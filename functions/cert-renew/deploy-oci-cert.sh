#!/bin/bash
# Certbot deploy hook — push renewed PEMs into OCI Certificates (same cert OCID).
# Env: CERT_OCID (required), RENEWED_LINEAGE (set by certbot).

set -euo pipefail

: "${CERT_OCID:?CERT_OCID is required}"
: "${RENEWED_LINEAGE:?RENEWED_LINEAGE is required (certbot deploy-hook)}"

PYTHON="${PYTHON:-/usr/bin/python3.11}"
OCI_RP="/function/oci_rp.py"

echo "Deploying renewed cert to OCI Certificates: ${CERT_OCID}"

"${PYTHON}" "${OCI_RP}" cert-import \
  --certificate-id "${CERT_OCID}" \
  --cert "${RENEWED_LINEAGE}/cert.pem" \
  --key "${RENEWED_LINEAGE}/privkey.pem" \
  --chain "${RENEWED_LINEAGE}/chain.pem"

echo "OCI Certificates update submitted."
