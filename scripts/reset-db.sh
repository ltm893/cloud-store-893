#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${PROJECT_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"

info() { printf '[info] %s\n' "$1"; }
warn() { printf '[warn] %s\n' "$1"; }
error() { printf '[error] %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reset-db.sh [--yes]

What it does:
  - Downloads a temporary Autonomous DB wallet via OCI CLI
  - Connects with SQLcl
  - Runs scripts/seed.sql to drop and recreate the schema from scratch

Requirements:
  - terraform
  - oci CLI
  - SQLcl (`sql`)
  - terraform/terraform.tfvars with `adb_admin_password`

Notes:
  - This is destructive. It deletes existing products, customers, cart items, sales,
    sale items, and sale payments before recreating them.
  - `scripts/seed.sql` is SQL, not a shell script. Do not run it directly with bash.
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      CONFIRMED=1
      shift
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

command -v terraform >/dev/null 2>&1 || error "terraform not found"
command -v oci >/dev/null 2>&1 || error "oci CLI not found"
SQL_CMD="$(find_sqlcl || true)"
[[ -n "${SQL_CMD}" ]] || error "SQLcl not found. Install it with ./scripts/install-sqlcl.sh"

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
  # ORDS may return 401/404 at the base path while still being reachable.
  # Treat any HTTP response code as "ready" and only retry on connection failures (000).
  until [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${ORDS_URL}" || true)" != "000" ]]; do
    attempts=$((attempts + 1))
    [[ "${attempts}" -lt "${max_attempts}" ]] || error "ORDS not ready after $((max_attempts * 5)) seconds"
    sleep 5
  done
fi

WALLET_DIR="$(mktemp -d)"
WALLET_ZIP="${WALLET_DIR}/wallet.zip"
cleanup() {
  rm -rf "${WALLET_DIR}"
}
trap cleanup EXIT

info "Downloading temporary ADB wallet"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "${ADB_OCID}" \
  --password "WalletTemp1!" \
  --file "${WALLET_ZIP}" >/dev/null

info "Running scripts/seed.sql against ${DB_SERVICE}"
"${SQL_CMD}" -cloudconfig "${WALLET_ZIP}" \
  "admin/${ADB_PASSWORD}@${DB_SERVICE}" \
  @"${SCRIPT_DIR}/seed.sql"

info "Database reset complete"
