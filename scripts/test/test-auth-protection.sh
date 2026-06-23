#!/usr/bin/env bash
# test-auth-protection.sh — verify cashier and admin routes enforce sessions.
#
# Usage (server must be running):
#   ./scripts/test-auth-protection.sh
#   BASE_URL=http://127.0.0.1:3000 ./scripts/test-auth-protection.sh
#   BASE_URL=$(cd terraform && terraform output -raw app_url) ./scripts/test-auth-protection.sh
#
# PINs: CASHIER_PIN / ADMIN_PIN env, or read from repo .env.
# Does not mutate cart/checkout (read-only + auth checks only).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/http-test-lib.sh
source "$SCRIPT_DIR/../lib/http-test-lib.sh"

BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
BASE_URL="${BASE_URL%/}"

CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"
ADMIN_PIN="$(read_env_var ADMIN_PIN "")"
[[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$CASHIER_PIN"

CASHIER_JAR=$(mktemp)
ADMIN_JAR=$(mktemp)
BODY=$(mktemp)
trap 'rm -f "$CASHIER_JAR" "$ADMIN_JAR" "$BODY"' EXIT

pass=0
fail=0
skip=0

log_ok()   { echo "  OK   $*"; pass=$((pass + 1)); }
log_fail() { echo "  FAIL $*"; fail=$((fail + 1)); }
log_skip() { echo "  SKIP $*"; skip=$((skip + 1)); }

HTTP_CODE=""
curl_req() {
  local method="$1"
  shift
  HTTP_CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X "$method" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    "$@")
}

# expect_anon METHOD PATH [extra curl args] — must be 401 without session
expect_protected_anon() {
  local method="$1" path="$2"
  shift 2
  curl_req "$method" "$BASE_URL$path" "$@"
  if [[ "$HTTP_CODE" == "401" ]]; then
    log_ok "anon $method $path → 401"
  else
    log_fail "anon $method $path → want 401, got $HTTP_CODE"
    sed 's/^/         /' "$BODY" | head -3
  fi
}

# expect_auth METHOD PATH cookie_jar [extra curl args] — must not be 401 with session
expect_allowed_authed() {
  local method="$1" path="$2" jar="$3"
  shift 3
  curl_req "$method" -b "$jar" -c "$jar" "$BASE_URL$path" "$@"
  if [[ "$HTTP_CODE" != "401" ]]; then
    log_ok "authed $method $path → $HTTP_CODE (not 401)"
  else
    log_fail "authed $method $path → still 401 with session cookie"
    sed 's/^/         /' "$BODY" | head -3
  fi
}

# Public routes — must not return 401 (default expect HTTP 200).
expect_public_anon() {
  local method="$1" path="$2" want="${3:-200}"
  shift 2
  curl_req "$method" "$BASE_URL$path" "$@"
  if [[ "$HTTP_CODE" == "$want" ]]; then
    log_ok "public $method $path → $HTTP_CODE"
  else
    log_fail "public $method $path → want $want, got $HTTP_CODE"
    sed 's/^/         /' "$BODY" | head -3
  fi
}

echo "== Auth protection tests =="
echo "   BASE_URL=$BASE_URL"
echo ""

# ── Server up? ──────────────────────────────────────────────────────────────
curl_req GET "$BASE_URL/api/cashier/session"
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "  Server not reachable at $BASE_URL (GET /api/cashier/session → $HTTP_CODE)"
  echo "  Start with: npm run dev:up"
  exit 1
fi
http_test_probe_cashier_session "$BASE_URL" "$BODY" || true

echo "-- Cashier: public without session --"
expect_public_anon GET /api/products
expect_public_anon GET /api/cashier/session
curl_req GET "$BASE_URL/api/cashier/approval/status"
case "$HTTP_CODE" in
  401) log_ok "GET /api/cashier/approval/status (no pending) → 401" ;;
  404) log_ok "GET /api/cashier/approval/status → 404 (Model B disabled)" ;;
  *)   log_fail "GET /api/cashier/approval/status → $HTTP_CODE" ;;
esac
curl_req POST "$BASE_URL/api/cashier/logout"
[[ "$HTTP_CODE" == "200" ]] && log_ok "public POST /api/cashier/logout → 200" || log_fail "public POST /api/cashier/logout → $HTTP_CODE"

curl_req POST "$BASE_URL/api/cashier/unlock" -d '{"pin":"0000"}'
if [[ "${SESSION_SUPERVISOR_REQUIRED:-false}" == "true" ]]; then
  [[ "$HTTP_CODE" == "403" ]] && log_ok "POST /api/cashier/unlock bad PIN → 403 (Model B)" \
    || log_fail "POST /api/cashier/unlock bad PIN → $HTTP_CODE (want 403 under Model B)"
else
  [[ "$HTTP_CODE" == "401" ]] && log_ok "POST /api/cashier/unlock bad PIN → 401" \
    || log_fail "POST /api/cashier/unlock bad PIN → $HTTP_CODE"
fi

echo ""
echo "-- Cashier: protected without session (expect 401) --"
POS_PROTECTED=(
  "GET|/api/customers"
  "GET|/api/cart"
  "GET|/api/sales/recent"
  "POST|/api/cart|{\"productId\":1}"
  "POST|/api/cart/barcode|{\"barcode\":\"x\"}"
  "POST|/api/cart/replace|{\"items\":[]}"
  "POST|/api/checkout|{\"paymentMethod\":\"cash\"}"
  "DELETE|/api/cart/1"
)
for entry in "${POS_PROTECTED[@]}"; do
  IFS='|' read -r method path payload <<< "$entry"
  if [[ -n "${payload:-}" ]]; then
    expect_protected_anon "$method" "$path" -d "$payload"
  else
    expect_protected_anon "$method" "$path"
  fi
done

echo ""
echo "-- Cashier: unlock and re-test --"
CASHIER_UNLOCKED=0
if [[ "${SESSION_OK:-false}" == "true" ]]; then
  log_skip "PIN unlock (existing cashier session)"
  CASHIER_UNLOCKED=1
elif [[ "${SESSION_SUPERVISOR_REQUIRED:-false}" == "true" ]]; then
  log_skip "PIN unlock + authed POS routes (Model B — use Oracle sign-in or ephemeral server with approval off)"
else
  curl_req POST "$BASE_URL/api/cashier/unlock" -c "$CASHIER_JAR" -d "{\"pin\":\"$CASHIER_PIN\"}"
  if [[ "$HTTP_CODE" != "200" ]]; then
    log_fail "POST /api/cashier/unlock (valid PIN) → $HTTP_CODE — check CASHIER_PIN"
    echo ""
    echo "== done (auth): $pass passed, $fail failed, $skip skipped =="
    exit 1
  fi
  log_ok "POST /api/cashier/unlock (valid PIN) → 200"
  CASHIER_UNLOCKED=1
fi

if [[ "$CASHIER_UNLOCKED" == "1" ]]; then
  for entry in "${POS_PROTECTED[@]}"; do
    IFS='|' read -r method path payload <<< "$entry"
    if [[ -n "${payload:-}" ]]; then
      expect_allowed_authed "$method" "$path" "$CASHIER_JAR" -d "$payload"
    else
      expect_allowed_authed "$method" "$path" "$CASHIER_JAR"
    fi
  done
fi

echo ""
echo "-- Cashier cookie must not grant admin API --"
expect_protected_anon GET /api/admin/meta -b "$CASHIER_JAR"

echo ""
echo "-- Admin: public without session --"
expect_public_anon GET /api/admin/session
curl_req POST "$BASE_URL/api/admin/logout"
[[ "$HTTP_CODE" == "200" ]] && log_ok "public POST /api/admin/logout (no-op) → 200" || log_fail "public POST /api/admin/logout → $HTTP_CODE"
curl_req POST "$BASE_URL/api/admin/login" -d '{"pin":"0000"}'
[[ "$HTTP_CODE" == "401" ]] && log_ok "POST /api/admin/login bad PIN → 401" || log_fail "POST /api/admin/login bad PIN → $HTTP_CODE"

echo ""
echo "-- Admin: protected without session (expect 401) --"
ADMIN_PROTECTED=(
  "GET|/api/admin/meta"
  "GET|/api/admin/products"
  "GET|/api/admin/customers"
  "GET|/api/admin/cart_items"
  "GET|/api/admin/sales"
  "GET|/api/admin/sale_items"
  "GET|/api/admin/cart_view"
  "GET|/api/admin/products/1"
  "POST|/api/admin/products|{\"name\":\"x\",\"price\":1}"
  "PUT|/api/admin/products/1|{\"name\":\"x\"}"
  "DELETE|/api/admin/products/999999999"
)
for entry in "${ADMIN_PROTECTED[@]}"; do
  IFS='|' read -r method path payload <<< "$entry"
  if [[ -n "${payload:-}" ]]; then
    expect_protected_anon "$method" "$path" -d "$payload"
  else
    expect_protected_anon "$method" "$path"
  fi
done

echo ""
echo "-- Admin UI pages (no API cookie) --"
HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/admin/login.html")
[[ "$HTTP_CODE" == "200" ]] && log_ok "GET /admin/login.html → 200" || log_fail "GET /admin/login.html → $HTTP_CODE"

REDIR=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/admin/")
if [[ "$REDIR" == "302" || "$REDIR" == "301" ]]; then
  log_ok "GET /admin/ without session → redirect ($REDIR)"
else
  log_fail "GET /admin/ without session → want 302, got $REDIR"
fi

echo ""
echo "-- Admin: unlock and re-test --"
curl_req POST "$BASE_URL/api/admin/login" -c "$ADMIN_JAR" -d "{\"pin\":\"$ADMIN_PIN\"}"
if [[ "$HTTP_CODE" != "200" ]]; then
  log_fail "POST /api/admin/login (valid PIN) → $HTTP_CODE — check ADMIN_PIN"
  echo ""
  echo "== done (auth): $pass passed, $fail failed, $skip skipped =="
  exit 1
fi
log_ok "POST /api/admin/login (valid PIN) → 200"

for entry in "${ADMIN_PROTECTED[@]}"; do
  IFS='|' read -r method path payload <<< "$entry"
  if [[ -n "${payload:-}" ]]; then
    expect_allowed_authed "$method" "$path" "$ADMIN_JAR" -d "$payload"
  else
    expect_allowed_authed "$method" "$path" "$ADMIN_JAR"
  fi
done
curl_req POST -b "$ADMIN_JAR" -c "$ADMIN_JAR" "$BASE_URL/api/admin/logout"
[[ "$HTTP_CODE" == "200" ]] && log_ok "authed POST /api/admin/logout → 200" || log_fail "authed POST /api/admin/logout → $HTTP_CODE"

echo ""
echo "-- Admin cookie must not grant POS cart without cashier session --"
expect_protected_anon GET /api/cart -b "$ADMIN_JAR"

echo ""
echo "-- Optional IdP routes (when configured) --"
for path in /oauth/login /oauth/admin/login; do
  curl_req GET "$BASE_URL$path"
  case "$HTTP_CODE" in
    302) log_ok "GET $path → 302 (IdP enabled)" ;;
    404) log_skip "GET $path → 404 (IdP not configured)" ;;
    500) log_fail "GET $path → 500 (IdP misconfigured?)" ;;
    *)   log_skip "GET $path → $HTTP_CODE" ;;
  esac
done

echo ""
echo "== done (auth): $pass passed, $fail failed, $skip skipped =="
[[ "$fail" -eq 0 ]]
