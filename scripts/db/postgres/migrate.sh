#!/usr/bin/env bash
# Run Postgres migrate against DATABASE_URL (local Compose or Aurora via URL).
# On Colima/macOS, host port publish may fail — falls back to docker network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

run_local() {
  if [[ -z "${DATABASE_URL:-}" ]]; then
    export DATABASE_URL="postgresql://cloudstore:cloudstore@127.0.0.1:5432/cloudstore"
  fi
  export DATABASE_SSL="${DATABASE_SSL:-false}"
  node "${SCRIPT_DIR}/migrate.js" 2>/dev/null
}

if run_local; then
  exit 0
fi

echo "Host DATABASE_URL unreachable — retrying via docker compose network…"
cd "$ROOT"
docker compose up -d postgres >/dev/null
docker run --rm \
  --network cloud-store-893_default \
  -v "${ROOT}:/app" \
  -w /app \
  -e DATABASE_URL=postgresql://cloudstore:cloudstore@postgres:5432/cloudstore \
  -e DATABASE_SSL=false \
  node:20-alpine \
  node scripts/db/postgres/migrate.js
