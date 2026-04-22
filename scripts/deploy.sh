#!/bin/zsh
# deploy.sh — Full Terraform + Docker deploy for cloud-store-893
#
# Run this from the project root:
#   chmod +x scripts/deploy.sh   (first time only)
#   ./scripts/deploy.sh

set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="${0:a:h}"
PROJECT_ROOT="${SCRIPT_DIR}/.."
TF_DIR="${PROJECT_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }
divider() { echo "\n${BLUE}────────────────────────────────────────${NC}\n" }

# ── Helper: read a value from terraform.tfvars ────────────────────────────────
tfvar() { grep "^${1}" "${TFVARS}" | sed 's/.*= *"//' | sed 's/".*//' | tr -d ' ' }

# ── Prereq checks ─────────────────────────────────────────────────────────────
divider
info "Checking prerequisites..."

command -v terraform &>/dev/null || error "terraform not found. Run: brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
command -v docker    &>/dev/null || error "docker not found."
command -v oci       &>/dev/null || error "OCI CLI not found. Run: brew install oci-cli"

docker info &>/dev/null || error "Docker daemon not running. Run: colima start"

[[ -f "${TFVARS}" ]] || error "terraform/terraform.tfvars not found.\nCopy terraform.tfvars.example → terraform.tfvars and fill in your values."

# ── Read image path components from tfvars ────────────────────────────────────
NAMESPACE=$(tfvar "object_storage_namespace")
REGION_KEY=$(tfvar "ocir_region_key")
PROJECT=$(tfvar "project_name" 2>/dev/null || echo "cloud-store-893")
IMAGE_TAG=$(tfvar "ocir_image_tag" 2>/dev/null || echo "latest")

# project_name has a default in variables.tf — fall back if not in tfvars
[[ -z "$PROJECT" ]] && PROJECT="cloud-store-893"
[[ -z "$IMAGE_TAG" ]] && IMAGE_TAG="latest"
[[ -z "$REGION_KEY" ]] && REGION_KEY="iad"

[[ -z "$NAMESPACE" || "$NAMESPACE" == "your_namespace_here" ]] && \
  error "object_storage_namespace not set in terraform.tfvars.\nFind it: OCI Console → Profile menu → Tenancy → Object Storage Namespace"

IMAGE_PATH="${REGION_KEY}.ocir.io/${NAMESPACE}/${PROJECT}:${IMAGE_TAG}"
REGISTRY="${REGION_KEY}.ocir.io"

success "All prerequisites met"
info "Image path: ${IMAGE_PATH}"

# ── Terraform init ─────────────────────────────────────────────────────────────
divider
info "Phase 0 — terraform init"
cd "${TF_DIR}"
terraform init -upgrade

# ── Phase 1: Create compartment + OCIR repo ────────────────────────────────────
divider
info "Phase 1 — Creating compartment and OCIR repo..."
terraform apply \
  -target=oci_identity_compartment.main \
  -target=oci_artifacts_container_repository.main \
  -auto-approve

success "OCIR repo ready"

# ── Build & push Docker image ──────────────────────────────────────────────────
divider
info "Logging into OCIR (${REGISTRY})..."
warn "Enter your OCI Auth Token as the password (Profile → My Profile → Auth Tokens)"
TENANCY_NS=$(oci os ns get --query 'data' --raw-output 2>/dev/null || echo "${NAMESPACE}")
USER_EMAIL=$(oci iam user list --all --query 'data[0]."email"' --raw-output 2>/dev/null || echo "YOUR_EMAIL")
docker login "${REGISTRY}" -u "${TENANCY_NS}/${USER_EMAIL}"

info "Building linux/arm64 image..."
cd "${PROJECT_ROOT}"
docker buildx build --platform linux/arm64 -t "${IMAGE_PATH}" .

info "Pushing image to OCIR..."
docker push "${IMAGE_PATH}"
success "Image pushed: ${IMAGE_PATH}"

# ── Phase 2: Full apply ────────────────────────────────────────────────────────
divider
info "Phase 2 — Applying full Terraform config (ADB + network + container instance)..."
warn "ADB provisioning takes 3–5 minutes — this is normal."
cd "${TF_DIR}"
terraform apply -auto-approve

# ── Print results ─────────────────────────────────────────────────────────────
divider
success "Deploy complete!"
echo ""
echo "  App URL:   $(terraform output -raw app_url 2>/dev/null || echo 'run: terraform output app_url')"
echo "  ORDS URL:  $(terraform output -raw ords_base_url 2>/dev/null || echo 'run: terraform output ords_base_url')"
echo ""
INSTANCE_OCID=$(terraform output -raw container_instance_ocid 2>/dev/null || echo "")
if [[ -n "$INSTANCE_OCID" ]]; then
  echo "  Container Instance OCID: ${INSTANCE_OCID}"
  echo ""
  warn "Add to ~/.zshrc: export CLOUD_STORE_OCID=\"${INSTANCE_OCID}\""
fi
echo ""
warn "Container instance may take 1–2 minutes to become ACTIVE."
info "Check status: ./scripts/container.sh status"
