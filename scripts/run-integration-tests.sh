#!/usr/bin/env bash
# run-integration-tests.sh — start a test server and run HTTP smoke tests.
#
# Requires: live ORDS (ORDS_BASE_URL in .env or env), curl, python3, node.
#
# Usage:
#   ./scripts/run-integration-tests.sh
#   RUN_DESTRUCTIVE=yes ./scripts/run-integration-tests.sh   # include cart/checkout
#   BASE_URL=http://127.0.0.1:3000 ./scripts/run-integration-tests.sh  # use existing server
#
# Overrides for the ephemeral server (when BASE_URL is not preset):
#   CASHIER_SUPERVISOR_APPROVAL=false  — PIN unlock works in auth tests
#   BUILD_ID=integration-test

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

ORDS_BASE_URL="$(read_env_var ORDS_BASE_URL "")"
CASHIER_PIN="$(read_env_var CASHIER_PIN 8930)"
ADMIN_PIN="$(read_env_var ADMIN_PIN "")"
[[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$CASHIER_PIN"

USE_EXISTING_SERVER=0
if [[ -n "${BASE_URL:-}" ]]; then
  USE_EXISTING_SERVER=1
  BASE_URL="${BASE_URL%/}"
else
  if [[ -z "$ORDS_BASE_URL" ]]; then
    echo "ORDS_BASE_URL is not set (.env or env). Integration tests need live ORDS."
    exit 1
  fi
  TEST_PORT="${TEST_PORT:-0}"
  if [[ "$TEST_PORT" == "0" ]]; then
    TEST_PORT=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
  fi
  BASE_URL="http://127.0.0.1:${TEST_PORT}"
fi

SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_server() {
  local i
  for i in $(seq 1 40); do
    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/api/cashier/session" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "Server did not become ready at $BASE_URL"
  return 1
}

if [[ "$USE_EXISTING_SERVER" == "0" ]]; then
  echo "== Starting integration test server on $BASE_URL =="
  echo "   ORDS_BASE_URL=$ORDS_BASE_URL"
  (
    cd "$PROJECT_ROOT"
    export PORT="$TEST_PORT"
    export ORDS_BASE_URL
    export BUILD_ID="${BUILD_ID:-integration-test}"
    export BUILD_LABEL="${BUILD_LABEL:-integration test}"
    export CASHIER_SUPERVISOR_APPROVAL="${CASHIER_SUPERVISOR_APPROVAL:-false}"
    export CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR="${CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR:-false}"
    export IDP_ALLOW_PIN="${IDP_ALLOW_PIN:-true}"
    export DEV_PERSIST_AUTH_SESSIONS=false
    exec node server.js
  ) &
  SERVER_PID=$!
  wait_for_server
fi

export BASE_URL
export CASHIER_PIN
export ADMIN_PIN

API_FLAGS=(SKIP_DESTRUCTIVE=yes)
if [[ "${RUN_DESTRUCTIVE:-}" == "yes" ]]; then
  API_FLAGS=(SKIP_CONFIRM=yes)
fi

echo ""
echo "== Integration: auth protection =="
AUTH_START=$SECONDS
set +e
./scripts/test-auth-protection.sh
AUTH_EXIT=$?
set -e
AUTH_SEC=$((SECONDS - AUTH_START))
echo "== timing (auth): $AUTH_SEC =="

echo ""
echo "== Integration: API smoke (destructive=${RUN_DESTRUCTIVE:-no}) =="
API_START=$SECONDS
set +e
env "${API_FLAGS[@]}" ./scripts/test-api-curl.sh
API_EXIT=$?
set -e
API_SEC=$((SECONDS - API_START))
echo "== timing (api): $API_SEC =="

echo ""
echo "== Integration: inventory API (destructive=${RUN_DESTRUCTIVE:-no}) =="
INV_FLAGS=(SKIP_DESTRUCTIVE=yes)
if [[ "${RUN_DESTRUCTIVE:-}" == "yes" ]]; then
  INV_FLAGS=(SKIP_CONFIRM=yes)
fi
INV_START=$SECONDS
set +e
env "${INV_FLAGS[@]}" ./scripts/test-inventory-api.sh
INV_EXIT=$?
set -e
INV_SEC=$((SECONDS - INV_START))
echo "== timing (inventory): $INV_SEC =="

echo ""
if [[ "$AUTH_EXIT" -eq 0 && "$API_EXIT" -eq 0 && "$INV_EXIT" -eq 0 ]]; then
  echo "== Integration tests passed (${AUTH_SEC}s auth, ${API_SEC}s api, ${INV_SEC}s inventory) =="
  exit 0
fi
echo "== Integration tests failed (auth exit=$AUTH_EXIT, api exit=$API_EXIT, inventory exit=$INV_EXIT) =="
exit 1
