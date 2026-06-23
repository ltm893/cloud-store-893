#!/usr/bin/env bash
# Bootstrap a new dev OCI Identity Domain (External Active User) for Cloud Store.
#
# Creates cloud-store-app-N (auto-increment), one dev user (ltm893@icloud.com default),
# groups, cloud-store-pos + cloud-store-admin OIDC apps, redirect URIs, and writes .env.dev.
#
# Usage:
#   ./scripts/oci/idp/bootstrap-dev.sh
#   ./scripts/oci/idp/bootstrap-dev.sh --apply     # also sync env + terraform apply dev container
#   ./scripts/oci/idp/bootstrap-dev.sh --resume    # continue on latest cloud-store-app-N
#   ./scripts/oci/idp/bootstrap-dev.sh --dry-run   # print next domain name only
#
# Prerequisites:
#   oci CLI, jq, dev stack deployed (terraform.dev.tfstate + compartment_ocid)
#   terraform/terraform.dev.tfvars configured
#
# After bootstrap, sign in at https://dev.oci.cloudstore893.com/oauth/login
# Password is generated and printed once (not stored in repo).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=lib/idp-env.sh
source "$SCRIPT_DIR/lib/idp-env.sh"
# shellcheck source=lib/idp-domain.sh
source "$SCRIPT_DIR/lib/idp-domain.sh"
# shellcheck source=lib/idp-groups-user.sh
source "$SCRIPT_DIR/lib/idp-groups-user.sh"
# shellcheck source=lib/idp-apps.sh
source "$SCRIPT_DIR/lib/idp-apps.sh"
# shellcheck source=lib/idp-write-env.sh
source "$SCRIPT_DIR/lib/idp-write-env.sh"

DRY_RUN=0
DO_APPLY=0
RESUME=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --apply) DO_APPLY=1 ;;
    --resume) RESUME=1 ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

idp_env_init "$PROJECT_ROOT"
idp_require_tools

if [[ "$RESUME" == "1" ]]; then
  NEXT_NAME="$(idp_latest_domain_name "$IDP_DOMAIN_PREFIX" "$IDP_COMPARTMENT_OCID")"
  [[ -n "$NEXT_NAME" ]] || {
    echo "error: --resume: no existing ${IDP_DOMAIN_PREFIX}N domain found" >&2
    exit 1
  }
  echo "Resuming domain: $NEXT_NAME"
else
  NEXT_NAME="$(idp_next_domain_name "$IDP_DOMAIN_PREFIX" "$IDP_COMPARTMENT_OCID")"
  LATEST_NAME="$(idp_latest_domain_name "$IDP_DOMAIN_PREFIX" "$IDP_COMPARTMENT_OCID")"
  echo "Next domain name: $NEXT_NAME"
  if [[ -n "$LATEST_NAME" && "$LATEST_NAME" != "$NEXT_NAME" ]]; then
    echo "hint: $LATEST_NAME exists — run with --resume to finish bootstrap on it" >&2
  fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
  exit 0
fi

IDP_BOOTSTRAP_PASSWORD="$(idp_generate_password)"

export APP_PUBLIC_HOST="${CLOUD_STORE_PUBLIC_HOSTNAME:-dev.oci.cloudstore893.com}"
export APP_PUBLIC_SCHEME="https"
export APP_PUBLIC_PORT=""

idp_create_domain "$NEXT_NAME"
idp_bootstrap_groups_and_user "$IDP_BOOTSTRAP_PASSWORD"
idp_bootstrap_apps
idp_grant_groups_to_apps

echo "==> OAuth redirect URIs"
if idp_redirect_uris_match_expected "$IDP_POS_APP_NAME" "pos" \
  && idp_redirect_uris_match_expected "$IDP_ADMIN_APP_NAME" "admin"; then
  echo "    Already configured on both apps (skip)"
else
  export IDP_DOMAIN_ENDPOINT
  export OCI_REGION="${IDP_REGION}"
  "$IDP_SCRIPTS_DIR/idp-update-redirect-uris-dev.sh"
fi

idp_write_state_json "$IDP_BOOTSTRAP_PASSWORD"
idp_write_env_files

set +H 2>/dev/null || true

echo ""
echo "================================================================"
echo "  Dev IdP bootstrap complete — SAVE THIS PASSWORD NOW"
echo "================================================================"
printf '  Domain:     %s\n' "$IDP_DOMAIN_NAME"
printf '  Endpoint:   %s\n' "$IDP_DOMAIN_ENDPOINT"
printf '  Issuer:     %s\n' "$IDP_ISSUER"
printf '  User:       %s (login userName: %s)\n' "$IDP_USER_EMAIL" "${IDP_USER_NAME:-$IDP_USER_EMAIL}"
printf '  Password:   %s\n' "$IDP_BOOTSTRAP_PASSWORD"
echo "================================================================"
echo ""
echo "Manual step (if groups claim missing): OCI Console → Domain →"
echo "  Settings / Token issuance → ensure 'groups' is in the ID token."
echo ""

if [[ "$DO_APPLY" == "1" ]]; then
  echo "==> Syncing container env and applying dev container..."
  "$IDP_SCRIPTS_DIR/sync-container-env-to-terraform-dev.sh"
  "$IDP_SCRIPTS_DIR/terraform-apply-container-dev.sh" --yes
  echo "==> Verify:"
  echo "  APP=\$(CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh)"
  echo "  curl -s \"\$APP/api/cashier/session\""
fi

echo "Next: ./scripts/oci/idp/bootstrap-dev.sh --apply   # if you skipped --apply"
echo "Test: https://dev.oci.cloudstore893.com/oauth/login"
