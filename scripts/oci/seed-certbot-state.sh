#!/usr/bin/env bash
# Upload local certbot state (from Mac) to Object Storage for the cert-renew function.
#
# Run once after your first successful certbot certonly on your laptop.
#
# Usage:
#   ./scripts/oci/seed-certbot-state.sh
#   CERTBOT_LOCAL_DIR=~/path/to/config ./scripts/oci/seed-certbot-state.sh
#
# Requires: oci CLI, terraform outputs (bucket name), local tree:
#   certs/certbot/config, work, logs (default CERTBOT_LOCAL_DIR parent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"

CERTBOT_ROOT="${CERTBOT_LOCAL_DIR:-$PROJECT_ROOT/certs/certbot}"
STATE_OBJECT="${CERTBOT_STATE_OBJECT:-certbot-state.tar.gz}"

if [[ ! -d "$CERTBOT_ROOT/config" ]]; then
  echo "error: missing $CERTBOT_ROOT/config — run certbot certonly on your Mac first" >&2
  exit 1
fi

BUCKET="${CERTBOT_STATE_BUCKET:-}"
if [[ -z "$BUCKET" ]]; then
  BUCKET="$(cd "$TF_DIR" && terraform output -raw certbot_state_bucket 2>/dev/null || true)"
fi
if [[ -z "$BUCKET" || "$BUCKET" == "null" ]]; then
  BUCKET="${CERTBOT_STATE_BUCKET:-cloud-store-certbot-state}"
  echo "warn: using default bucket name $BUCKET (set enable_cert_renew_function or CERTBOT_STATE_BUCKET)" >&2
fi

NS="$(oci os ns get --query 'data' --raw-output 2>/dev/null || true)"
if [[ -z "$NS" ]]; then
  echo "error: could not read Object Storage namespace (oci os ns get)" >&2
  exit 1
fi

echo "==> Packing certbot state from $CERTBOT_ROOT"
COPYFILE_DISABLE=1 tar czf /tmp/certbot-state.tar.gz -C "$CERTBOT_ROOT" \
  --exclude='._*' \
  --exclude='.DS_Store' \
  .

echo "==> Uploading to oci://${NS}/${BUCKET}/${STATE_OBJECT}"
oci os object put \
  --bucket-name "$BUCKET" \
  --name "$STATE_OBJECT" \
  --file /tmp/certbot-state.tar.gz \
  --force

echo "✅ Seeded ${BUCKET}/${STATE_OBJECT}"
