#!/usr/bin/env bash
# test-cashier-approval-poll.sh — poll until approved issues cashier_session (step 5 E2E)
#
# Usage (server must be running with supervisor approval enabled):
#   CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true \
#     ./scripts/test-cashier-approval-poll.sh

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

ADMIN_PIN="$(read_env_var ADMIN_PIN "")"
CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"
[[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$CASHIER_PIN"

ORDS_BASE_URL="${ORDS_BASE_URL:-$(read_env_var ORDS_BASE_URL "")}"
if [[ -z "$ORDS_BASE_URL" ]] && [[ -d "$PROJECT_ROOT/terraform" ]]; then
  ORDS_BASE_URL="$(cd "$PROJECT_ROOT/terraform" && terraform output -raw ords_base_url 2>/dev/null || true)"
fi
export ORDS_BASE_URL

BODY=$(mktemp)
PENDING_JAR=$(mktemp)
ADMIN_JAR=$(mktemp)
CASHIER_JAR=$(mktemp)
trap 'rm -f "$BODY" "$PENDING_JAR" "$ADMIN_JAR" "$CASHIER_JAR"' EXIT

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

echo "== Cashier approval poll E2E =="
echo "   BASE_URL=$BASE_URL"
echo ""

TOKEN="$(node "$SCRIPT_DIR/create-test-pending-approval.js")"
[[ -n "$TOKEN" ]] || { echo "FAIL create pending"; exit 1; }
log_ok "pending token (${TOKEN:0:8}…)"

curl_req GET -b "cashier_pending=$TOKEN" -c "$PENDING_JAR" "$BASE_URL/api/cashier/approval/status"
python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('status')=='pending' else 1)" \
  && log_ok "poll before approve → pending" \
  || log_fail "poll before approve → $(cat "$BODY")"

curl_req GET -b "cashier_pending=$TOKEN" "$BASE_URL/api/cart"
[[ "$HTTP_CODE" == "401" ]] && log_ok "cart before approve → 401" || log_fail "cart before approve → $HTTP_CODE"

curl_req POST "$BASE_URL/api/admin/login" -c "$ADMIN_JAR" -d "{\"pin\":\"$ADMIN_PIN\"}"
[[ "$HTTP_CODE" == "200" ]] || { log_fail "admin login → $HTTP_CODE"; exit 1; }

curl_req POST -b "$ADMIN_JAR" "$BASE_URL/api/admin/login-approvals/${TOKEN}/approve" -d '{}'
[[ "$HTTP_CODE" == "200" ]] && log_ok "supervisor approve → 200" || log_fail "supervisor approve → $HTTP_CODE"

curl_req GET -b "cashier_pending=$TOKEN" -c "$CASHIER_JAR" "$BASE_URL/api/cashier/approval/status"
python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('status')=='approved' and d.get('ok') else 1)" \
  && log_ok "poll after approve → approved" \
  || log_fail "poll after approve → $(cat "$BODY")"

curl_req GET -b "$CASHIER_JAR" "$BASE_URL/api/cart"
[[ "$HTTP_CODE" != "401" ]] && log_ok "cart after approve → $HTTP_CODE (session cookie set)" || log_fail "cart after approve still 401"

curl_req POST -b "$CASHIER_JAR" "$BASE_URL/api/cashier/approval/cancel"
[[ "$HTTP_CODE" == "200" ]] && log_ok "cancel with active session → 200" || log_fail "cancel with session → $HTTP_CODE"

TOKEN2="$(node "$SCRIPT_DIR/create-test-pending-approval.js")"
curl_req GET -b "cashier_pending=$TOKEN2" "$BASE_URL/api/cashier/approval/status"
[[ "$HTTP_CODE" == "200" ]] && log_ok "poll pending token2 → 200" || log_fail "poll token2 → $HTTP_CODE"

curl_req POST -b "cashier_pending=$TOKEN2" -c "$PENDING_JAR" "$BASE_URL/api/cashier/approval/cancel"
python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('status')=='cancelled' else 1)" \
  && log_ok "cancel pending → cancelled" \
  || log_fail "cancel → $(cat "$BODY")"

curl_req GET -b "cashier_pending=$TOKEN2" "$BASE_URL/api/cashier/approval/status"
python3 -c "import json,sys; d=json.load(open('$BODY')); sys.exit(0 if d.get('status')=='cancelled' and not d.get('ok',True) else 1)" \
  && log_ok "poll after cancel → cancelled" \
  || log_fail "poll after cancel → $(cat "$BODY")"

curl_req GET "$BASE_URL/api/cashier/approval/status"
[[ "$HTTP_CODE" == "401" ]] && log_ok "poll without cookie → 401" || log_fail "poll anon → $HTTP_CODE"

echo ""
echo "== done: $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
