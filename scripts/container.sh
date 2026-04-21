#!/bin/zsh

# cloud-store-893 Container Instance Manager
# Usage: ./scripts/container.sh [start|stop|status]

# Check OCI CLI is available
if ! command -v oci &> /dev/null; then
  echo "❌ OCI CLI not found. Install with: brew install oci-cli"
  exit 1
fi

# ── Resolve Container Instance OCID ─────────────────────────────────────────
# Use env var if already set, otherwise look it up from OCI
if [[ -z "$CLOUD_STORE_OCID" ]]; then
  echo "🔍 CLOUD_STORE_OCID not set — looking up container instance from OCI..."

  # Get compartment OCID for cloud-store-893
  COMPARTMENT_OCID=$(oci iam compartment list \
    --all \
    --query "data[?name=='cloud-store-893'].id | [0]" \
    --raw-output 2>/dev/null)

  if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
    echo "❌ Could not find compartment 'cloud-store-893' in OCI."
    echo "   Check your OCI CLI config: oci iam compartment list"
    exit 1
  fi

  # Get the container instance OCID by name
  CLOUD_STORE_OCID=$(oci container-instances container-instance list \
    --compartment-id "$COMPARTMENT_OCID" \
    --query "data.items[?\"display-name\"=='container-instance-cloud-store-893'].id | [0]" \
    --raw-output 2>/dev/null)

  if [[ -z "$CLOUD_STORE_OCID" || "$CLOUD_STORE_OCID" == "null" ]]; then
    echo "❌ Could not find container instance 'container-instance-cloud-store-893'."
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
    echo "🚀 Starting cloud-store-893 container instance..."
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
    echo "🛑 Stopping cloud-store-893 container instance..."
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
    echo "📦 cloud-store-893: $STATUS"
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
