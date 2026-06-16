#!/usr/bin/env bash
# Truncate till/session approval tables (pos_sessions, tills, till_open_approvals, till_close_approvals).
#
# Use between test runs to clear stale pending approvals and active tills.
# Does NOT delete products, sales, cart items, or customers.
#
# Usage:
#   ./scripts/truncate-shift-auth-tables.sh          # interactive confirm
#   ./scripts/truncate-shift-auth-tables.sh --yes    # skip confirm
#
# Requires: oci CLI, SQLcl, terraform/terraform.tfvars (adb_admin_password)

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
  ./scripts/truncate-shift-auth-tables.sh [--yes]

Truncates (empties):
  - till_open_approvals
  - pos_sessions
  - tills
  - till_close_approvals

Leaves products, customers, sales, cart, and inventory unchanged.

After running:
  - Active cashier sessions on the server are stale; sign out on tablets / iPad.
  - Next cashier sign-in needs a fresh supervisor approval and opening till (if configured).
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

command -v oci >/dev/null 2>&1 || error "oci CLI not found"
SQL_CMD="$(find_sqlcl || true)"
[[ -n "${SQL_CMD}" ]] || error "SQLcl not found. Install with ./scripts/install-sqlcl.sh"

ADB_OCID="${ADB_OCID:-$(cd "${TF_DIR}" 2>/dev/null && terraform output -raw adb_ocid 2>/dev/null || true)}"
ADB_PASSWORD="${ADB_ADMIN_PASSWORD:-$(tfvar "adb_admin_password" || true)}"
DB_NAME="${ADB_DB_NAME:-$(tfvar "adb_db_name" || true)}"

[[ -n "${ADB_OCID}" ]] || error "Unable to read adb_ocid (set ADB_OCID or run from terraform-configured repo)"
[[ -n "${ADB_PASSWORD}" ]] || error "Unable to read adb_admin_password from terraform/terraform.tfvars"

[[ -n "${DB_NAME}" ]] || DB_NAME="CLOUDSTORE893"
DB_NAME_LOWER="$(printf '%s' "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"
DB_SERVICE="${ADB_DB_SERVICE:-${DB_NAME_LOWER}_high}"

if [[ "${CONFIRMED}" -eq 0 ]]; then
  warn "This will DELETE all rows in:"
  warn "  - till_close_approvals"
  warn "  - tills"
  warn "  - till_open_approvals"
  warn "  - pos_sessions"
  read -r -p "Continue? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) error "Cancelled" ;;
  esac
fi

WALLET_DIR="$(mktemp -d)"
WALLET_ZIP="${WALLET_DIR}/wallet.zip"
trap 'rm -rf "${WALLET_DIR}"' EXIT

info "Downloading temporary ADB wallet"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "${ADB_OCID}" \
  --password "WalletTemp1!" \
  --file "${WALLET_ZIP}" >/dev/null

info "Truncating shift/auth tables on ${DB_SERVICE}"
"${SQL_CMD}" -cloudconfig "${WALLET_ZIP}" \
  "admin/${ADB_PASSWORD}@${DB_SERVICE}" \
  @"${SCRIPT_DIR}/truncate-shift-auth-tables.sql"

info "Complete. Restart cashier sessions on tablets if any were signed in."
