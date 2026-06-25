# http-test-lib.sh — shared curl helpers for integration test scripts.
# Source from scripts/test/*.sh: source "$SCRIPT_DIR/../lib/http-test-lib.sh"

http_test_project_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$lib_dir/../.." && pwd
}

# Wait until GET /api/cashier/session returns 200.
http_test_wait_for_server() {
  local base_url="$1" i code
  base_url="${base_url%/}"
  for i in $(seq 1 40); do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/api/cashier/session" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "Server did not become ready at $base_url"
  return 1
}

# Start node server.js on a free port. Sets EPHEMERAL_SERVER_PID and EPHEMERAL_BASE_URL.
# Arg 1: CASHIER_SUPERVISOR_APPROVAL value (true/false, default false).
http_test_start_ephemeral_server() {
  local supervisor_approval="${1:-false}"
  local ords port root
  ords="$(read_env_var ORDS_BASE_URL "")"
  if [[ -z "$ords" ]]; then
    echo "ORDS_BASE_URL is not set (.env or environment). Required for RUN_EPHEMERAL=yes."
    return 1
  fi
  root="$(http_test_project_root)"
  port="${TEST_PORT:-0}"
  if [[ "$port" == "0" ]]; then
    port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
  fi
  EPHEMERAL_BASE_URL="http://127.0.0.1:${port}"
  echo "== Starting ephemeral test server on $EPHEMERAL_BASE_URL =="
  echo "   ORDS_BASE_URL=$ords"
  echo "   CASHIER_SUPERVISOR_APPROVAL=$supervisor_approval"
  (
    cd "$root"
    export PORT="$port"
    export ORDS_BASE_URL="$ords"
    export BUILD_ID="${BUILD_ID:-integration-test}"
    export BUILD_LABEL="${BUILD_LABEL:-integration test}"
    export CASHIER_SUPERVISOR_APPROVAL="$supervisor_approval"
    export CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR="${CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR:-false}"
    export IDP_ALLOW_PIN="${IDP_ALLOW_PIN:-true}"
    export DEV_PERSIST_AUTH_SESSIONS=false
    exec node server.js
  ) &
  EPHEMERAL_SERVER_PID=$!
  http_test_wait_for_server "$EPHEMERAL_BASE_URL"
}

http_test_stop_ephemeral_server() {
  if [[ -n "${EPHEMERAL_SERVER_PID:-}" ]] && kill -0 "$EPHEMERAL_SERVER_PID" 2>/dev/null; then
    kill "$EPHEMERAL_SERVER_PID" 2>/dev/null || true
    wait "$EPHEMERAL_SERVER_PID" 2>/dev/null || true
  fi
  EPHEMERAL_SERVER_PID=""
}

# read_env_var KEY [default]
read_env_var() {
  local key="$1" default="${2:-}"
  local root
  root="$(http_test_project_root)"
  if [[ -n "${!key:-}" ]]; then
    printf '%s' "${!key}"
    return
  fi
  if [[ -f "$root/.env" ]]; then
    local line
    line=$(grep -E "^${key}=" "$root/.env" 2>/dev/null | head -1 || true)
    if [[ -n "$line" ]]; then
      printf '%s' "${line#*=}" | tr -d '"' | tr -d "'"
      return
    fi
  fi
  printf '%s' "$default"
}

# Probe GET /api/cashier/session into $body_file.
# Sets: SESSION_SUPERVISOR_REQUIRED (true/false), SESSION_PIN_ALLOWED, SESSION_OK (true/false)
http_test_probe_cashier_session() {
  local base_url="$1" body_file="$2"
  local code
  code=$(curl -sS -o "$body_file" -w '%{http_code}' \
    -H 'Accept: application/json' \
    "$base_url/api/cashier/session" 2>/dev/null || echo "000")
  if [[ "$code" != "200" ]]; then
    SESSION_SUPERVISOR_REQUIRED=false
    SESSION_PIN_ALLOWED=true
    SESSION_OK=false
    return 1
  fi
  read -r SESSION_SUPERVISOR_REQUIRED SESSION_PIN_ALLOWED SESSION_OK <<< "$(python3 -c "
import json, sys
try:
    d = json.load(open('$body_file'))
except Exception:
    print('false true false')
    sys.exit(0)
sup = 'true' if d.get('supervisorApprovalRequired') else 'false'
pin = 'true' if d.get('pinAllowed') else 'false'
ok = 'true' if d.get('ok') else 'false'
print(sup, pin, ok)
" 2>/dev/null || echo "false true false")"
  return 0
}

# POST /api/cashier/unlock when PIN is allowed. Uses cookie jar at $jar_file.
# Returns 0 when a session cookie was established, 1 when unlock was skipped.
http_test_unlock_cashier() {
  local base_url="$1" jar_file="$2" body_file="$3" pin="$4"
  if ! http_test_probe_cashier_session "$base_url" "$body_file"; then
    echo "  WARN server unreachable for session probe"
    return 1
  fi
  if [[ "$SESSION_OK" == "true" ]]; then
    return 0
  fi
  if [[ "$SESSION_SUPERVISOR_REQUIRED" == "true" || "$SESSION_PIN_ALLOWED" != "true" ]]; then
    return 1
  fi
  local code
  code=$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
    -b "$jar_file" -c "$jar_file" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "{\"pin\":\"$pin\"}" \
    "$base_url/api/cashier/unlock" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    SESSION_OK=true
    return 0
  fi
  return 1
}

# POST /api/admin/login. Returns 0 on success.
http_test_admin_login() {
  local base_url="$1" jar_file="$2" body_file="$3" pin="$4"
  local code
  code=$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
    -b "$jar_file" -c "$jar_file" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "{\"pin\":\"$pin\"}" \
    "$base_url/api/admin/login" 2>/dev/null || echo "000")
  [[ "$code" == "200" ]]
}
