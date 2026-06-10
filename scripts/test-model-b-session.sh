#!/usr/bin/env bash
# test-model-b-session.sh — lightweight Model B session probe (no ORDS approval rows).
#
# Verifies supervisorApprovalRequired + pinAllowed on GET /api/cashier/session and
# POST /api/cashier/unlock → 403 when Model B is enabled.
#
# Usage:
#   # Ephemeral server (reads ORDS_BASE_URL from .env) — recommended:
#   RUN_EPHEMERAL=yes npm run test:model-b-session
#
#   # Against a server already running with CASHIER_SUPERVISOR_APPROVAL=true:
#   npm run dev:up   # with Model B env
#   npm run test:model-b-session
#
# For pending-cookie + approval poll E2E, use npm run test:cashier-approval-session / test:cashier-approval-poll.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/http-test-lib.sh
source "$SCRIPT_DIR/lib/http-test-lib.sh"

BODY=$(mktemp)

cleanup_model_b() {
  http_test_stop_ephemeral_server
  rm -f "$BODY"
}
trap cleanup_model_b EXIT

pass=0
fail=0

log_ok()   { echo "  OK   $*"; pass=$((pass + 1)); }
log_fail() { echo "  FAIL $*"; fail=$((fail + 1)); }

HTTP_CODE=""
curl_req() {
  local method="$1"
  shift
  HTTP_CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X "$method" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    "$@" 2>/dev/null || echo "000")
}

if [[ "${RUN_EPHEMERAL:-}" == "yes" && -z "${BASE_URL:-}" ]]; then
  http_test_start_ephemeral_server true || exit 1
  BASE_URL="$EPHEMERAL_BASE_URL"
else
  BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
fi
BASE_URL="${BASE_URL%/}"

CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"

echo "== Model B session tests =="
echo "   BASE_URL=$BASE_URL"
echo ""

if ! http_test_wait_for_server "$BASE_URL"; then
  echo ""
  echo "  No server at $BASE_URL."
  echo "  Ephemeral (recommended):  RUN_EPHEMERAL=yes npm run test:model-b-session"
  echo "  Or start dev server with CASHIER_SUPERVISOR_APPROVAL=true"
  exit 1
fi

curl_req GET "$BASE_URL/api/cashier/session"
[[ "$HTTP_CODE" == "200" ]] || { echo "Server not reachable (HTTP $HTTP_CODE)"; exit 1; }

python3 -c "
import json, sys
d = json.load(open('$BODY'))
if not d.get('supervisorApprovalRequired'):
    print('supervisorApprovalRequired is false')
    sys.exit(1)
if d.get('pinAllowed'):
    print('pinAllowed should be false under Model B')
    sys.exit(2)
if d.get('ok'):
    print('expected unauthenticated session (ok=false)')
    sys.exit(3)
" && log_ok "session: supervisorApprovalRequired=true, pinAllowed=false" \
  || log_fail "session flags wrong for Model B (is CASHIER_SUPERVISOR_APPROVAL=true on the server?)"

curl_req POST "$BASE_URL/api/cashier/unlock" -d "{\"pin\":\"$CASHIER_PIN\"}"
[[ "$HTTP_CODE" == "403" ]] && log_ok "PIN unlock blocked → 403" || log_fail "PIN unlock → $HTTP_CODE (want 403)"

curl_req GET "$BASE_URL/api/cashier/approval/status"
case "$HTTP_CODE" in
  401) log_ok "GET /api/cashier/approval/status (no pending) → 401" ;;
  *)   log_fail "GET /api/cashier/approval/status → $HTTP_CODE (want 401)" ;;
esac

echo ""
echo "== done (model-b): $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
