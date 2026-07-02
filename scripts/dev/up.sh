#!/bin/zsh
# dev-up.sh — Start the local dev stack for cloud-store-893.
#
# Does NOT touch Docker, Terraform, or the cloud Container Instance.
# Just verifies ADB/ORDS is reachable, prints the tablet URL,
# and runs `node --watch server.js`.
#
#   ./scripts/dev/up.sh
#
# Flags:
#   --no-probe   Skip the ORDS health check (start the server even if cloud is down)
#   --no-watch   Use `node server.js` instead of `node --watch server.js`

set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="${0:a:h}"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
TF_DIR="${PROJECT_ROOT}/terraform"

PROBE=1
WATCH=1
for arg in "$@"; do
  case "$arg" in
    --no-probe) PROBE=0 ;;
    --no-watch) WATCH=0 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }
divider() { echo "\n${BLUE}────────────────────────────────────────${NC}\n" }

# ── Read ORDS_BASE_URL from .env ──────────────────────────────────────────────
[[ -f "${PROJECT_ROOT}/.env" ]] || error ".env not found at ${PROJECT_ROOT}/.env"
ORDS_BASE_URL=$(grep -E '^ORDS_BASE_URL=' "${PROJECT_ROOT}/.env" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
[[ -z "$ORDS_BASE_URL" ]] && error "ORDS_BASE_URL missing in .env"

divider
info "Cloud-store-893 local dev"
info "  Project root: ${PROJECT_ROOT}"
info "  ORDS URL:     ${ORDS_BASE_URL}"

# ── Drift check — does .env match what terraform last applied? ────────────────
if [[ -d "${TF_DIR}" ]] && command -v terraform &>/dev/null; then
  TF_ORDS=$(cd "${TF_DIR}" && terraform output -raw ords_base_url 2>/dev/null || true)
  if [[ -n "$TF_ORDS" && "$TF_ORDS" != "$ORDS_BASE_URL" ]]; then
    warn "ORDS_BASE_URL drift between .env and terraform output:"
    warn "  .env:       $ORDS_BASE_URL"
    warn "  terraform:  $TF_ORDS"
    warn "Update .env if the cloud was redeployed."
  fi
fi

# ── ORDS health probe ─────────────────────────────────────────────────────────
# /metadata-catalog/ is a built-in ORDS endpoint — 200 only when the schema
# is ORDS-enabled. Distinguishes "ADB stopped" (no response) from
# "ADB up but ORDS not configured" (404) from "all good" (200).
if [[ "$PROBE" = "1" ]]; then
  info "Probing ${ORDS_BASE_URL}/metadata-catalog/ ..."
  HTTP_CODE=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" "${ORDS_BASE_URL}/metadata-catalog/" || echo "000")
  case "$HTTP_CODE" in
    200)
      success "ORDS is healthy (schema enabled)."
      ;;
    404)
      warn "ORDS reachable but schema NOT enabled (HTTP 404)."
      warn "Fix: paste the ORDS-only PL/SQL block (or scripts/db/seed.sql) into Database Actions → SQL."
      warn "Server will start, but /api/* endpoints will return 500 until this is fixed."
      ;;
    000|"")
      warn "ORDS unreachable (no response). The ADB is likely STOPPED."
      warn "Fix: OCI Console → Autonomous Database → cloudstore893 → Start, then retry."
      warn "Server will start, but /api/* endpoints will fail until ADB is back."
      ;;
    *)
      warn "ORDS returned unexpected HTTP $HTTP_CODE — investigate before relying on /api/*."
      ;;
  esac
else
  warn "Skipping ORDS probe (--no-probe)"
fi

# ── Print LAN URL for the Android tablet ──────────────────────────────────────
if command -v ipconfig &>/dev/null; then
  LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
  PORT_VAL="${PORT:-3000}"
  if [[ -n "$LAN_IP" ]]; then
    info "Tablet should target: http://${LAN_IP}:${PORT_VAL}/"
    warn "Oracle IdP must allow redirect http://${LAN_IP}:${PORT_VAL}/oauth/callback"
    warn "  Run: ./scripts/dev/update-idp-redirects.sh (once per LAN IP change)"
  else
    warn "Could not detect LAN IP — verify Wi-Fi is on if you intend to use the tablet."
  fi
fi

# ── Start the local Node server ───────────────────────────────────────────────
divider
info "Web POS: use one host for the whole session (e.g. http://127.0.0.1:${PORT_VAL:-3000}/)"
info "  localhost and 127.0.0.1 do not share cookies."
info "  Cashier PIN: CASHIER_PIN in .env (not ADMIN_PIN). Sessions persist across node --watch restarts."

cd "${PROJECT_ROOT}"
export DEV_PERSIST_AUTH_SESSIONS=true
if [[ "$WATCH" = "1" ]]; then
  info "Starting: node --watch server.js"
  exec node --watch server.js
else
  info "Starting: node server.js"
  exec node server.js
fi
