#!/usr/bin/env bash
# scripts/test-api-curl.sh — curl smoke tests for every /api route in server.js
#
# Usage:
#   npm run dev:up   # or: node server.js   (server must be running)
#   ./scripts/test-api-curl.sh
#   BASE_URL=http://192.168.1.50:3000 ./scripts/test-api-curl.sh
#
# Requires: curl, python3 (for JSON parsing). Optional: VERBOSE=1
#
# The script has a DESTRUCTIVE phase (clears the shared cart + completes checkout).
# You must type "yes" to continue, unless SKIP_CONFIRM=yes (for CI / automation).

set -u

BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
BASE_URL="${BASE_URL%/}"
CASHIER_PIN="${CASHIER_PIN:-8930}"

BODY=$(mktemp)
COOKIE=$(mktemp)
trap 'rm -f "$BODY" "$COOKIE"' EXIT

pass=0
fail=0

log_ok()  { echo "  OK   $*"; pass=$((pass + 1)); }
log_bad() { echo "  FAIL $*"; fail=$((fail + 1)); }

# curl_json METHOD URL [curl-args...]  -> sets HTTP_CODE, writes body to $BODY
curl_json() {
  local method="$1"
  shift
  HTTP_CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X "$method" \
    -b "$COOKIE" -c "$COOKIE" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    "$@")
}

expect_code() {
  local want="$1" label="$2"
  if [[ "$HTTP_CODE" == "$want" ]]; then
    log_ok "$label (HTTP $HTTP_CODE)"
    [[ "${VERBOSE:-0}" == "1" ]] && head -c 400 "$BODY" | cat -v && echo
  else
    log_bad "$label (want HTTP $want, got $HTTP_CODE)"
    sed 's/^/         /' "$BODY" | head -20
  fi
}

py() { python3 "$@"; }

# Remove all cart lines (walk-in GET shape: { items: [...] }).
clear_cart() {
  local id
  while true; do
    curl_json GET "$BASE_URL/api/cart"
    [[ "$HTTP_CODE" != "200" ]] && break
    id=$(py -c "import json;d=open('$BODY').read();o=json.loads(d);its=o.get('items')or[];print(its[0]['id'] if its else '')" 2>/dev/null || true)
    [[ -z "${id:-}" ]] && break
    curl_json DELETE "$BASE_URL/api/cart/$id"
    [[ "$HTTP_CODE" != "200" ]] && break
  done
}

# Bash 3.2–safe lowercase (no ${var,,}).
confirm_destructive_phase() {
  if [[ "${SKIP_CONFIRM:-}" == "yes" ]]; then
    echo "  (SKIP_CONFIRM=yes — continuing without prompt)"
    echo ""
    return 0
  fi
  echo ""
  echo "  ******************************************************************"
  echo "  * DESTRUCTIVE PHASE — read before continuing                     *"
  echo "  *                                                                *"
  echo "  * The shared cart is GLOBAL: this script will DELETE every      *"
  echo "  * cart line, then POST /api/checkout (creates a real sale +      *"
  echo "  * sale_items in Autonomous DB).                                *"
  echo "  *                                                                *"
  echo "  * Do not run if you care about the current cart contents or      *"
  echo "  * against production.                                            *"
  echo "  ******************************************************************"
  echo ""
  printf "  Type the word yes to continue (anything else aborts): "
  IFS= read -r reply || reply=""
  reply_lc=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
  if [[ "$reply_lc" != "yes" ]]; then
    echo ""
    echo "  Aborted — destructive phase skipped (no cart clears / no checkout)."
    exit 1
  fi
  echo ""
}

echo "== cloud-store-893 API curl tests =="
echo "   BASE_URL=$BASE_URL"
echo ""

# ── GET /api/products ─────────────────────────────────────────────────────
curl_json GET "$BASE_URL/api/products"
expect_code 200 "GET /api/products"
PRODUCT_ID=$(py -c "import json;d=open('$BODY').read();a=json.loads(d) if d.strip() else [];print(a[0]['id'] if isinstance(a,list)and a else '')" 2>/dev/null || true)

# ── POST /api/cashier/unlock (session cookie for protected APIs) ─────────
curl_json POST "$BASE_URL/api/cashier/unlock" -d "{\"pin\":\"$CASHIER_PIN\"}"
expect_code 200 "POST /api/cashier/unlock"

# ── GET /api/customers ────────────────────────────────────────────────────
curl_json GET "$BASE_URL/api/customers"
expect_code 200 "GET /api/customers"
CUSTOMER_893_ID=$(py -c "
import json
try:
    d=json.load(open('$BODY'))
except Exception:
    d=None
a=d if isinstance(d,list) else []
x=next((c for c in a if c.get('is893')),None)
print(x['id'] if x else '')
" 2>/dev/null || true)
CUSTOMER_ANY_ID=$(py -c "
import json
try:
    d=json.load(open('$BODY'))
except Exception:
    d=None
a=d if isinstance(d,list) else []
print(a[0]['id'] if a else '')
" 2>/dev/null || true)

# ── GET /api/cart (walk-in) ───────────────────────────────────────────────
curl_json GET "$BASE_URL/api/cart"
expect_code 200 "GET /api/cart"

# ── GET /api/cart?customerId= (893 preview if customer exists) ─────────────
if [[ -n "${CUSTOMER_893_ID:-}" ]]; then
  curl_json GET "$BASE_URL/api/cart?customerId=$CUSTOMER_893_ID"
  expect_code 200 "GET /api/cart?customerId=$CUSTOMER_893_ID (893)"
else
  echo "  SKIP GET /api/cart?customerId=… (no is893 customer in DB)"
fi

# ── GET /api/cart?customerId= invalid ─────────────────────────────────────
curl_json GET "$BASE_URL/api/cart?customerId=999999999"
expect_code 400 "GET /api/cart?customerId=999999999 (invalid)"

# ── POST /api/cart/barcode validation ───────────────────────────────────────
curl_json POST "$BASE_URL/api/cart/barcode" -d '{}'
expect_code 400 "POST /api/cart/barcode {} (missing barcode)"

# ── POST /api/cart (add line for mutation tests) ────────────────────────────
if [[ -z "${PRODUCT_ID:-}" ]]; then
  echo "  SKIP cart mutation / checkout (no products from GET /api/products)"
else
  confirm_destructive_phase

  echo "  -- clear cart, then mutation / checkout flow --"
  clear_cart

  curl_json POST "$BASE_URL/api/checkout" -d '{"paymentMethod":"card"}'
  expect_code 400 "POST /api/checkout (empty cart)"

  curl_json POST "$BASE_URL/api/cart" -d "{\"productId\":$PRODUCT_ID}"
  expect_code 200 "POST /api/cart {productId}"

  if [[ -n "${CUSTOMER_893_ID:-}" ]]; then
    curl_json POST "$BASE_URL/api/cart" -d "{\"productId\":$PRODUCT_ID,\"customerId\":$CUSTOMER_893_ID}"
    expect_code 200 "POST /api/cart {productId,customerId} (893)"
  fi

  curl_json POST "$BASE_URL/api/cart/barcode" -d '{"barcode":"100000000001"}'
  if [[ "$HTTP_CODE" == "200" ]]; then
    log_ok "POST /api/cart/barcode {barcode: OCI book} (HTTP 200)"
  else
    log_bad "POST /api/cart/barcode (want 200, got $HTTP_CODE)"
    sed 's/^/         /' "$BODY" | head -10
  fi

  curl_json POST "$BASE_URL/api/cart/barcode" -d '{"barcode":"does-not-exist-xyz"}'
  expect_code 404 "POST /api/cart/barcode (unknown barcode)"

  curl_json GET "$BASE_URL/api/cart"
  expect_code 200 "GET /api/cart (after adds)"
  CART_LINE_ID=$(py -c "import json;d=open('$BODY').read();o=json.loads(d);print(o['items'][0]['id'] if o.get('items') else '')" 2>/dev/null || true)

  if [[ -n "${CART_LINE_ID:-}" ]]; then
    curl_json DELETE "$BASE_URL/api/cart/$CART_LINE_ID"
    expect_code 200 "DELETE /api/cart/:id"
  else
    echo "  SKIP DELETE /api/cart/:id (no cart line id)"
  fi

  curl_json POST "$BASE_URL/api/cart" -d "{\"productId\":$PRODUCT_ID}"
  expect_code 200 "POST /api/cart (line for checkout)"

  CHECKOUT_BODY='{"paymentMethod":"cash"}'
  if [[ -n "${CUSTOMER_893_ID:-}" ]]; then
    CHECKOUT_BODY="{\"paymentMethod\":\"cash\",\"customerId\":$CUSTOMER_893_ID}"
  elif [[ -n "${CUSTOMER_ANY_ID:-}" ]]; then
    CHECKOUT_BODY="{\"paymentMethod\":\"cash\",\"customerId\":$CUSTOMER_ANY_ID}"
  fi
  curl_json POST "$BASE_URL/api/checkout" -d "$CHECKOUT_BODY"
  expect_code 200 "POST /api/checkout"

  curl_json POST "$BASE_URL/api/checkout" -d '{"paymentMethod":"card"}'
  expect_code 400 "POST /api/checkout (empty cart after sale)"
fi

# ── GET /api/sales/recent ───────────────────────────────────────────────────
curl_json GET "$BASE_URL/api/sales/recent"
expect_code 200 "GET /api/sales/recent"

echo ""
echo "== done: $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
