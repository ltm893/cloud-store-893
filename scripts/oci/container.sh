#!/bin/zsh

# Container Instance manager for the Terraform project compartment.
# Default compartment: cloud-store (matches terraform/variables.tf project_name).
# Overrides: CLOUD_STORE_PROJECT_NAME=my-name ./scripts/oci/container.sh status
#
# Usage: ./scripts/oci/container.sh [start|stop|status]

PROJECT_NAME="${CLOUD_STORE_PROJECT_NAME:-cloud-store}"
CONTAINER_DISPLAY_NAME="container-instance-${PROJECT_NAME}"

# Check OCI CLI is available
if ! command -v oci &> /dev/null; then
  echo "❌ OCI CLI not found. Install with: brew install oci-cli"
  exit 1
fi

# ── Resolve Container Instance OCID ─────────────────────────────────────────
# Use env var if already set, otherwise look it up from OCI
if [[ -z "$CLOUD_STORE_OCID" ]]; then
  echo "🔍 CLOUD_STORE_OCID not set — looking up container instance from OCI..."

  # Get compartment OCID (name = project_name / PROJECT_NAME)
  COMPARTMENT_OCID=$(oci iam compartment list \
    --all \
    --query "data[?name=='${PROJECT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null)

  if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
    echo "❌ Could not find compartment '${PROJECT_NAME}' in OCI."
    echo "   Check your OCI CLI config: oci iam compartment list"
    exit 1
  fi

  # Get the container instance OCID by name
  CLOUD_STORE_OCID=$(oci container-instances container-instance list \
    --compartment-id "$COMPARTMENT_OCID" \
    --query "data.items[?\"display-name\"=='${CONTAINER_DISPLAY_NAME}'].id | [0]" \
    --raw-output 2>/dev/null)

  if [[ -z "$CLOUD_STORE_OCID" || "$CLOUD_STORE_OCID" == "null" ]]; then
    echo "❌ Could not find container instance '${CONTAINER_DISPLAY_NAME}'."
    echo "   Verify it exists in OCI Console → Developer Services → Container Instances"
    echo "   Or set it manually in ~/.zshrc:"
    echo "   export CLOUD_STORE_OCID=\"<your-container-instance-ocid>\""
    exit 1
  fi

  echo "✅ Found container instance: $CLOUD_STORE_OCID"
  echo "   💡 To skip this lookup, add to ~/.zshrc:"
  echo "      export CLOUD_STORE_OCID=\"$CLOUD_STORE_OCID\""
  echo ""
fi

# ── Commands ─────────────────────────────────────────────────────────────────
case "$1" in
  start)
    echo "🚀 Starting container instance (${PROJECT_NAME})..."
    oci container-instances container-instance start \
      --container-instance-id "$CLOUD_STORE_OCID"
    echo "⏳ Waiting for Active state..."
    sleep 5
    STATUS=$(oci container-instances container-instance get \
      --container-instance-id "$CLOUD_STORE_OCID" \
      --query "data.\"lifecycle-state\"" \
      --raw-output)
    echo "✅ Status: $STATUS"
    ;;

  stop)
    echo "🛑 Stopping container instance (${PROJECT_NAME})..."
    oci container-instances container-instance stop \
      --container-instance-id "$CLOUD_STORE_OCID"
    echo "⏳ Waiting for Inactive state..."
    sleep 5
    STATUS=$(oci container-instances container-instance get \
      --container-instance-id "$CLOUD_STORE_OCID" \
      --query "data.\"lifecycle-state\"" \
      --raw-output)
    echo "✅ Status: $STATUS"
    ;;

  status)
    echo "🔍 Checking container instance status..."
    STATUS=$(oci container-instances container-instance get \
      --container-instance-id "$CLOUD_STORE_OCID" \
      --query "data.\"lifecycle-state\"" \
      --raw-output)
    echo "📦 ${PROJECT_NAME}: $STATUS"
    ;;

  *)
    echo "Usage: $0 [start|stop|status]"
    echo ""
    echo "  start   — Start the OCI container instance"
    echo "  stop    — Stop the OCI container instance"
    echo "  status  — Check current lifecycle state"
    echo ""
    echo "The script will auto-discover your container instance OCID from OCI."
    echo "To skip the lookup, set CLOUD_STORE_OCID in ~/.zshrc."
    exit 1
    ;;
esac
