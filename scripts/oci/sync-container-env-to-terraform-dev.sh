#!/usr/bin/env bash
export CLOUD_STORE_ENV=dev
export ENV_FILE="${ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.env.dev}"
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-container-env-to-terraform.sh"
