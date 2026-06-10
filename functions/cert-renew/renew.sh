#!/bin/bash
# Let's Encrypt renew + OCI Certificates deploy. Intended for OCI Functions (resource principal).
#
# Env (required):
#   CERT_HOSTNAME          e.g. oci.cloudstore893.com
#   CERT_OCID              OCI Certificates resource OCID
#   CERTBOT_STATE_BUCKET   Object Storage bucket for certbot config/work/logs
#   CERTBOT_STATE_OBJECT   Object name (default certbot-state.tar.gz)
#
# Env (optional):
#   CERTBOT_EMAIL          Let's Encrypt account email
#   DRY_RUN                1 = certbot --dry-run (staging server)
#   FORCE_RENEW            1 = certbot --force-renewal (POC only; rate limits apply)
#   DNS_PROPAGATION_SECS   default 120

set -euo pipefail

if [[ "${1:-}" == "--smoke-test" ]]; then
  SMOKE_TEST=1
fi

: "${CERT_HOSTNAME:?CERT_HOSTNAME is required}"
: "${CERT_OCID:?CERT_OCID is required}"
: "${CERTBOT_STATE_BUCKET:?CERTBOT_STATE_BUCKET is required}"

CERTBOT_STATE_OBJECT="${CERTBOT_STATE_OBJECT:-certbot-state.tar.gz}"
DNS_PROPAGATION_SECS="${DNS_PROPAGATION_SECS:-120}"
STATE_ROOT="/tmp/certbot"
mkdir -p "${STATE_ROOT}"

PYTHON="${PYTHON:-/usr/bin/python3.11}"
OCI_RP="/function/oci_rp.py"

fix_renewal_paths() {
  "${PYTHON}" -c "
import glob
import os
import sys

state_root = sys.argv[1]
renewal_dir = os.path.join(state_root, 'config', 'renewal')
if not os.path.isdir(renewal_dir):
    sys.exit(0)

for path in glob.glob(os.path.join(renewal_dir, '*.conf')):
    with open(path, encoding='utf-8') as handle:
        lines = handle.readlines()
    old_base = None
    for line in lines:
        if line.startswith('config_dir = '):
            old_base = line.split(' = ', 1)[1].strip()
            old_base = old_base[: -len('/config')] if old_base.endswith('/config') else old_base
            break
    if not old_base or old_base == state_root:
        continue
    new_root = state_root
    with open(path, 'w', encoding='utf-8') as handle:
        for line in lines:
            handle.write(line.replace(old_base, new_root))
" "${STATE_ROOT}"
}

echo "==> Restoring certbot state from Object Storage (if present)"
if "${PYTHON}" "${OCI_RP}" os-head \
  --bucket "${CERTBOT_STATE_BUCKET}" \
  --name "${CERTBOT_STATE_OBJECT}"; then
  "${PYTHON}" "${OCI_RP}" os-get \
    --bucket "${CERTBOT_STATE_BUCKET}" \
    --name "${CERTBOT_STATE_OBJECT}" \
    --file /tmp/certbot-state.tar.gz
  rm -rf "${STATE_ROOT:?}/"*
  "${PYTHON}" -c "
import os
import sys
import tarfile

archive_path, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
with tarfile.open(archive_path, 'r:gz') as archive:
    for member in archive.getmembers():
        name = member.name.lstrip('./')
        if '/._' in name or name.startswith('._'):
            continue
        archive.extract(member, dest, filter='data')
" /tmp/certbot-state.tar.gz "${STATE_ROOT}"
  fix_renewal_paths
  echo "    Restored ${CERTBOT_STATE_OBJECT}"
else
  echo "    No state object yet — first run will register account and issue/renew."
  mkdir -p "${STATE_ROOT}/config" "${STATE_ROOT}/work" "${STATE_ROOT}/logs"
fi

if [[ "${SMOKE_TEST:-0}" == "1" ]]; then
  echo "==> SMOKE_TEST: restore state, validate certbot + dns-oci plugin"
  echo "==> Running certbot certificates"
  certbot certificates \
    --config-dir "${STATE_ROOT}/config" \
    --work-dir "${STATE_ROOT}/work" \
    --logs-dir "${STATE_ROOT}/logs"
  echo "==> dns-oci plugin"
  certbot plugins --text | grep -i dns-oci
  echo "==> Smoke test OK"
  exit 0
fi

CERTBOT_BASE=(
  --non-interactive
  --agree-tos
  --config-dir "${STATE_ROOT}/config"
  --work-dir "${STATE_ROOT}/work"
  --logs-dir "${STATE_ROOT}/logs"
  --authenticator dns-oci
  --dns-oci-instance-principal=y
  --dns-oci-propagation-seconds "${DNS_PROPAGATION_SECS}"
)

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  CERTBOT_BASE+=(
    --deploy-hook /function/deploy-oci-cert.sh
    --run-deploy-hooks
  )
fi

if [[ -n "${CERTBOT_EMAIL:-}" ]]; then
  CERTBOT_BASE+=(--email "${CERTBOT_EMAIL}")
else
  CERTBOT_BASE+=(--register-unsafely-without-email)
fi

has_renewal_conf() {
  [[ -d "${STATE_ROOT}/config/renewal" ]] \
    && ls "${STATE_ROOT}/config/renewal/"*.conf >/dev/null 2>&1
}

use_renew=false
if has_renewal_conf; then
  use_renew=true
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "==> DRY_RUN: using Let's Encrypt staging (no production cert change)"
fi

if [[ "${FORCE_RENEW:-0}" == "1" ]]; then
  CERTBOT_BASE+=(--force-renewal)
fi

if [[ "${use_renew}" == true ]]; then
  CERTBOT_ARGS=(renew "${CERTBOT_BASE[@]}" --cert-name "${CERT_HOSTNAME}")
else
  CERTBOT_ARGS=(certonly "${CERTBOT_BASE[@]}" -d "${CERT_HOSTNAME}")
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  CERTBOT_ARGS+=(--dry-run)
fi

echo "==> Running certbot ${CERTBOT_ARGS[*]}"
certbot "${CERTBOT_ARGS[@]}"

echo "==> Saving certbot state to Object Storage"
"${PYTHON}" -c "
import os
import sys
import tarfile

root, archive_path = sys.argv[1], sys.argv[2]
with tarfile.open(archive_path, 'w:gz') as archive:
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            if filename.startswith('._'):
                continue
            full_path = os.path.join(dirpath, filename)
            arcname = os.path.relpath(full_path, root)
            archive.add(full_path, arcname=arcname)
" "${STATE_ROOT}" /tmp/certbot-state.tar.gz
"${PYTHON}" "${OCI_RP}" os-put \
  --bucket "${CERTBOT_STATE_BUCKET}" \
  --name "${CERTBOT_STATE_OBJECT}" \
  --file /tmp/certbot-state.tar.gz

echo "==> Done"
