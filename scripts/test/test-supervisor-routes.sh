#!/usr/bin/env bash
# test-supervisor-routes.sh — HTTP smoke tests for /api/admin/login-approvals/*
#
# Usage (server must be running):
#   CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true ./scripts/test-supervisor-routes.sh
#   BASE_URL=http://127.0.0.1:3000 ./scripts/test-supervisor-routes.sh
#
# Creates a pending approval via ORDS, then exercises list/approve/deny routes.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

PIN_SUPERVISOR="${CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR:-false}"
BODY=$(mktemp)
ADMIN_JAR=$(mktemp)
trap 'rm -f "$BODY" "$ADMIN_JAR"' EXIT

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

echo "== Supervisor route tests =="
echo "   BASE_URL=$BASE_URL"
echo "   CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=$PIN_SUPERVISOR"
echo ""

curl_req GET "$BASE_URL/api/admin/session"
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "  Server not reachable at $BASE_URL (GET /api/admin/session → $HTTP_CODE)"
  exit 1
fi

echo "-- Without admin session (expect 401) --"
curl_req GET "$BASE_URL/api/admin/login-approvals"
[[ "$HTTP_CODE" == "401" ]] && log_ok "anon GET login-approvals → 401" || log_fail "anon GET login-approvals → $HTTP_CODE"

REQUEST_TOKEN=""
if [[ -z "${ORDS_BASE_URL:-}" ]]; then
  ORDS_BASE_URL="$(read_env_var ORDS_BASE_URL "")"
fi
if [[ -z "$ORDS_BASE_URL" ]] && [[ -d "$PROJECT_ROOT/terraform" ]]; then
  ORDS_BASE_URL="$(cd "$PROJECT_ROOT/terraform" && terraform output -raw ords_base_url 2>/dev/null || true)"
fi
export ORDS_BASE_URL
REQUEST_TOKEN="$(node "$SCRIPT_DIR/create-test-pending-approval.js" 2>/dev/null || true)"
if [[ -z "$REQUEST_TOKEN" ]]; then
  log_fail "could not create pending approval (set ORDS_BASE_URL)"
  echo ""
  echo "== done: $pass passed, $fail failed =="
  exit 1
fi
log_ok "created pending request token (${REQUEST_TOKEN:0:8}…)"

echo ""
echo "-- Admin login --"
curl_req POST "$BASE_URL/api/admin/login" -c "$ADMIN_JAR" -d "{\"pin\":\"$ADMIN_PIN\"}"
[[ "$HTTP_CODE" == "200" ]] && log_ok "POST /api/admin/login → 200" || log_fail "POST /api/admin/login → $HTTP_CODE"

curl_req GET -b "$ADMIN_JAR" "$BASE_URL/api/admin/session"
if [[ "$HTTP_CODE" == "200" ]]; then
  SERVER_SUPERVISOR=$(python3 -c "import json; print(json.load(open('$BODY')).get('isSupervisor', False))" 2>/dev/null || echo "False")
  if [[ "$PIN_SUPERVISOR" == "true" || "$PIN_SUPERVISOR" == "1" || "$PIN_SUPERVISOR" == "yes" ]]; then
    if [[ "$SERVER_SUPERVISOR" == "True" ]]; then
      log_ok "server reports isSupervisor (PIN fallback on server process)"
    else
      log_fail "server isSupervisor=false — restart dev:up with CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true on the Node process"
    fi
  fi
fi

echo ""
echo "-- Supervisor routes with admin session --"
curl_req GET -b "$ADMIN_JAR" -c "$ADMIN_JAR" "$BASE_URL/api/admin/login-approvals?status=pending"
case "$HTTP_CODE" in
  200)
    if [[ "$PIN_SUPERVISOR" == "true" || "$PIN_SUPERVISOR" == "1" || "$PIN_SUPERVISOR" == "yes" ]]; then
      log_ok "GET login-approvals → 200"
    else
      log_fail "GET login-approvals → 200 but PIN supervisor fallback is disabled (expected 403)"
    fi
    ;;
  403)
    if [[ "$PIN_SUPERVISOR" == "true" || "$PIN_SUPERVISOR" == "1" || "$PIN_SUPERVISOR" == "yes" ]]; then
      log_fail "GET login-approvals → 403 with PIN supervisor fallback enabled"
    else
      log_ok "GET login-approvals → 403 (admin PIN is not a supervisor)"
    fi
    ;;
  *)
    log_fail "GET login-approvals → $HTTP_CODE"
    ;;
esac

if [[ "$HTTP_CODE" == "403" ]]; then
  echo ""
  echo "  Tip: CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR must be set when starting the server, e.g."
  echo "    CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run dev:up"
  echo "  Or sign in via admin IdP with group store-supervisors."
  echo ""
  echo "== done: $pass passed, $fail failed =="
  [[ "$fail" -eq 0 ]]
  exit $?
fi

if ! grep -q "$REQUEST_TOKEN" "$BODY"; then
  log_fail "pending list missing created request token"
else
  log_ok "pending list includes created request"
fi

curl_req POST -b "$ADMIN_JAR" -c "$ADMIN_JAR" \
  "$BASE_URL/api/admin/login-approvals/${REQUEST_TOKEN}/approve" -d '{}'
[[ "$HTTP_CODE" == "200" ]] && log_ok "POST approve → 200" || log_fail "POST approve → $HTTP_CODE"

DENY_TOKEN="$(node "$SCRIPT_DIR/create-test-pending-approval.js" 2>/dev/null || true)"
if [[ -n "$DENY_TOKEN" ]]; then
  curl_req POST -b "$ADMIN_JAR" -c "$ADMIN_JAR" \
    "$BASE_URL/api/admin/login-approvals/${DENY_TOKEN}/deny" \
    -d '{"reason":"test deny"}'
  [[ "$HTTP_CODE" == "200" ]] && log_ok "POST deny → 200" || log_fail "POST deny → $HTTP_CODE"
else
  log_fail "could not create second pending request for deny test"
fi

echo ""
echo "== done: $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
