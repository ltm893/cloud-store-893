#!/usr/bin/env bash
# Shared helpers: warn when Terraform will replace the OCI container instance (new public IP).
# Source from other scripts — do not run directly.

# Print current reachable public IP(s) for the app (best effort).
oci_ip_print_status() {
  local tf_dir="${1:?tf_dir required}"
  local port="${APP_PORT:-3000}"

  echo ""
  echo "── Current app network (best effort) ──"

  if [[ -d "$tf_dir" ]] && command -v terraform >/dev/null 2>&1; then
    local tf_url ocid
    tf_url="$(cd "$tf_dir" && terraform output -raw app_url 2>/dev/null || true)"
    ocid="$(cd "$tf_dir" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
    [[ -n "$tf_url" ]] && echo "  terraform app_url:     $tf_url"
    [[ -n "$ocid" ]] && echo "  container_instance:    $ocid"
  fi

  if [[ -n "${ocid:-}" ]] && command -v oci >/dev/null 2>&1; then
    local vnic_id live_ip
    vnic_id="$(oci container-instances container-instance get \
      --container-instance-id "$ocid" \
      --query 'data.vnics[0]."vnic-id"' \
      --raw-output 2>/dev/null || true)"
    if [[ -n "$vnic_id" && "$vnic_id" != "null" ]]; then
      live_ip="$(oci network vnic get \
        --vnic-id "$vnic_id" \
        --query 'data."public-ip"' \
        --raw-output 2>/dev/null || true)"
      [[ -n "$live_ip" && "$live_ip" != "null" ]] && echo "  live VNIC public IP:   http://${live_ip}:${port}/"
    fi
  fi

  if [[ -n "${CLOUD_STORE_RESERVED_PUBLIC_IP_OCID:-}" ]] && command -v oci >/dev/null 2>&1; then
    oci network public-ip get \
      --public-ip-id "$CLOUD_STORE_RESERVED_PUBLIC_IP_OCID" \
      --query 'data.{"reserved":"ip-address","state":"lifecycle-state","assigned":"private-ip-id"}' \
      --output table 2>/dev/null || true
  fi

  echo "  tip: ./scripts/oci/oci-app-url.sh  (live IP via OCI CLI)"
  echo ""
}

# Run terraform plan; return 0 if container instance unchanged, 1 if replace/update/create, 2 on plan error.
oci_ip_terraform_plan_container_change() {
  local tf_dir="${1:?tf_dir required}"
  local plan_file
  plan_file="$(mktemp "${TMPDIR:-/tmp}/cloud-store-tfplan.XXXXXX")"

  if ! command -v terraform >/dev/null 2>&1; then
    echo "warning: terraform not in PATH — skipping IP change check" >&2
    return 2
  fi

  local plan_out plan_ec=0
  set +e
  plan_out="$(cd "$tf_dir" && terraform plan -no-color -out="$plan_file" 2>&1)"
  plan_ec=$?
  set -e

  if [[ "$plan_ec" -ne 0 && "$plan_ec" -ne 2 ]]; then
    echo "$plan_out" >&2
    rm -f "$plan_file"
    return 2
  fi

  local replaces=false
  local changes=false

  if echo "$plan_out" | grep -q 'oci_container_instances_container_instance.main must be replaced'; then
    replaces=true
    changes=true
  elif echo "$plan_out" | grep -qE '# oci_container_instances_container_instance\.main will be (created|updated|replaced)'; then
    changes=true
    echo "$plan_out" | grep -q 'forces replacement' && replaces=true
  elif echo "$plan_out" | grep -q 'Plan: .* to add'; then
    if echo "$plan_out" | grep -qi 'container_instance'; then
      changes=true
    fi
  fi

  rm -f "$plan_file"

  if [[ "$changes" != "true" ]]; then
    echo "terraform plan: no container instance changes (public IP should stay the same)."
    return 0
  fi

  oci_ip_print_status "$tf_dir"

  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  WARNING: terraform apply will change the OCI container instance    ║"
  if [[ "$replaces" == "true" ]]; then
    echo "║  → Oracle replaces the instance (forces replacement).               ║"
  fi
  echo "║  → Expect a NEW ephemeral public IP on the new VNIC.                ║"
  echo "║  → A reserved public IP does NOT reattach automatically.            ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "After apply:"
  echo "  1. ./scripts/oci/oci-app-url.sh          # live IP (may differ from terraform output)"
  echo "  2. ./scripts/oci/reattach-reserved-ip.sh   # or pass --recover-network to deploy/apply scripts"
  echo "  3. Update IdCS redirect URIs if using raw IPs — ./scripts/oci/idp-update-redirect-uris.sh"
  echo "  4. cloud-store-refresh-ocid  # or: export CLOUD_STORE_OCID=\$(cd terraform && terraform output -raw container_instance_ocid)"
  echo ""
  echo "For app CODE only (no env change): docker push + ./scripts/oci/restart-container-instance.sh"
  echo "  (does not replace the instance — reserved IP stays attached)"
  echo ""

  return 1
}

# Prompt unless AUTO_YES=1 or second arg is --yes
oci_ip_confirm_apply_or_exit() {
  local auto_yes="${1:-}"
  if [[ "$auto_yes" == "--yes" || "${AUTO_YES:-}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "error: container instance change detected; re-run with --yes or AUTO_YES=1 to apply non-interactively" >&2
    exit 1
  fi
  read -r -p "Continue with terraform apply? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) echo "Aborted."; exit 1 ;;
  esac
}

# After apply when the container instance was replaced: offer or run reserved-IP reattach.
# Args: $1 = --recover-network (auto-run) or empty; $2 = scripts/oci directory.
oci_ip_offer_recover_network() {
  local auto_recover="${1:-}"
  local oci_scripts_dir="${2:?oci_scripts_dir required}"
  local reattach="$oci_scripts_dir/reattach-reserved-ip.sh"

  if [[ -z "${CLOUD_STORE_RESERVED_PUBLIC_IP_OCID:-}" ]]; then
    echo ""
    echo "Post-apply: container instance changed — if hostname times out, reattach reserved IP:"
    echo "  export CLOUD_STORE_RESERVED_PUBLIC_IP_OCID=...   # see docs/oci-network-recovery.md"
    echo "  ./scripts/oci/reattach-reserved-ip.sh"
    return 0
  fi

  if [[ ! -f "$reattach" ]]; then
    echo ""
    echo "Post-apply: run ./scripts/oci/reattach-reserved-ip.sh if oci.cloudstore893.com times out"
    return 0
  fi

  echo ""
  echo "Container instance was replaced — reserved public IP may need reattach."

  if [[ "$auto_recover" == "--recover-network" || "${RECOVER_NETWORK:-}" == "1" ]]; then
    "$reattach" --yes --refresh-ocid
    return $?
  fi

  if [[ ! -t 0 ]]; then
    echo "Run: ./scripts/oci/reattach-reserved-ip.sh  (or re-run with --recover-network)"
    return 0
  fi

  read -r -p "Run ./scripts/oci/reattach-reserved-ip.sh now? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) "$reattach" --yes --refresh-ocid ;;
    *) echo "Skipped. Run ./scripts/oci/reattach-reserved-ip.sh if the hostname times out." ;;
  esac
}
