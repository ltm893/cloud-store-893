#!/usr/bin/env bash
# Shared ADB wallet helpers for scripts/db/*.sh

ADB_GENERATED_WALLET_PASSWORD="${ADB_GENERATED_WALLET_PASSWORD:-WalletTemp1!}"

adb_wallet_cache_path() {
  printf '%s/wallet/adb.zip' "${PROJECT_ROOT:?PROJECT_ROOT required}"
}

adb_wallet_source_file() {
  printf '%s/wallet/.adb-wallet-source' "${PROJECT_ROOT}"
}

adb_wallet_print_failure_help() {
  cat <<'EOF' >&2
[error] Could not obtain an ADB wallet zip.

Option A — Cache a Console wallet (recommended when OCI API returns HTTP 500):
  1. OCI Console → Autonomous Database → your DB → Database connection → Download wallet
  2. cp ~/Downloads/Wallet_*.zip wallet/adb.zip
  3. export ADB_WALLET_PASSWORD='the-password-you-set-in-console'
  4. ./scripts/db/run-sql.sh your-script.sql

Option B — Pin any wallet zip:
  export ADB_WALLET_ZIP=/path/to/Wallet_CLOUDSTORE893.zip
  export ADB_WALLET_PASSWORD='your-wallet-zip-password'
  ./scripts/db/run-sql.sh your-script.sql

Option C — Pre-download via OCI CLI (retries, saves wallet/adb.zip):
  ./scripts/db/download-adb-wallet.sh
  ./scripts/db/run-sql.sh your-script.sql

Option D — No wallet (Database Actions):
  OCI Console → Database Actions → SQL → Run your .sql as ADMIN

EOF
}

adb_wallet_resolve_zip() {
  local explicit="${1:-}"

  if [[ -n "${explicit}" ]]; then
    [[ -f "${explicit}" ]] || return 1
    printf '%s' "${explicit}"
    return 0
  fi

  if [[ -n "${ADB_WALLET_ZIP:-}" ]]; then
    [[ -f "${ADB_WALLET_ZIP}" ]] || return 1
    printf '%s' "${ADB_WALLET_ZIP}"
    return 0
  fi

  local cached
  cached="$(adb_wallet_cache_path)"
  if [[ -f "${cached}" ]]; then
    printf '%s' "${cached}"
    return 0
  fi

  return 1
}

# Resolve wallet zip: explicit/cache/env, then OCI download to cache or temp_zip.
# Prints wallet path on stdout. temp_zip is optional fallback (e.g. mktemp wallet.zip).
adb_wallet_obtain_zip() {
  local explicit="${1:-}"
  local adb_ocid="$2"
  local temp_zip="${3:-}"

  local resolved cached
  if resolved="$(adb_wallet_resolve_zip "${explicit}")"; then
    printf '%s' "${resolved}"
    return 0
  fi

  cached="$(adb_wallet_cache_path)"
  if adb_wallet_download_oci "${cached}" "${adb_ocid}"; then
    printf '%s' "${cached}"
    return 0
  fi

  if [[ -n "${temp_zip}" ]] && adb_wallet_download_oci "${temp_zip}" "${adb_ocid}"; then
    printf '%s' "${temp_zip}"
    return 0
  fi

  return 1
}

adb_wallet_download_oci() {
  local dest_zip="$1"
  local adb_ocid="$2"
  local attempt max_attempts=3
  local dest_dir
  dest_dir="$(dirname "${dest_zip}")"

  mkdir -p "${dest_dir}"
  for attempt in 1 2 3; do
    if oci db autonomous-database generate-wallet \
      --autonomous-database-id "${adb_ocid}" \
      --password "${ADB_GENERATED_WALLET_PASSWORD}" \
      --file "${dest_zip}"; then
      printf 'oci-cli\n' > "$(adb_wallet_source_file)"
      return 0
    fi
    if [[ "${attempt}" -lt "${max_attempts}" ]]; then
      printf '[warn] generate-wallet failed (attempt %s/%s); retrying in %ss…\n' \
        "${attempt}" "${max_attempts}" "$((attempt * 5))" >&2
      sleep $((attempt * 5))
    fi
  done
  return 1
}

adb_wallet_password_for_zip() {
  local zip="$1"

  if [[ -n "${ADB_WALLET_PASSWORD:-}" ]]; then
    printf '%s' "${ADB_WALLET_PASSWORD}"
    return 0
  fi

  local source_file cached
  source_file="$(adb_wallet_source_file)"
  cached="$(adb_wallet_cache_path)"
  if [[ -f "${source_file}" ]] && [[ "$(tr -d '\r\n' < "${source_file}")" == oci-cli ]] \
    && [[ "${zip}" == "${cached}" ]]; then
    printf '%s' "${ADB_GENERATED_WALLET_PASSWORD}"
    return 0
  fi

  return 1
}

adb_wallet_run_sqlcl() {
  local sql_cmd="$1"
  local wallet_zip="$2"
  local adb_password="$3"
  local db_service="$4"
  local sql_file="$5"
  local wallet_password
  local wrapper_sql
  local wrapper_dir

  if ! wallet_password="$(adb_wallet_password_for_zip "${wallet_zip}")"; then
    if [[ "${ADB_NONINTERACTIVE:-0}" == 1 ]]; then
      printf '[error] Set ADB_WALLET_PASSWORD for wallet zip %s (non-interactive mode)\n' "${wallet_zip}" >&2
      return 1
    fi
    "${sql_cmd}" -cloudconfig "${wallet_zip}" \
      "admin/${adb_password}@${db_service}" \
      @"${sql_file}"
    return $?
  fi

  # Wrapper adds EXIT so SQLcl does not re-read the wallet password from stdin as a command.
  wrapper_dir="$(mktemp -d)"
  wrapper_sql="${wrapper_dir}/run.sql"
  printf '@%s\nexit\n' "${sql_file}" > "${wrapper_sql}"
  "${sql_cmd}" -cloudconfig "${wallet_zip}" \
    "admin/${adb_password}@${db_service}" \
    @"${wrapper_sql}" <<< "${wallet_password}"
  local status=$?
  rm -rf "${wrapper_dir}"
  return "${status}"
}
