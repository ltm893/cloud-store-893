#!/usr/bin/env bash
# test-inventory-api.sh — HTTP smoke tests for inventory fields, stock 409s, checkout depletion.
#
# Usage (needs ORDS with inventory schema):
#   npm run dev:up && npm run test:inventory
#   RUN_EPHEMERAL=yes npm run test:inventory   # starts its own server (reads ORDS from .env)
#   BASE_URL=http://127.0.0.1:3000 ./scripts/test-inventory-api.sh
#   SKIP_DESTRUCTIVE=yes ./scripts/test-inventory-api.sh   # skip checkout + movement checks
#
# Requires: curl, python3. Uses CASHIER_PIN / ADMIN_PIN from env or .env.
# Skips cart tests when Model B is on and no cashier session exists.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/http-test-lib.sh
source "$SCRIPT_DIR/../lib/http-test-lib.sh"

BODY=$(mktemp)
CASHIER_JAR=$(mktemp)
ADMIN_JAR=$(mktemp)

cleanup_inventory_tests() {
  http_test_stop_ephemeral_server
  rm -f "$BODY" "$CASHIER_JAR" "$ADMIN_JAR"
}
trap cleanup_inventory_tests EXIT

if [[ "${RUN_EPHEMERAL:-}" == "yes" && -z "${BASE_URL:-}" ]]; then
  http_test_start_ephemeral_server false || exit 1
  BASE_URL="$EPHEMERAL_BASE_URL"
else
  BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
fi
BASE_URL="${BASE_URL%/}"

CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"
ADMIN_PIN="$(read_env_var ADMIN_PIN "")"
[[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$CASHIER_PIN"

pass=0
fail=0
skip=0

log_ok()   { echo "  OK   $*"; pass=$((pass + 1)); }
log_fail() { echo "  FAIL $*"; fail=$((fail + 1)); }
log_skip() { echo "  SKIP $*"; skip=$((skip + 1)); }

HTTP_CODE=""
curl_json() {
  local method="$1" jar="$2"
  shift 2
  local -a curl_args
  curl_args=(-sS -o "$BODY" -w '%{http_code}' -X "$method"
    -H 'Accept: application/json'
    -H 'Content-Type: application/json')
  if [[ -n "$jar" ]]; then
    curl_args+=(-b "$jar" -c "$jar")
  fi
  HTTP_CODE=$(curl "${curl_args[@]}" "$@" 2>/dev/null || echo "000")
}

expect_code() {
  local want="$1" label="$2"
  if [[ "$HTTP_CODE" == "$want" ]]; then
    log_ok "$label (HTTP $HTTP_CODE)"
    [[ "${VERBOSE:-0}" == "1" ]] && head -c 400 "$BODY" | cat -v && echo
  else
    log_fail "$label (want HTTP $want, got $HTTP_CODE)"
    sed 's/^/         /' "$BODY" | head -20
  fi
}

clear_cart() {
  local id
  while true; do
    curl_json GET "$CASHIER_JAR" "$BASE_URL/api/cart"
    [[ "$HTTP_CODE" != "200" ]] && break
    id=$(python3 -c "import json;d=open('$BODY').read();o=json.loads(d);its=o.get('items')or[];print(its[0]['id'] if its else '')" 2>/dev/null || true)
    [[ -z "${id:-}" ]] && break
    curl_json DELETE "$CASHIER_JAR" "$BASE_URL/api/cart/$id"
    [[ "$HTTP_CODE" != "200" ]] && break
  done
}

confirm_destructive_phase() {
  if [[ "${SKIP_DESTRUCTIVE:-}" == "yes" ]]; then
    echo "  (SKIP_DESTRUCTIVE=yes — skipping inventory checkout verification)"
    echo ""
    return 1
  fi
  if [[ "${SKIP_CONFIRM:-}" == "yes" ]]; then
    echo "  (SKIP_CONFIRM=yes — continuing without prompt)"
    echo ""
    return 0
  fi
  echo ""
  echo "  ******************************************************************"
  echo "  * DESTRUCTIVE — mixed cart checkout + inventory movement checks   *"
  echo "  ******************************************************************"
  echo ""
  printf "  Type the word yes to continue (anything else aborts): "
  IFS= read -r reply || reply=""
  reply_lc=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
  if [[ "$reply_lc" != "yes" ]]; then
    echo ""
    echo "  Aborted — destructive inventory phase skipped."
    return 1
  fi
  echo ""
  return 0
}

echo "== Inventory API tests =="
echo "   BASE_URL=$BASE_URL"
echo ""

if ! http_test_wait_for_server "$BASE_URL"; then
  echo ""
  echo "  No server at $BASE_URL."
  echo "  Start one:  npm run dev:up"
  echo "  Or ephemeral:  RUN_EPHEMERAL=yes npm run test:inventory"
  exit 1
fi

# ── Product JSON shape (public) ─────────────────────────────────────────────
curl_json GET "" "$BASE_URL/api/products"
expect_code 200 "GET /api/products"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo ""
  echo "== done (inventory): $pass passed, $fail failed, $skip skipped =="
  exit 1
fi

python3 -c "
import json, sys
products = json.load(open('$BODY'))
if not isinstance(products, list) or not products:
    print('no products')
    sys.exit(1)
missing = [p for p in products if 'inStock' not in p]
if missing:
    print('missing inStock')
    sys.exit(2)
drinks = [p for p in products if p.get('quantityOnHand') is None]
tracked = [p for p in products if p.get('quantityOnHand') is not None]
if not drinks:
    print('no untracked drink SKU')
    sys.exit(3)
if not tracked:
    print('no tracked retail SKU')
    sys.exit(4)
for p in drinks:
    if p.get('inStock') is not True:
        print('drink should always be inStock')
        sys.exit(5)
for p in tracked:
    if not isinstance(p.get('quantityOnHand'), (int, float)):
        print('tracked SKU needs numeric quantityOnHand')
        sys.exit(6)
print('shape ok')
" && log_ok "products expose inStock + quantityOnHand (drinks null, retail numeric)" \
  || log_fail "product inventory field shape"

read -r DRINK_ID RETAIL_ID OOS_ID <<< "$(python3 -c "
import json
products = json.load(open('$BODY'))
drink = next((p for p in products if p.get('quantityOnHand') is None), {})
retail = next((p for p in products if p.get('quantityOnHand') is not None and p.get('inStock')), {})
oos = next((p for p in products if p.get('quantityOnHand') is not None and not p.get('inStock')), {})
print(drink.get('id', ''), retail.get('id', ''), oos.get('id', ''))
")"

# ── Cashier session for cart routes ─────────────────────────────────────────
if http_test_unlock_cashier "$BASE_URL" "$CASHIER_JAR" "$BODY" "$CASHIER_PIN"; then
  log_ok "cashier session ready (PIN unlock or existing session)"
else
  if [[ "${SESSION_SUPERVISOR_REQUIRED:-false}" == "true" ]]; then
    log_skip "cart inventory tests (Model B — PIN unlock blocked; start server with CASHIER_SUPERVISOR_APPROVAL=false or sign in)"
  else
    log_fail "cashier unlock failed — cannot run cart inventory tests"
  fi
  echo ""
  echo "== done (inventory): $pass passed, $fail failed, $skip skipped =="
  [[ "$fail" -eq 0 ]]
  exit $?
fi

# ── Retail OOS → 409 ────────────────────────────────────────────────────────
RESTORE_PRODUCT_ID=""
RESTORE_QTY=""

if [[ -n "${OOS_ID:-}" ]]; then
  TEST_OOS_ID="$OOS_ID"
else
  if [[ -n "${RETAIL_ID:-}" ]] && http_test_admin_login "$BASE_URL" "$ADMIN_JAR" "$BODY" "$ADMIN_PIN"; then
    curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/product_inventory/$RETAIL_ID"
    RESTORE_QTY=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)
    if [[ -n "${RESTORE_QTY:-}" ]]; then
      RESTORE_PRODUCT_ID="$RETAIL_ID"
      curl_json POST "$ADMIN_JAR" "$BASE_URL/api/admin/inventory/set-count" \
        -d "{\"productId\":$RETAIL_ID,\"quantity\":0,\"note\":\"integration-test-oos\"}"
      if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
        TEST_OOS_ID="$RETAIL_ID"
        log_ok "admin set-count → 0 for OOS cart test (product $RETAIL_ID)"
      else
        log_fail "admin set-count for OOS test (HTTP $HTTP_CODE)"
        TEST_OOS_ID=""
      fi
    fi
  else
    log_skip "retail OOS 409 (no OOS SKU and admin login failed)"
    TEST_OOS_ID=""
  fi
fi

if [[ -n "${TEST_OOS_ID:-}" ]]; then
  clear_cart
  curl_json POST "$CASHIER_JAR" "$BASE_URL/api/cart" -d "{\"productId\":$TEST_OOS_ID}"
  expect_code 409 "POST /api/cart out-of-stock retail → 409"
  if [[ -n "${RESTORE_PRODUCT_ID:-}" && -n "${RESTORE_QTY:-}" ]]; then
    curl_json POST "$ADMIN_JAR" "$BASE_URL/api/admin/inventory/set-count" \
      -d "{\"productId\":$RESTORE_PRODUCT_ID,\"quantity\":$RESTORE_QTY,\"note\":\"integration-test-restore\"}"
    [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]] \
      && log_ok "restored retail qty after OOS test" \
      || log_fail "restore retail qty (HTTP $HTTP_CODE)"
  fi
else
  log_skip "retail OOS 409 (no suitable product)"
fi

# ── Bulk beans insufficient → 409 ───────────────────────────────────────────
BULK_RESTORE_QTY=""
if [[ -n "${DRINK_ID:-}" ]] && http_test_admin_login "$BASE_URL" "$ADMIN_JAR" "$BODY" "$ADMIN_PIN"; then
  curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/bulk_inventory/kitchen_beans"
  if [[ "$HTTP_CODE" == "200" ]]; then
    BULK_RESTORE_QTY=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)
    curl_json POST "$ADMIN_JAR" "$BASE_URL/api/admin/inventory/bulk/set-count" \
      -d '{"skuKey":"kitchen_beans","quantity":0.5,"note":"integration-test-bulk-oos"}'
    if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
      clear_cart
      curl_json POST "$CASHIER_JAR" "$BASE_URL/api/cart" -d "{\"productId\":$DRINK_ID}"
      expect_code 409 "POST /api/cart insufficient kitchen beans → 409"
      if [[ -n "${BULK_RESTORE_QTY:-}" ]]; then
        curl_json POST "$ADMIN_JAR" "$BASE_URL/api/admin/inventory/bulk/set-count" \
          -d "{\"skuKey\":\"kitchen_beans\",\"quantity\":$BULK_RESTORE_QTY,\"note\":\"integration-test-restore\"}"
        [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]] \
          && log_ok "restored kitchen_beans qty after bulk 409 test" \
          || log_fail "restore kitchen_beans (HTTP $HTTP_CODE)"
      fi
    else
      log_fail "admin bulk set-count for 409 test (HTTP $HTTP_CODE)"
    fi
  else
    log_skip "bulk 409 (kitchen_beans not in DB — run seed-bulk-inventory-migrate.sql)"
  fi
else
  log_skip "bulk 409 (no drink SKU or admin login failed)"
fi

# ── Destructive: mixed checkout depletes retail + bulk ───────────────────────
if [[ -n "${DRINK_ID:-}" && -n "${RETAIL_ID:-}" ]] && confirm_destructive_phase; then
  if ! http_test_admin_login "$BASE_URL" "$ADMIN_JAR" "$BODY" "$ADMIN_PIN"; then
    log_fail "admin login for checkout inventory verification"
  else
    curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/bulk_inventory/kitchen_beans"
    BULK_BEFORE=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)
    curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/product_inventory/$RETAIL_ID"
    RETAIL_BEFORE=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)

    clear_cart
    curl_json POST "$CASHIER_JAR" "$BASE_URL/api/cart" -d "{\"productId\":$DRINK_ID}"
    expect_code 200 "POST /api/cart drink (destructive)"
    curl_json POST "$CASHIER_JAR" "$BASE_URL/api/cart" -d "{\"productId\":$RETAIL_ID}"
    expect_code 200 "POST /api/cart retail (destructive)"

    curl_json POST "$CASHIER_JAR" "$BASE_URL/api/checkout" -d '{"paymentMethod":"cash"}'
    if [[ "$HTTP_CODE" == "200" ]]; then
      log_ok "POST /api/checkout mixed cart (HTTP 200)"
      ORDER_NUMBER=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('orderNumber',''))" 2>/dev/null || true)

      curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/bulk_inventory/kitchen_beans"
      BULK_AFTER=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)
      curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/product_inventory/$RETAIL_ID"
      RETAIL_AFTER=$(python3 -c "import json; d=json.load(open('$BODY')); print(d.get('quantity_on_hand', ''))" 2>/dev/null || true)

      python3 -c "
import sys
b0, b1 = float('$BULK_BEFORE'), float('$BULK_AFTER')
r0, r1 = float('$RETAIL_BEFORE'), float('$RETAIL_AFTER')
if abs((b0 - b1) - 1.5) > 0.01:
    print(f'bulk delta {b0-b1}, want 1.5')
    sys.exit(1)
if abs((r0 - r1) - 1) > 0.01:
    print(f'retail delta {r0-r1}, want 1')
    sys.exit(1)
print('deltas ok')
" && log_ok "bulk −1.5 oz and retail −1 after mixed checkout" \
        || log_fail "inventory quantities did not decrease as expected"

      if [[ -n "${ORDER_NUMBER:-}" ]]; then
        curl_json GET "$ADMIN_JAR" "$BASE_URL/api/admin/inventory_movements"
        if [[ "$HTTP_CODE" == "200" ]]; then
          python3 -c "
import json, sys
order = '$ORDER_NUMBER'
rows = json.load(open('$BODY'))
if not isinstance(rows, list):
    sys.exit('movements not a list')
hits = [r for r in rows if r.get('order_number') == order]
sales = [r for r in hits if r.get('reason') == 'sale' and r.get('product_id')]
consumes = [r for r in hits if r.get('reason') == 'consume' and r.get('bulk_sku_key') == 'kitchen_beans']
if not sales:
    print('missing sale movement')
    sys.exit(1)
if not consumes:
    print('missing consume movement')
    sys.exit(1)
print('movements ok')
" && log_ok "inventory_movements has sale + consume for $ORDER_NUMBER" \
            || log_fail "inventory_movements missing sale/consume rows"
        else
          log_fail "GET /api/admin/inventory_movements (HTTP $HTTP_CODE)"
        fi
      else
        log_fail "checkout response missing orderNumber"
      fi
    else
      log_fail "POST /api/checkout mixed cart (want HTTP 200, got $HTTP_CODE)"
      sed 's/^/         /' "$BODY" | head -10
    fi
  fi
else
  if [[ -z "${DRINK_ID:-}" || -z "${RETAIL_ID:-}" ]]; then
    log_skip "destructive mixed checkout (need drink + retail product IDs)"
  fi
fi

echo ""
echo "== done (inventory): $pass passed, $fail failed, $skip skipped =="
[[ "$fail" -eq 0 ]]
