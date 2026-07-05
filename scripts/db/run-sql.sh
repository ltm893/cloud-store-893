#!/usr/bin/env bash
# Run a SQL script against live ADB via SQLcl + wallet (non-destructive by itself).
#
#   ./scripts/db/run-sql.sh scripts/db/verify-test-sales-matrix.sql
#   ./scripts/db/run-sql.sh --wallet-zip wallet/adb.zip path/to/script.sql

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
  ./scripts/db/run-sql.sh [--wallet-zip PATH] SQL_FILE

Run SQL_FILE as ADMIN via SQLcl using an ADB wallet zip.

Examples:
  ./scripts/db/run-sql.sh scripts/db/verify-test-sales-matrix.sql
  npm run verify:test-sales-matrix

Wallet resolution (first match wins):
  1. --wallet-zip PATH
  2. ADB_WALLET_ZIP in environment or .env
  3. wallet/adb.zip (Console download or download-adb-wallet.sh)
  4. OCI CLI generate-wallet (3 retries) → caches wallet/adb.zip

Requirements:
  - terraform, oci CLI, SQLcl (`sql`)
  - terraform/terraform.tfvars with adb_admin_password

Wallet passwords:
  - OCI-generated wallet/adb.zip uses WalletTemp1!
  - Console wallet: export ADB_WALLET_PASSWORD='your-zip-password'
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

WALLET_ZIP_ARG=""
SQL_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet-zip)
      WALLET_ZIP_ARG="${2:-}"
      [[ -n "${WALLET_ZIP_ARG}" ]] || error "--wallet-zip requires a path"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      ;;
    -*)
      usage
      error "Unknown argument: $1"
      ;;
    *)
      if [[ -n "${SQL_FILE}" ]]; then
        error "Only one SQL file allowed (got: ${SQL_FILE} and $1)"
      fi
      SQL_FILE="$1"
      shift
      ;;
  esac
done

[[ -n "${SQL_FILE}" ]] || { usage; error "SQL_FILE is required"; }
[[ -f "${SQL_FILE}" ]] || error "SQL file not found: ${SQL_FILE}"

command -v oci >/dev/null 2>&1 || error "oci CLI not found"
SQL_CMD="$(find_sqlcl || true)"
[[ -n "${SQL_CMD}" ]] || error "SQLcl not found. Install with ./scripts/tools/install-sqlcl.sh"

ADB_OCID="${ADB_OCID:-$(cd "${TF_DIR}" && terraform output -raw adb_ocid 2>/dev/null || true)}"
ADB_PASSWORD="${ADB_ADMIN_PASSWORD:-$(tfvar "adb_admin_password" || true)}"
DB_NAME="${ADB_DB_NAME:-$(tfvar "adb_db_name" || true)}"

[[ -n "${ADB_OCID}" ]] || error "Unable to read adb_ocid from terraform output"
[[ -n "${ADB_PASSWORD}" ]] || error "Unable to read adb_admin_password from terraform/terraform.tfvars"
[[ -n "${DB_NAME}" ]] || DB_NAME="CLOUDSTORE893"

DB_NAME_LOWER="$(printf '%s' "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"
DB_SERVICE="${ADB_DB_SERVICE:-${DB_NAME_LOWER}_high}"

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

if ! adb_wallet_password_for_zip "${WALLET_ZIP}" >/dev/null 2>&1; then
  warn "Console wallet: set ADB_WALLET_PASSWORD or SQLcl will prompt for zip password"
fi

info "Running ${SQL_FILE} against ${DB_SERVICE}"
adb_wallet_run_sqlcl "${SQL_CMD}" "${WALLET_ZIP}" "${ADB_PASSWORD}" "${DB_SERVICE}" "${SQL_FILE}"

info "SQL complete"
