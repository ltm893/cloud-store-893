#!/usr/bin/env bash
# Verify OCI DNS delegation + certbot-dns-oci can complete a Let's Encrypt DNS-01 challenge.
#
# Prerequisites (one-time on your Mac):
#   brew install certbot oci-cli
#   git clone https://github.com/therealcmj/certbot-dns-oci.git /tmp/certbot-dns-oci
#   CERTBOT_SITE="$(/opt/homebrew/Cellar/certbot/*/libexec/bin/python3 -c 'import site; print(site.getsitepackages()[0])')"
#   /opt/homebrew/Cellar/certbot/*/libexec/bin/python3 -m pip install --target "$CERTBOT_SITE" /tmp/certbot-dns-oci
#   certbot plugins   # should list dns-oci
#
# OCI IAM (your ~/.oci/config user): read dns-zones + manage dns-records in the compartment.
#
# Usage:
#   ./scripts/oci/verify-certbot-dns-oci.sh
#   ./scripts/oci/verify-certbot-dns-oci.sh --run-test    # LE staging cert (not trusted; proves ACME path)
#   HOST=oci.cloudstore893.com ./scripts/oci/verify-certbot-dns-oci.sh

set -euo pipefail

HOST="${HOST:-oci.cloudstore893.com}"
ZONE="${ZONE:-oci.cloudstore893.com}"
RUN_TEST=false
for arg in "$@"; do
  case "$arg" in
    --run-test) RUN_TEST=true ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERTBOT_DIRS="${PROJECT_ROOT}/certs/certbot"
COMPARTMENT_NAME="${CLOUD_STORE_COMPARTMENT_NAME:-cloud-store}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

echo "=== Step 6: certbot + OCI DNS for ${HOST} ==="
echo

# ── 1. Public DNS delegation ───────────────────────────────────────────────
echo "1. Public DNS (Google resolver)"
NS="$(dig NS "${ZONE}" +short @8.8.8.8 | sort -u | tr '\n' ' ')"
A="$(dig A "${HOST}" +short @8.8.8.8 | head -1)"
if [[ -z "$NS" ]]; then
  red "   FAIL: no NS for ${ZONE} — Route 53 delegation missing?"
  exit 1
fi
if [[ "$NS" != *oraclecloud.net* ]]; then
  red "   FAIL: NS not OCI (${NS})"
  exit 1
fi
green "   OK NS ${ZONE} → ${NS}"
if [[ -z "$A" ]]; then
  red "   FAIL: no A record for ${HOST}"
  exit 1
fi
green "   OK A   ${HOST} → ${A}"
echo

# ── 2. OCI zone + A record ───────────────────────────────────────────────────
echo "2. OCI DNS zone"
command -v oci >/dev/null || { red "   FAIL: oci CLI not found"; exit 1; }
COMPARTMENT_OCID="$(oci iam compartment list --all \
  --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" --raw-output)"
if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
  red "   FAIL: compartment '${COMPARTMENT_NAME}' not found"
  exit 1
fi
ZONE_JSON="$(oci dns zone get --zone-name-or-id "${ZONE}" 2>/dev/null || true)"
if [[ -z "$ZONE_JSON" ]]; then
  red "   FAIL: OCI zone '${ZONE}' not found"
  exit 1
fi
green "   OK zone ${ZONE} exists"
OCI_A="$(oci dns record rrset get --zone-name-or-id "${ZONE}" \
  --domain "${HOST}" --rtype A \
  --query 'data.items[0].rdata' --raw-output 2>/dev/null || true)"
if [[ -z "$OCI_A" || "$OCI_A" == "null" ]]; then
  red "   FAIL: no A record in OCI zone for ${HOST}"
  exit 1
fi
green "   OK OCI A ${HOST} → ${OCI_A}"
if [[ "$OCI_A" != "$A" ]]; then
  echo "   WARN public A (${A}) != OCI A (${OCI_A}) — propagation or stale cache?"
fi
echo

# ── 3. certbot + dns-oci plugin ──────────────────────────────────────────────
echo "3. certbot + dns-oci plugin"
command -v certbot >/dev/null || { red "   FAIL: certbot not installed (brew install certbot)"; exit 1; }
if ! certbot plugins 2>/dev/null | grep -q 'dns-oci'; then
  red "   FAIL: dns-oci plugin not installed — see script header for install steps"
  exit 1
fi
green "   OK certbot $(certbot --version 2>&1 | head -1)"
green "   OK dns-oci plugin registered"
echo

if [[ "$RUN_TEST" != true ]]; then
  echo "Pre-checks passed. To run a Let's Encrypt staging issuance:"
  echo "  $0 --run-test"
  exit 0
fi

# ── 4. LE staging cert (proves ACME + OCI DNS write access) ───────────────────
echo "4. Let's Encrypt staging cert (DNS-01 via OCI DNS)"
mkdir -p "${CERTBOT_DIRS}/config" "${CERTBOT_DIRS}/work" "${CERTBOT_DIRS}/logs"
certbot certonly \
  --test-cert \
  --logs-dir "${CERTBOT_DIRS}/logs" \
  --work-dir "${CERTBOT_DIRS}/work" \
  --config-dir "${CERTBOT_DIRS}/config" \
  --authenticator dns-oci \
  -d "${HOST}" \
  --agree-tos \
  --register-unsafely-without-email \
  --non-interactive \
  --dns-oci-propagation-seconds 120

green "   OK staging cert issued"
echo "   Certs: ${CERTBOT_DIRS}/config/live/${HOST}/"
echo
echo "Next (when ready for production):"
echo "  certbot certonly ... (drop --test-cert) → import to OCI Certificates → LB listener certificate_ids"
