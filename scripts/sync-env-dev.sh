#!/usr/bin/env bash
# Update .env.dev ORDS_BASE_URL from dev Terraform state.
#
#   ./scripts/sync-env-dev.sh
#   ./scripts/sync-env-dev.sh --dry

set -euo pipefail

export CLOUD_STORE_ENV=dev
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env.dev}"

# shellcheck source=oci/lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"

DRY=0
[[ "${1:-}" == "--dry" || "${1:-}" == "-n" ]] && DRY=1

command -v terraform >/dev/null || { echo "error: terraform not found" >&2; exit 1; }

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$PROJECT_ROOT/.env.example" ]]; then
    cp "$PROJECT_ROOT/.env.example" "$ENV_FILE"
    echo "Created $ENV_FILE from .env.example"
  else
    echo "error: $ENV_FILE not found" >&2
    exit 1
  fi
fi

NEW_URL="$(cloud_store_tf_output ords_base_url || true)"
[[ -z "$NEW_URL" ]] && { echo "error: dev ords_base_url empty — run deploy-dev.sh first" >&2; exit 1; }

CURRENT_URL="$(grep -E '^ORDS_BASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"

echo "Environment: dev"
echo "Current .env.dev:  ${CURRENT_URL:-(not set)}"
echo "Terraform output:  $NEW_URL"

if [[ "$CURRENT_URL" == "$NEW_URL" ]]; then
  echo "Already in sync."
  exit 0
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "Dry run — would set ORDS_BASE_URL=$NEW_URL"
  exit 0
fi

cp "$ENV_FILE" "${ENV_FILE}.bak"
if grep -qE '^ORDS_BASE_URL=' "$ENV_FILE"; then
  sed -i '' "s|^ORDS_BASE_URL=.*|ORDS_BASE_URL=${NEW_URL}|" "$ENV_FILE"
else
  printf '\nORDS_BASE_URL=%s\n' "$NEW_URL" >> "$ENV_FILE"
fi

echo "Updated $ENV_FILE (backup: ${ENV_FILE}.bak)"
grep -E '^ORDS_BASE_URL=' "$ENV_FILE"
