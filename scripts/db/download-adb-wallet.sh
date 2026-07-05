#!/usr/bin/env bash
# Download (or refresh) wallet/adb.zip for SQLcl scripts. Retries OCI generate-wallet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${PROJECT_ROOT}/terraform"
# shellcheck source=scripts/db/lib/adb-wallet.sh
source "${SCRIPT_DIR}/lib/adb-wallet.sh"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/.env"
fi

info() { printf '[info] %s\n' "$1"; }
error() { printf '[error] %s\n' "$1" >&2; exit 1; }

ADB_OCID="${ADB_OCID:-$(cd "${TF_DIR}" && terraform output -raw adb_ocid 2>/dev/null || true)}"
[[ -n "${ADB_OCID}" ]] || error "Unable to read adb_ocid from terraform output"

DEST="$(adb_wallet_cache_path)"
info "Downloading ADB wallet to ${DEST} (OCI generate-wallet; up to 3 attempts)"
if adb_wallet_download_oci "${DEST}" "${ADB_OCID}"; then
  info "Wallet saved. SQLcl wallet password: ${ADB_GENERATED_WALLET_PASSWORD}"
  info "Run: ./scripts/db/reset-db.sh --yes"
  exit 0
fi

adb_wallet_print_failure_help
error "generate-wallet failed after retries"
