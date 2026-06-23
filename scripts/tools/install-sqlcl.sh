#!/bin/zsh
# install-sqlcl.sh — Download, install, and configure SQLcl on macOS
#
# What this script does:
#   1. Installs Java 21 LTS (Temurin) via Homebrew if not present
#   2. Removes any existing /opt/sqlcl installation
#   3. Downloads sqlcl-latest.zip from Oracle
#   4. Extracts to /opt/sqlcl and fixes permissions
#   5. Adds /opt/sqlcl/bin to PATH and sets JAVA_HOME=21 in ~/.zshrc
#   6. Verifies with: sql -version
#
# Usage:
#   chmod +x scripts/install-sqlcl.sh
#   ./scripts/install-sqlcl.sh

set -e

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }
divider() { echo "\n${BLUE}────────────────────────────────────────${NC}\n" }

SQLCL_DIR="/opt/sqlcl"
SQLCL_ZIP="/tmp/sqlcl-latest.zip"
SQLCL_URL="https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
ZSHRC="$HOME/.zshrc"

# ── Step 1: Java 21 LTS ───────────────────────────────────────────────────────
divider
info "Step 1 — Checking for Java 21 LTS..."

# SQLcl requires Java 11-21. Java 22+ has module changes that break SQLcl's
# classloader. Java 21 is the current LTS and the safest choice.
JAVA21_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || true)

if [[ -z "$JAVA21_HOME" ]]; then
  info "Java 21 not found — installing Temurin 21 via Homebrew..."
  brew install --cask temurin@21
  JAVA21_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null) || \
    error "Java 21 install succeeded but /usr/libexec/java_home can't find it. Try opening a new terminal."
fi

success "Java 21 found at: ${JAVA21_HOME}"

# ── Step 2: Remove existing SQLcl ────────────────────────────────────────────
divider
info "Step 2 — Removing any existing SQLcl at ${SQLCL_DIR}..."

if [[ -d "$SQLCL_DIR" ]]; then
  sudo rm -rf "$SQLCL_DIR"
  success "Removed ${SQLCL_DIR}"
else
  info "No existing installation found — skipping."
fi

# ── Step 3: Download ──────────────────────────────────────────────────────────
divider
info "Step 3 — Downloading SQLcl from Oracle..."
info "URL: ${SQLCL_URL}"

curl -L --progress-bar "${SQLCL_URL}" -o "${SQLCL_ZIP}"
ZIPSIZE=$(du -sh "${SQLCL_ZIP}" | cut -f1)
success "Downloaded ${ZIPSIZE} → ${SQLCL_ZIP}"

# ── Step 4: Extract and fix permissions ───────────────────────────────────────
divider
info "Step 4 — Extracting to ${SQLCL_DIR}..."

# unzip creates /opt/sqlcl/ from the zip's root folder
sudo unzip -q "${SQLCL_ZIP}" -d /opt/

# The zip extracts as root:wheel with -rw-r----- on the jars (no world-read).
# Java's classloader runs as your user and can't read the jars without this fix.
info "Fixing permissions (jars need to be world-readable)..."
sudo chmod -R a+r "${SQLCL_DIR}"
sudo chmod a+x "${SQLCL_DIR}/bin/sql"

success "Extracted and permissions fixed"

# ── Step 5: Configure ~/.zshrc ────────────────────────────────────────────────
divider
info "Step 5 — Configuring ~/.zshrc..."

# Remove any stale SQLcl/JAVA_HOME lines we may have added before
sed -i '' '/# SQLcl/d' "${ZSHRC}" 2>/dev/null || true
sed -i '' '/opt\/sqlcl/d' "${ZSHRC}" 2>/dev/null || true
sed -i '' '/java_home.*21/d' "${ZSHRC}" 2>/dev/null || true

# Add fresh block
cat >> "${ZSHRC}" <<'EOF'

# SQLcl — Oracle command-line SQL client
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
export PATH="/opt/sqlcl/bin:$PATH"
EOF

success "Added SQLcl PATH and JAVA_HOME=21 to ~/.zshrc"

# ── Step 6: Verify ────────────────────────────────────────────────────────────
divider
info "Step 6 — Verifying installation..."

export JAVA_HOME="${JAVA21_HOME}"
export PATH="/opt/sqlcl/bin:$PATH"

VERSION=$(/opt/sqlcl/bin/sql -version 2>&1) || \
  error "SQLcl installed but failed to run. Check output above."

success "SQLcl is working!"
echo ""
echo "  ${VERSION}"
echo ""

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "${SQLCL_ZIP}"
info "Cleaned up ${SQLCL_ZIP}"

# ── Source ~/.zshrc ───────────────────────────────────────────────────────────
# Note: this applies to the current script process only.
# Your terminal session still needs 'source ~/.zshrc' or a new window.
if [[ -f "${ZSHRC}" ]]; then
  source "${ZSHRC}" 2>/dev/null || true
  info "Sourced ~/.zshrc in this session"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
divider
success "SQLcl install complete!"
echo ""
echo "  Binary:     /opt/sqlcl/bin/sql"
echo "  Java:       ${JAVA21_HOME}"
echo "  Config:     ~/.zshrc updated"
echo ""
warn "Open a new terminal tab or run: source ~/.zshrc"
info "Then verify with: sql -version"
