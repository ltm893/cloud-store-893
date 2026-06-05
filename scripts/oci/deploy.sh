#!/bin/zsh
# deploy.sh — Full Terraform + Docker deploy (single compartment: cloud-store)
#
# Run this from the project root:
#   chmod +x scripts/oci/deploy.sh   (first time only)
#   ./scripts/oci/deploy.sh

set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="${0:a:h}"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
TF_DIR="${PROJECT_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }
divider() { echo "\n${BLUE}────────────────────────────────────────${NC}\n" }

# Run terraform and surface failures (piping to grep alone hides non-zero exits).
run_terraform_apply() {
  local label="$1"
  shift
  local logf
  logf=$(mktemp)
  "$@" 2>&1 | tee "$logf" | grep -E '(Apply complete|No changes|Plan:|Error:|error:|created|updated|destroyed|Replaced|ocid)' || true
  local ec=${pipestatus[1]}
  if [[ "$ec" -ne 0 ]]; then
    local tail_out
    tail_out=$(tail -80 "$logf" 2>/dev/null || true)
    rm -f "$logf"
    error "${label} failed (terraform exit ${ec}). Last lines:\n${tail_out}\n\nFull re-run: cd ${TF_DIR} && terraform apply"
  fi
  rm -f "$logf"
}

run_terraform_init() {
  local logf
  logf=$(mktemp)
  terraform init -upgrade -no-color 2>&1 | tee "$logf" | grep -E '(Initializing|provider|complete|Error|error)' || true
  local ec=${pipestatus[1]}
  if [[ "$ec" -ne 0 ]]; then
    local tail_out
    tail_out=$(tail -80 "$logf" 2>/dev/null || true)
    rm -f "$logf"
    error "terraform init failed (exit ${ec}). Last lines:\n${tail_out}\n\ncd ${TF_DIR} && terraform init -upgrade"
  fi
  rm -f "$logf"
}

# ── Helper: read a value from terraform.tfvars ────────────────────────────────
tfvar() { grep "^${1}" "${TFVARS}" | sed 's/.*= *"//' | sed 's/".*//' | tr -d ' ' }

# ── Helper: locate SQLcl binary ───────────────────────────────────────────────
# Wraps detection in a subshell so set -e failures don't kill the script.
find_sqlcl() {
  # 1. Try bare 'sql' on PATH (works after adding /opt/sqlcl/bin to ~/.zshrc)
  if command -v sql &>/dev/null; then
    echo "sql"
    return
  fi
  # 2. Try standard manual install location
  if [[ -x "/opt/sqlcl/bin/sql" ]]; then
    echo "/opt/sqlcl/bin/sql"
  fi
}

# ── Prereq checks ─────────────────────────────────────────────────────────────
divider
info "Checking prerequisites..."

command -v terraform &>/dev/null || error "terraform not found. Run: brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
command -v docker    &>/dev/null || error "docker not found."
command -v oci       &>/dev/null || error "OCI CLI not found. Run: brew install oci-cli"
docker info &>/dev/null          || error "Docker daemon not running. Run: colima start"
[[ -f "${TFVARS}" ]]             || error "terraform/terraform.tfvars not found. Copy terraform.tfvars.example → terraform.tfvars and fill in your values."

# SQLcl — optional, needed for Phase 3 seed
SQL_CMD=$(find_sqlcl || true)
if [[ -n "$SQL_CMD" ]]; then
  # Verify Java 11+ is present (SQLcl requirement)
  if ! command -v java &>/dev/null; then
    warn "SQLcl found but Java is missing — seed will be skipped. Install: brew install --cask temurin"
    SQL_CMD=""
  elif ! java -version 2>&1 | grep -qE 'version "(1[1-9]|[2-9][0-9])'; then
    warn "SQLcl requires Java 11+ — seed will be skipped. Install: brew install --cask temurin"
    SQL_CMD=""
  else
    info "SQLcl found: ${SQL_CMD}"
  fi
else
  warn "SQLcl not found — seed will be skipped. Install: brew install --cask temurin && brew install sqlcl"
fi

# ── Read image path components from tfvars ────────────────────────────────────
NAMESPACE=$(tfvar "object_storage_namespace")
REGION_KEY=$(tfvar "ocir_region_key")
PROJECT=$(tfvar "project_name")
IMAGE_TAG=$(tfvar "ocir_image_tag")

[[ -z "$PROJECT"   ]] && PROJECT="cloud-store"
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
run_terraform_init

# ── Phase 1: Create compartment + OCIR repo ────────────────────────────────────
divider
info "Phase 1 — Compartment and OCIR repo..."
run_terraform_apply "Phase 1 (compartment + OCIR)" terraform apply \
  -target=oci_identity_compartment.main \
  -target=oci_artifacts_container_repository.main \
  -auto-approve -compact-warnings -no-color
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
info "Phase 2 — VCN, ADB, and Container Instance..."
warn "ADB provisioning takes 3–5 minutes on first run — this is normal."
cd "${TF_DIR}"
run_terraform_apply "Phase 2 (full stack)" terraform apply -auto-approve -compact-warnings -no-color

# ── Print resource summary ─────────────────────────────────────────────────────
divider
info "Resource Summary"
echo ""
echo "  App URL:              $(terraform output -raw app_url              2>/dev/null || echo 'not available')"
echo "  ORDS URL:             $(terraform output -raw ords_base_url        2>/dev/null || echo 'not available')"
echo "  ADB OCID:             $(terraform output -raw adb_ocid             2>/dev/null || echo 'not available')"
echo "  VCN OCID:             $(terraform output -raw vcn_ocid             2>/dev/null || echo 'not available')"
echo "  Container OCID:       $(terraform output -raw container_instance_ocid 2>/dev/null || echo 'not available')"
echo "  Compartment OCID:     $(terraform output -raw compartment_ocid    2>/dev/null || echo 'not available')"
echo ""

# ── Phase 3: Seed the database ────────────────────────────────────────────────
divider
info "Phase 3 — Seeding the database via SQLcl..."

if [[ -z "$SQL_CMD" ]]; then
  warn "SQLcl not available — skipping seed."
  warn "Run manually: paste scripts/seed.sql into OCI Database Actions → SQL"
else
  cd "${TF_DIR}"
  ADB_OCID=$(terraform output -raw adb_ocid 2>/dev/null)
  ADB_PASSWORD=$(tfvar "adb_admin_password")
  DB_NAME=$(tfvar "adb_db_name")
  [[ -z "$DB_NAME" ]] && DB_NAME="CLOUDSTORE893"
  DB_SERVICE="${DB_NAME:l}_high"   # e.g. cloudstore893_high

  # Wait for ORDS to respond before connecting
  ORDS_URL=$(terraform output -raw ords_base_url 2>/dev/null)
  info "Waiting for ORDS at ${ORDS_URL}..."
  ATTEMPT=0
  MAX_ATTEMPTS=12  # 12 × 10s = 2 minutes
  until curl -s --max-time 5 "${ORDS_URL}" -o /dev/null; do
    ATTEMPT=$((ATTEMPT + 1))
    [[ $ATTEMPT -ge $MAX_ATTEMPTS ]] && \
      error "ORDS not ready after $((MAX_ATTEMPTS * 10))s — check ADB status in OCI Console."
    warn "ORDS not ready — retrying in 10s... (${ATTEMPT}/${MAX_ATTEMPTS})"
    sleep 10
  done
  success "ORDS is ready!"

  # Download wallet to a temp dir
  WALLET_DIR=$(mktemp -d)
  WALLET_ZIP="${WALLET_DIR}/wallet.zip"
  info "Downloading ADB wallet..."
  oci db autonomous-database generate-wallet \
    --autonomous-database-id "${ADB_OCID}" \
    --password "WalletTemp1!" \
    --file "${WALLET_ZIP}" || error "Wallet download failed — check OCI CLI auth."

  # Run seed.sql
  info "Running seed.sql against ${DB_SERVICE}..."
  "${SQL_CMD}" -cloudconfig "${WALLET_ZIP}" \
    "admin/${ADB_PASSWORD}@${DB_SERVICE}" \
    @"${PROJECT_ROOT}/scripts/seed.sql"

  rm -rf "${WALLET_DIR}"
  success "Database seeded!"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
divider
success "Deploy complete!"
CONTAINER_OCID=$(cd "${TF_DIR}" && terraform output -raw container_instance_ocid 2>/dev/null || true)
if [[ -n "$CONTAINER_OCID" ]]; then
  warn "Save to ~/.zshrc: export CLOUD_STORE_OCID=\"${CONTAINER_OCID}\""
fi
warn "Container instance may take 1–2 minutes to become ACTIVE."
info "Check status: ./scripts/oci/container.sh status"
