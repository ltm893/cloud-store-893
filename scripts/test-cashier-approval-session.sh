#!/usr/bin/env bash
# test-cashier-approval-session.sh — step 4/5 session + pending cookie checks
#
# Usage (server must be running):
#   CASHIER_SUPERVISOR_APPROVAL=true ./scripts/test-cashier-approval-session.sh
#
# With supervisor approval OFF on the server, also verifies PIN unlock still works.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
BASE_URL="${BASE_URL%/}"

read_env_var() {
  local key="$1" default="${2:-}"
  if [[ -n "${!key:-}" ]]; then
    printf '%s' "${!key}"
    return
  fi
  if [[ -f "$PROJECT_ROOT/.env" ]]; then
    local line
    line=$(grep -E "^${key}=" "$PROJECT_ROOT/.env" 2>/dev/null | head -1 || true)
    if [[ -n "$line" ]]; then
      printf '%s' "${line#*=}" | tr -d '"' | tr -d "'"
      return
    fi
  fi
  printf '%s' "$default"
}

CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"
SUPERVISOR_APPROVAL="${CASHIER_SUPERVISOR_APPROVAL:-false}"
ORDS_BASE_URL="${ORDS_BASE_URL:-$(read_env_var ORDS_BASE_URL "")}"
if [[ -z "$ORDS_BASE_URL" ]] && [[ -d "$PROJECT_ROOT/terraform" ]]; then
  ORDS_BASE_URL="$(cd "$PROJECT_ROOT/terraform" && terraform output -raw ords_base_url 2>/dev/null || true)"
fi
export ORDS_BASE_URL

BODY=$(mktemp)
JAR=$(mktemp)
trap 'rm -f "$BODY" "$JAR"' EXIT

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
    "$@")
}

echo "== Cashier approval session tests =="
echo "   BASE_URL=$BASE_URL"
echo "   CASHIER_SUPERVISOR_APPROVAL (client expectation)=$SUPERVISOR_APPROVAL"
echo ""

curl_req GET "$BASE_URL/api/cashier/session"
[[ "$HTTP_CODE" == "200" ]] || { echo "Server not reachable"; exit 1; }

if [[ "$SUPERVISOR_APPROVAL" == "true" || "$SUPERVISOR_APPROVAL" == "1" ]]; then
  python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('supervisorApprovalRequired') else 1)" \
    && log_ok "session reports supervisorApprovalRequired" \
    || log_fail "session missing supervisorApprovalRequired (is it set on the server process?)"

  curl_req POST "$BASE_URL/api/cashier/unlock" -d "{\"pin\":\"$CASHIER_PIN\"}"
  [[ "$HTTP_CODE" == "403" ]] && log_ok "PIN unlock blocked → 403" || log_fail "PIN unlock → $HTTP_CODE (want 403)"

  [[ -n "$ORDS_BASE_URL" ]] || { log_fail "ORDS_BASE_URL not set"; exit 1; }
  TOKEN="$(node "$SCRIPT_DIR/create-test-pending-approval.js")"
  [[ -n "$TOKEN" ]] && log_ok "created pending token (${TOKEN:0:8}…)" || { log_fail "create pending"; exit 1; }

  curl_req GET "$BASE_URL/api/cashier/session"
  python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if not d.get('pending') else 1)" \
    && log_ok "session without pending cookie → not pending" \
    || log_fail "unexpected pending without cookie"

  curl_req GET -b "cashier_pending=$TOKEN" "$BASE_URL/api/cashier/session"
  python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('pending') and d.get('approval',{}).get('requestToken')=='$TOKEN' else 1)" \
    && log_ok "session with pending cookie → pending + token" \
    || log_fail "pending session payload wrong"
else
  curl_req POST "$BASE_URL/api/cashier/unlock" -c "$JAR" -d "{\"pin\":\"$CASHIER_PIN\"}"
  [[ "$HTTP_CODE" == "200" ]] && log_ok "PIN unlock → 200 (approval off)" || log_fail "PIN unlock → $HTTP_CODE"
  curl_req GET -b "$JAR" "$BASE_URL/api/cashier/session"
  python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('ok') else 1)" \
    && log_ok "session after PIN → ok" \
    || log_fail "session after PIN not ok"
fi

echo ""
echo "== done: $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
