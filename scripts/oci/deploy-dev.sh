#!/usr/bin/env bash
# Greenfield deploy of the OCI **dev** stack (compartment cloud-store-dev).
#
#   cp terraform/terraform.dev.tfvars.example terraform/terraform.dev.tfvars
#   # fill tenancy creds + adb_admin_password
#   ./scripts/oci/deploy-dev.sh
#
# See docs/oci-dev-environment.md

set -euo pipefail

export CLOUD_STORE_ENV=dev
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" "$@"
