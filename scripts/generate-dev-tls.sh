#!/bin/zsh
# Generate a self-signed TLS cert for local HTTPS dev.
#
#   ./scripts/generate-dev-tls.sh
#
# Then add to .env:
#   TLS_KEY_PATH=certs/dev-key.pem
#   TLS_CERT_PATH=certs/dev-cert.pem
#   CASHIER_SESSION_SECURE=true
#   APP_PUBLIC_URL=https://127.0.0.1:3000

set -e

SCRIPT_DIR="${0:a:h}"
PROJECT_ROOT="${SCRIPT_DIR}/.."
CERT_DIR="${PROJECT_ROOT}/certs"

mkdir -p "$CERT_DIR"

openssl req -x509 -newkey rsa:2048 \
  -keyout "${CERT_DIR}/dev-key.pem" \
  -out "${CERT_DIR}/dev-cert.pem" \
  -days 365 -nodes \
  -subj '/CN=localhost'

echo "✅ Wrote ${CERT_DIR}/dev-key.pem and ${CERT_DIR}/dev-cert.pem"
echo "Add to .env:"
echo "  TLS_KEY_PATH=certs/dev-key.pem"
echo "  TLS_CERT_PATH=certs/dev-cert.pem"
echo "  CASHIER_SESSION_SECURE=true"
echo "  APP_PUBLIC_URL=https://127.0.0.1:\${PORT:-3000}"
