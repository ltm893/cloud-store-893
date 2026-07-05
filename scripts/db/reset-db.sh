#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${PROJECT_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"
# shellcheck source=scripts/db/lib/adb-wallet.sh
source "${SCRIPT_DIR}/lib/adb-wallet.sh"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/.env"
fi

info() { printf '[info] %s\n' "$1"; }
warn() { printf '[warn] %s\n' "$1"; }
error() { printf '[error] %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./scripts/db/reset-db.sh [--yes] [--wallet-zip PATH]

What it does:
  - Connects with SQLcl using an ADB wallet zip
  - Runs scripts/db/seed.sql to drop and recreate the schema from scratch

Wallet resolution (first match wins):
  1. --wallet-zip PATH
  2. ADB_WALLET_ZIP in environment or .env
  3. wallet/adb.zip in repo root (from Console download or download-adb-wallet.sh)
  4. OCI CLI generate-wallet (3 retries) → caches wallet/adb.zip

Requirements:
  - terraform, oci CLI, SQLcl (`sql`)
  - terraform/terraform.tfvars with adb_admin_password

Wallet passwords:
  - OCI-generated wallet/adb.zip uses WalletTemp1! (see download-adb-wallet.sh)
  - Console-downloaded wallet: export ADB_WALLET_PASSWORD='your-zip-password'

If generate-wallet keeps failing (HTTP 500):
  - ./scripts/db/download-adb-wallet.sh   OR
  - cp ~/Downloads/Wallet_*.zip wallet/adb.zip + ADB_WALLET_PASSWORD  OR
  - Database Actions → Run scripts/db/seed.sql
  - ./scripts/db/run-sql.sh scripts/db/seed.sql

Notes:
  - Destructive: drops products, customers, cart, sales, tills, approvals, etc.
  - scripts/db/seed.sql is SQL — do not run it with bash.
EOF
}

find_sqlcl() {
  if command -v sql >/dev/null 2>&1; then
    command -v sql
    return
  fi
  if [[ -x "/opt/sqlcl/bin/sql" ]]; then
    printf '/opt/sqlcl/bin/sql\n'
    return
  fi
  return 1
}

tfvar() {
  local key="$1"
  [[ -f "${TFVARS}" ]] || return 1
  awk -F '=' -v key="${key}" '
    $1 ~ ("^[[:space:]]*" key "[[:space:]]*$") {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "${TFVARS}"
}

CONFIRMED=0
WALLET_ZIP_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      CONFIRMED=1
      shift
      ;;
    --wallet-zip)
      WALLET_ZIP_ARG="${2:-}"
      [[ -n "${WALLET_ZIP_ARG}" ]] || error "--wallet-zip requires a path"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      error "Unknown argument: $1"
      ;;
  esac
done

[[ "${CONFIRMED}" -eq 1 ]] && ADB_NONINTERACTIVE=1

command -v terraform >/dev/null 2>&1 || error "terraform not found"
command -v oci >/dev/null 2>&1 || error "oci CLI not found"
SQL_CMD="$(find_sqlcl || true)"
[[ -n "${SQL_CMD}" ]] || error "SQLcl not found. Install it with ./scripts/tools/install-sqlcl.sh"

ADB_OCID="${ADB_OCID:-$(cd "${TF_DIR}" && terraform output -raw adb_ocid 2>/dev/null || true)}"
ORDS_URL="${ORDS_URL:-$(cd "${TF_DIR}" && terraform output -raw ords_base_url 2>/dev/null || true)}"
ADB_PASSWORD="${ADB_ADMIN_PASSWORD:-$(tfvar "adb_admin_password" || true)}"
DB_NAME="${ADB_DB_NAME:-$(tfvar "adb_db_name" || true)}"

[[ -n "${ADB_OCID}" ]] || error "Unable to read adb_ocid from terraform output"
[[ -n "${ADB_PASSWORD}" ]] || error "Unable to read adb_admin_password from terraform/terraform.tfvars"
[[ -n "${DB_NAME}" ]] || DB_NAME="CLOUDSTORE893"

DB_NAME_LOWER="$(printf '%s' "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"
DB_SERVICE="${ADB_DB_SERVICE:-${DB_NAME_LOWER}_high}"

if [[ "${CONFIRMED}" -eq 0 ]]; then
  warn "This will DELETE all current test data and rebuild the database schema."
  read -r -p "Continue with full reset? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES)
      ;;
    *)
      error "Reset cancelled"
      ;;
  esac
fi

if [[ -n "${ORDS_URL}" ]]; then
  info "Waiting for ORDS at ${ORDS_URL}"
  attempts=0
  max_attempts=24
  until [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${ORDS_URL}" || true)" != "000" ]]; do
    attempts=$((attempts + 1))
    [[ "${attempts}" -lt "${max_attempts}" ]] || error "ORDS not ready after $((max_attempts * 5)) seconds"
    sleep 5
  done
fi

WALLET_DIR="$(mktemp -d)"
TEMP_WALLET_ZIP="${WALLET_DIR}/wallet.zip"
cleanup() {
  rm -rf "${WALLET_DIR}"
}
trap cleanup EXIT

WALLET_ZIP=""
if resolved="$(adb_wallet_resolve_zip "${WALLET_ZIP_ARG}")"; then
  WALLET_ZIP="${resolved}"
  info "Using wallet: ${WALLET_ZIP}"
else
  info "No cached wallet; trying OCI generate-wallet (3 attempts) → wallet/adb.zip"
  if WALLET_ZIP="$(adb_wallet_obtain_zip "${WALLET_ZIP_ARG}" "${ADB_OCID}" "${TEMP_WALLET_ZIP}")"; then
    if [[ "${WALLET_ZIP}" == "$(adb_wallet_cache_path)" ]]; then
      trap - EXIT
      info "Cached wallet at ${WALLET_ZIP}"
    else
      info "Using temporary OCI wallet"
    fi
  else
    adb_wallet_print_failure_help
    error "Could not obtain ADB wallet"
  fi
fi

if [[ "${CONFIRMED}" -eq 1 ]] && ! adb_wallet_password_for_zip "${WALLET_ZIP}" >/dev/null 2>&1; then
  error "Set ADB_WALLET_PASSWORD for wallet ${WALLET_ZIP} (required with --yes for Console wallets)"
fi

info "Running scripts/db/seed.sql against ${DB_SERVICE}"
adb_wallet_run_sqlcl "${SQL_CMD}" "${WALLET_ZIP}" "${ADB_PASSWORD}" "${DB_SERVICE}" "${SCRIPT_DIR}/seed.sql"

info "Database reset complete"
