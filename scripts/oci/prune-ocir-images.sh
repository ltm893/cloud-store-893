#!/usr/bin/env bash
# Delete stale OCIR images in the cloud-store repository.
#
# Default is dry-run. Always keeps protected tags (latest, cert-renew, Terraform
# ocir_image_tag) plus the N most recent other tagged deploy images. Deletes
# untagged/orphan manifests and older dated tags.
#
# Usage:
#   ./scripts/oci/prune-ocir-images.sh                    # dry-run
#   ./scripts/oci/prune-ocir-images.sh --apply            # delete
#   ./scripts/oci/prune-ocir-images.sh --keep-recent 5
#   ./scripts/oci/prune-ocir-images.sh --keep my-feature-tag
#   KEEP_RECENT_N=2 ./scripts/oci/prune-ocir-images.sh --apply
#
# Requires: oci CLI, python3, terraform state (for compartment + repo name).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"

APPLY=false
KEEP_RECENT_N="${KEEP_RECENT_N:-3}"
EXTRA_KEEP=()
REPO_NAME="${OCIR_REPOSITORY_NAME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply|--yes) APPLY=true ;;
    --keep-recent)
      shift
      KEEP_RECENT_N="${1:?--keep-recent requires a number}"
      ;;
    --keep)
      shift
      EXTRA_KEEP+=("${1:?--keep requires a tag name}")
      ;;
    --repository)
      shift
      REPO_NAME="${1:?--repository requires a name}"
      ;;
    --help|-h)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1 (use --help)" >&2
      exit 1
      ;;
  esac
  shift
done

if ! command -v oci >/dev/null 2>&1; then
  echo "error: oci CLI not found" >&2
  exit 1
fi

if [[ ! -d "$TF_DIR" ]]; then
  echo "error: terraform directory not found: $TF_DIR" >&2
  exit 1
fi

COMPARTMENT_OCID="$(cd "$TF_DIR" && terraform output -raw compartment_ocid 2>/dev/null || true)"
if [[ -z "$COMPARTMENT_OCID" ]]; then
  echo "error: could not read compartment_ocid from terraform output" >&2
  exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
  REPO_NAME="$(cd "$TF_DIR" && terraform output -raw ocir_image_path 2>/dev/null | sed -E 's#.*/([^/:]+):.*#\1#')"
fi
if [[ -z "$REPO_NAME" ]]; then
  REPO_NAME="${CLOUD_STORE_COMPARTMENT_NAME:-cloud-store}"
fi

TF_IMAGE_TAG="$(cd "$TF_DIR" && terraform output -raw ocir_image_path 2>/dev/null | sed -E 's/.*://')"
CERT_RENEW_TAG="$(cd "$TF_DIR" && terraform console -var-file=terraform.tfvars -var-file=container_env.auto.tfvars <<< 'var.cert_renew_image_tag' 2>/dev/null | tr -d '"' || true)"
CERT_RENEW_TAG="${CERT_RENEW_TAG:-cert-renew}"

PROTECTED_TAGS=(latest "$CERT_RENEW_TAG")
if [[ -n "${TF_IMAGE_TAG:-}" && "$TF_IMAGE_TAG" != "null" ]]; then
  PROTECTED_TAGS+=("$TF_IMAGE_TAG")
fi
if ((${#EXTRA_KEEP[@]} > 0)); then
  PROTECTED_TAGS+=("${EXTRA_KEEP[@]}")
fi
# Dedupe (bash 3.2–safe)
PROTECTED_CSV=""
_seen=""
for t in "${PROTECTED_TAGS[@]}"; do
  case "$_seen" in *"|$t|"*) continue ;; esac
  _seen="${_seen}|${t}|"
  PROTECTED_CSV="${PROTECTED_CSV:+$PROTECTED_CSV,}$t"
done

echo "==> Repository: ${REPO_NAME}"
echo "==> Compartment: ${COMPARTMENT_OCID}"
echo "==> Protected tags: ${PROTECTED_CSV}"
echo "==> Keep ${KEEP_RECENT_N} most recent deploy tag(s) (besides protected)"
echo "==> Mode: $(if $APPLY; then echo APPLY; else echo dry-run; fi)"
echo ""

LIST_JSON="$(mktemp)"
trap 'rm -f "$LIST_JSON"' EXIT

oci artifacts container image list \
  --compartment-id "$COMPARTMENT_OCID" \
  --repository-name "$REPO_NAME" \
  --all \
  --output json >"$LIST_JSON"

export LIST_JSON PROTECTED_CSV KEEP_RECENT_N APPLY
python3 <<'PY'
import json
import os
import subprocess
import sys

list_path = os.environ["LIST_JSON"]
protected = {t.strip() for t in os.environ["PROTECTED_CSV"].split(",") if t.strip()}
keep_recent = int(os.environ["KEEP_RECENT_N"])
apply = os.environ.get("APPLY", "false").lower() == "true"

with open(list_path, encoding="utf-8") as fh:
    payload = json.load(fh)

items = payload.get("data", payload)
if isinstance(items, dict):
    items = items.get("items", [])

if not items:
    print("No images found.")
    sys.exit(0)

tagged = []
untagged = []
for row in items:
    version = row.get("version")
    entry = {
        "id": row["id"],
        "digest": row.get("digest", ""),
        "version": version,
        "created": row.get("time-created", ""),
        "display": row.get("display-name", ""),
    }
    if version:
        tagged.append(entry)
    else:
        untagged.append(entry)

deploy_candidates = [t for t in tagged if t["version"] not in protected]
deploy_candidates.sort(key=lambda r: r["created"], reverse=True)
recent_keep = {r["version"] for r in deploy_candidates[:keep_recent]}

keep_ids = set()
keep_tags = set(protected) | recent_keep

for row in tagged:
    if row["version"] in keep_tags:
        keep_ids.add(row["id"])

to_delete = []
for row in tagged + untagged:
    if row["id"] not in keep_ids:
        to_delete.append(row)

to_delete.sort(key=lambda r: (r["version"] or "", r["created"]))

print(f"Total images: {len(items)}")
print(f"  tagged:   {len(tagged)}")
print(f"  untagged: {len(untagged)}")
print(f"Keeping {len(keep_ids)} image(s) — tags: {', '.join(sorted(keep_tags))}")
print(f"Would delete {len(to_delete)} image(s)")
print()

if not to_delete:
    print("Nothing to prune.")
    sys.exit(0)

print("Delete list:")
for row in to_delete:
    tag = row["version"] or "<untagged>"
    print(f"  {tag:<40} {row['created'][:10]}  {row['digest'][:19]}…")

if not apply:
    print()
    print("Dry-run only. Re-run with --apply to delete.")
    sys.exit(0)

print()
failures = 0
for row in to_delete:
    tag = row["version"] or "<untagged>"
    try:
        subprocess.run(
            ["oci", "artifacts", "container", "image", "delete", "--image-id", row["id"], "--force"],
            check=True,
            capture_output=True,
            text=True,
        )
        print(f"deleted  {tag}")
    except subprocess.CalledProcessError as err:
        failures += 1
        msg = (err.stderr or err.stdout or str(err)).strip().splitlines()
        print(f"FAILED   {tag}: {msg[0] if msg else err}", file=sys.stderr)

print()
if failures:
    print(f"Done with {failures} failure(s).", file=sys.stderr)
    sys.exit(1)
print(f"Deleted {len(to_delete)} image(s).")
PY
