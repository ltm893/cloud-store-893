#!/usr/bin/env bash
# Shared env + paths for dev IdP bootstrap (source from bootstrap-dev.sh).

# Map display names / legacy values to oci iam domain create --license-type slugs.
idp_normalize_license_type() {
  local raw="${1:-external-active-user}"
  local key
  key="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d ' _')"
  case "$key" in
    free) printf '%s' 'free' ;;
    premium) printf '%s' 'premium' ;;
    oracleappspremium) printf '%s' 'oracle-apps-premium' ;;
    externaluser) printf '%s' 'external-active-user' ;;  # legacy script default
    externalactiveuser) printf '%s' 'external-active-user' ;;
    external-user|external-active-user|oracle-apps-premium)
      printf '%s' "$key"
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

idp_env_init() {
  local project_root="${1:?project_root required}"
  IDP_PROJECT_ROOT="$project_root"
  IDP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  IDP_SCRIPTS_DIR="$(cd "$IDP_LIB_DIR/../.." && pwd)"
  IDP_STATE_DIR="$IDP_LIB_DIR/../state"
  IDP_STATE_FILE="$IDP_STATE_DIR/dev-domain.json"

  export CLOUD_STORE_ENV=dev
  # shellcheck source=../../lib/terraform-env.sh
  source "$IDP_SCRIPTS_DIR/lib/terraform-env.sh"
  cloud_store_resolve_tf_env "$IDP_PROJECT_ROOT"

  IDP_ENV_FILE="${IDP_ENV_FILE:-$IDP_PROJECT_ROOT/.env.dev}"
  IDP_ENV_EXAMPLE="$IDP_PROJECT_ROOT/.env.dev.example"

  IDP_DOMAIN_PREFIX="${IDP_DEV_DOMAIN_PREFIX:-cloud-store-app-}"
  IDP_LICENSE_TYPE="${IDP_DEV_LICENSE_TYPE:-external-active-user}"
  IDP_USER_EMAIL="${IDP_DEV_USER_EMAIL:-ltm893@icloud.com}"
  IDP_USER_GIVEN_NAME="${IDP_DEV_USER_GIVEN_NAME:-Dev}"
  IDP_USER_FAMILY_NAME="${IDP_DEV_USER_FAMILY_NAME:-User}"
  IDP_POS_APP_NAME="${IDP_DEV_POS_APP_NAME:-cloud-store-pos}"
  IDP_ADMIN_APP_NAME="${IDP_DEV_ADMIN_APP_NAME:-cloud-store-admin}"
  IDP_CASHIER_GROUP="${IDP_DEV_CASHIER_GROUP:-store-cashiers}"
  IDP_SUPERVISOR_GROUP="${IDP_DEV_SUPERVISOR_GROUP:-store-supervisors}"
  IDP_ADMIN_GROUP="${IDP_DEV_ADMIN_GROUP:-store-admins}"

  if [[ -f "$IDP_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck source=/dev/null
    source "$IDP_ENV_FILE"
    set +a
    IDP_USER_EMAIL="${IDP_DEV_USER_EMAIL:-$IDP_USER_EMAIL}"
    IDP_USER_GIVEN_NAME="${IDP_DEV_USER_GIVEN_NAME:-$IDP_USER_GIVEN_NAME}"
    IDP_USER_FAMILY_NAME="${IDP_DEV_USER_FAMILY_NAME:-$IDP_USER_FAMILY_NAME}"
  fi

  IDP_LICENSE_TYPE="$(idp_normalize_license_type "${IDP_DEV_LICENSE_TYPE:-$IDP_LICENSE_TYPE}")"

  IDP_REGION="$(awk -F '=' '/^[[:space:]]*region[[:space:]]*=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"|"$/, "", $2); print $2; exit }' "$CLOUD_STORE_TFVARS")"
  [[ -n "$IDP_REGION" ]] || IDP_REGION="${OCI_REGION:-us-ashburn-1}"

  IDP_COMPARTMENT_OCID="$(cloud_store_tf_output compartment_ocid)"
  if [[ -z "$IDP_COMPARTMENT_OCID" ]]; then
    echo "error: compartment_ocid not in dev terraform state — run ./scripts/oci/deploy-dev.sh first" >&2
    return 1
  fi

  mkdir -p "$IDP_STATE_DIR"
}

idp_require_tools() {
  command -v oci >/dev/null 2>&1 || { echo "error: oci CLI not found" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; return 1; }
  command -v openssl >/dev/null 2>&1 || { echo "error: openssl not found" >&2; return 1; }
}

idp_generate_password() {
  # Meets typical IDCS complexity: upper, lower, digit, symbol.
  # Avoid trailing '!' — breaks echo in interactive bash (history expansion).
  local base
  base="$(openssl rand -base64 18 | tr -d '/+=' | head -c 14)"
  printf '%s' "${base}Aa1#"
}

idp_user_name_from_email() {
  local email="${1:?email}"
  printf '%s' "$email" | tr '[:upper:]' '[:lower:]'
}

idp_idcs() {
  oci --region "$IDP_REGION" identity-domains "$@"
}
