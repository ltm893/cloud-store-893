#!/bin/zsh
# sync-env.sh — Update .env's ORDS_BASE_URL from `terraform output`.
#
# Run after any `terraform apply` that may have changed the ADB hostname.
#
#   ./scripts/sync-env.sh        # update .env in place
#   ./scripts/sync-env.sh --dry  # show what would change, don't write

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="${0:a:h}"
PROJECT_ROOT="${SCRIPT_DIR}/.."
TF_DIR="${PROJECT_ROOT}/terraform"
ENV_FILE="${PROJECT_ROOT}/.env"

DRY=0
[[ "$1" == "--dry" || "$1" == "-n" ]] && DRY=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }

command -v terraform >/dev/null || error "terraform not found on PATH."
[[ -d "$TF_DIR" ]] || error "Terraform dir not found: $TF_DIR"
[[ -f "$ENV_FILE" ]] || error ".env not found: $ENV_FILE  (copy from .env.example first)"

NEW_URL=$(cd "$TF_DIR" && terraform output -raw ords_base_url 2>/dev/null || true)
[[ -z "$NEW_URL" ]] && error "terraform output -raw ords_base_url returned empty. Has the cloud been deployed?"

CURRENT_URL=$(grep -E '^ORDS_BASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")

info "Current .env:        ${CURRENT_URL:-(not set)}"
info "Terraform output:    ${NEW_URL}"

if [[ "$CURRENT_URL" == "$NEW_URL" ]]; then
  success ".env is already in sync — nothing to do."
  exit 0
fi

if [[ $DRY -eq 1 ]]; then
  warn "Dry run — would update .env to: ORDS_BASE_URL=${NEW_URL}"
  exit 0
fi

cp "$ENV_FILE" "${ENV_FILE}.bak"
if grep -qE '^ORDS_BASE_URL=' "$ENV_FILE"; then
  sed -i '' "s|^ORDS_BASE_URL=.*|ORDS_BASE_URL=${NEW_URL}|" "$ENV_FILE"
else
  printf '\nORDS_BASE_URL=%s\n' "$NEW_URL" >> "$ENV_FILE"
fi

success "Updated $ENV_FILE (backup at ${ENV_FILE}.bak)"
grep -E '^ORDS_BASE_URL=' "$ENV_FILE"
