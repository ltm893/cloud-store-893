#!/usr/bin/env bash
# Non-destructive: add till columns to login_approval_requests + refresh ORDS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TF_DIR="${PROJECT_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"

info() { printf '[info] %s\n' "$1"; }
error() { printf '[error] %s\n' "$1" >&2; exit 1; }

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

command -v oci >/dev/null 2>&1 || error "oci CLI not found"
SQL_CMD="$(find_sqlcl || true)"
[[ -n "${SQL_CMD}" ]] || error "SQLcl not found. Install with ./scripts/tools/install-sqlcl.sh"

ADB_OCID="${ADB_OCID:-$(cd "${TF_DIR}" 2>/dev/null && terraform output -raw adb_ocid 2>/dev/null || true)}"
ADB_PASSWORD="${ADB_ADMIN_PASSWORD:-$(tfvar "adb_admin_password" || true)}"
DB_NAME="${ADB_DB_NAME:-$(tfvar "adb_db_name" || true)}"

[[ -n "${ADB_OCID}" ]] || error "Unable to read adb_ocid (set ADB_OCID or run from terraform-configured repo)"
[[ -n "${ADB_PASSWORD}" ]] || error "Unable to read adb_admin_password from terraform/terraform.tfvars"

[[ -n "${DB_NAME}" ]] || DB_NAME="CLOUDSTORE893"
DB_NAME_LOWER="$(printf '%s' "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"
DB_SERVICE="${ADB_DB_SERVICE:-${DB_NAME_LOWER}_high}"

WALLET_DIR="$(mktemp -d)"
WALLET_ZIP="${WALLET_DIR}/wallet.zip"
trap 'rm -rf "${WALLET_DIR}"' EXIT

info "Downloading temporary ADB wallet"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "${ADB_OCID}" \
  --password "WalletTemp1!" \
  --file "${WALLET_ZIP}" >/dev/null

info "Running scripts/db/migrate/migrate-login-approval-till.sql against ${DB_SERVICE}"
"${SQL_CMD}" -cloudconfig "${WALLET_ZIP}" \
  "admin/${ADB_PASSWORD}@${DB_SERVICE}" \
  @"${SCRIPT_DIR}/migrate-login-approval-till.sql"

info "Migration complete. Deny any stale pending logins and have cashiers sign in again."
