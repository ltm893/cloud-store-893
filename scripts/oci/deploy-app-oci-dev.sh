#!/usr/bin/env bash
export CLOUD_STORE_ENV=dev
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-app-oci.sh" "$@"
