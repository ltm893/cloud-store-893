# OCI network recovery after container instance replace

Living doc for what happens when the OCI **container instance** gets a new VNIC (new ephemeral public IP), how we recover today, and what we plan to automate.

**Related:** root [README.md](../README.md) (OCI env parity), [terraform/README.md](../terraform/README.md), [idp-setup.md](idp-setup.md).

---

## Why the IP changes

Oracle **replaces** the container instance (new VNIC) when Terraform changes certain container inputs — especially **environment variables** or an **`ocir_image_tag`** apply that forces replacement.

After replace:

- Terraform `app_url` and `container_instance_ocid` outputs may update.
- Oracle assigns a **new ephemeral public IP** on the new VNIC.
- A **reserved public IP does not reattach automatically** — it moves to lifecycle state `AVAILABLE` until you assign it to the new primary private IP.

**Does not change IP:** `./scripts/oci/restart-container-instance.sh` (same instance; reserved IP stays attached).

**Warns before replace:** `./scripts/oci/terraform-apply-container.sh`, `./scripts/oci/deploy-app-oci.sh`, and `./scripts/oci/sync-container-env-to-terraform.sh` (via `scripts/oci/lib/oci-ip-warn.sh`).

---

## Stable hostname setup (this project)

| Item | Value |
|------|--------|
| Reserved public IP | `129.153.187.63` |
| Reserved IP OCID | `ocid1.publicip.oc1.iad.amaaaaaa36usv6qatlrxmwbk2ehpwj5wr43rusqjcobno54msiok4mqfbh7q` |
| DNS (Route 53) | `oci.cloudstore893.com` → A → `129.153.187.63` |
| App URL | `http://oci.cloudstore893.com:3000` |

With this layout, **successful reattach** restores the same IP DNS already points at. You usually **do not** need Route 53 or tablet APK changes after recovery.

OAuth: `APP_PUBLIC_URL_FROM_REQUEST=true` on OCI (default in `terraform/container.tf`) — users should browse via **`oci.cloudstore893.com`**, not a raw ephemeral IP.

---

## Shell env vars (operator profile, not app `.env`)

Set in `~/.zshrc` (or export before running OCI scripts):

```bash
# Current container instance — refresh after every instance replace
export CLOUD_STORE_OCID=$(cd /path/to/cloud-store-893/terraform && terraform output -raw container_instance_ocid)

# Reserved public IP — stable across instance replaces
export CLOUD_STORE_RESERVED_PUBLIC_IP_OCID="ocid1.publicip.oc1.iad.amaaaaaa36usv6qatlrxmwbk2ehpwj5wr43rusqjcobno54msiok4mqfbh7q"
```

If `CLOUD_STORE_OCID` is stale, `./scripts/oci/confirm-public-url.sh` may fail with `NotAuthorizedOrNotFound` even when the app responds on the reserved IP. **Unset it** or refresh from terraform output.

Optional alias (referenced in deploy scripts; define locally if useful):

```bash
cloud-store-refresh-ocid() {
  export CLOUD_STORE_OCID=$(cd /path/to/cloud-store-893/terraform && terraform output -raw container_instance_ocid)
  echo "CLOUD_STORE_OCID=$CLOUD_STORE_OCID"
}
```

---

## What exists in the repo today (not one script)

| Step | Status | Tool |
|------|--------|------|
| Warn before instance replace | **Scripted** | `scripts/oci/lib/oci-ip-warn.sh` |
| Resolve live public URL | **Scripted** | `./scripts/oci/confirm-public-url.sh` |
| Detect detached reserved IP | **Partial** | `restart-container-instance.sh` warns if reserved IP is `AVAILABLE` |
| Reattach reserved IP to new VNIC | **Scripted** | `./scripts/oci/reattach-reserved-ip.sh` |
| Refresh `CLOUD_STORE_OCID` | **Scripted** | `reattach-reserved-ip.sh --refresh-ocid` or terraform output |
| Update IdCS redirect URIs | **Scripted (optional)** | `./scripts/oci/idp-update-redirect-uris.sh` or `--update-idp` on reattach script |
| Route 53 | **Manual (AWS)** | Usually **unchanged** if A record targets reserved IP |
| Tablet APK rebuild | **Manual** | Only if **hostname** changes — not needed after reattach with stable DNS |

Post-apply hooks on `deploy-app-oci.sh` and `terraform-apply-container.sh` offer to run reattach when a plan detects container replace (pass `--recover-network` to run automatically).

---

## Manual recovery checklist (after instance replace)

Run from repo root when `oci.cloudstore893.com` times out or reserved IP shows `AVAILABLE`.

**Automated:** `./scripts/oci/reattach-reserved-ip.sh` runs steps 1–4 below (prompts unless `--yes`). Add `--refresh-ocid` to print `export CLOUD_STORE_OCID=...`, `--update-idp` to call `idp-update-redirect-uris.sh`, or `--dry-run` to print actions only.

After `deploy-app-oci.sh` or `terraform-apply-container.sh` when the plan showed a container replace, the scripts **offer** to run reattach interactively; pass **`--recover-network`** to run it automatically (requires `CLOUD_STORE_RESERVED_PUBLIC_IP_OCID`).

### Manual OCI CLI steps (reference)

### 1. Refresh instance OCID

```bash
cd terraform
export INSTANCE_OCID=$(terraform output -raw container_instance_ocid)
export CLOUD_STORE_OCID="$INSTANCE_OCID"
echo "INSTANCE_OCID=$INSTANCE_OCID"
```

### 2. Resolve VNIC and primary private IP

Container instances expose `vnic-id`, not `private-ip-id` directly:

```bash
export VNIC_ID=$(oci container-instances container-instance get \
  --container-instance-id "$INSTANCE_OCID" \
  --query 'data.vnics[0]."vnic-id"' \
  --raw-output)

export PRIVATE_IP_ID=$(oci network private-ip list \
  --vnic-id "$VNIC_ID" \
  --query 'data[0].id' \
  --raw-output)

echo "VNIC_ID=$VNIC_ID"
echo "PRIVATE_IP_ID=$PRIVATE_IP_ID"
```

Use **single quotes** on `--query` strings that contain backticks (JMESPath `true`).

### 3. Reattach reserved public IP

```bash
export RESERVED_OCID="${CLOUD_STORE_RESERVED_PUBLIC_IP_OCID:-ocid1.publicip.oc1.iad.amaaaaaa36usv6qatlrxmwbk2ehpwj5wr43rusqjcobno54msiok4mqfbh7q}"

oci network public-ip update \
  --public-ip-id "$RESERVED_OCID" \
  --private-ip-id "$PRIVATE_IP_ID" \
  --wait-for-state ASSIGNED
```

Confirm:

```bash
oci network public-ip get --public-ip-id "$RESERVED_OCID" \
  --query 'data.{"ip":"ip-address","state":"lifecycle-state"}' \
  --output table
```

### 4. Verify app

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://oci.cloudstore893.com:3000/
curl -s http://oci.cloudstore893.com:3000/api/admin/session | python3 -m json.tool

./scripts/oci/confirm-public-url.sh
# expect http://129.153.187.63:3000 (or reserved IP)
```

### 5. IdCS (only if needed)

If redirect URIs were registered for an **old ephemeral IP**, add/update host-based URIs or run:

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-....identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="oci.cloudstore893.com"   # or reserved IP without scheme
export APP_PORT="3000"
./scripts/oci/idp-update-redirect-uris.sh
```

Hostname-based redirects (`http://oci.cloudstore893.com:3000/oauth/...`) usually **need no change** after reattach.

### 6. Tablet

Only if the **hostname** changed:

```bash
cd android-pos
LAN_IP=oci.cloudstore893.com ./RebuildReinstall.sh
```

---

## Deploy paths and IP risk

| Goal | Command | Instance replaced? | Reserved IP risk |
|------|---------|-------------------|------------------|
| App code only | `./scripts/oci/redeploy-app-code.sh` | No | None |
| Tagged image deploy | `./scripts/oci/deploy-app-oci.sh <tag>` | **Often yes** | Reattach may be required |
| Env / IdP flags via Terraform | `sync-container-env-to-terraform.sh` + `terraform-apply-container.sh` | **Often yes** | Reattach may be required |
| Full stack + seed | `./scripts/oci/deploy.sh` | First deploy / major | Set up reserved IP once |

**Do not** run another `terraform apply` just to “fix” `APP_PUBLIC_URL` to a new ephemeral IP — that replaces the instance again.

---

## Automation reference

Implemented scripts and hooks (see sections above for manual CLI equivalent):

1. **`./scripts/oci/reattach-reserved-ip.sh`**
   - Resolves VNIC → private IP → `public-ip update` → wait → verify curl + `confirm-public-url.sh`
   - Uses `CLOUD_STORE_RESERVED_PUBLIC_IP_OCID` (or documented default OCID)
   - Flags: `--yes`, `--dry-run`, `--refresh-ocid`, `--update-idp`

2. **Post-apply hook** on `deploy-app-oci.sh` and `terraform-apply-container.sh`
   - When plan detects container replace and `CLOUD_STORE_RESERVED_PUBLIC_IP_OCID` is set, offers to run reattach (or `--recover-network` to run automatically)

3. **Operator env vars** — documented in [Shell env vars](#shell-env-vars-operator-profile-not-app-env) above; linked from root [README.md](../README.md) and [.env.example](../.env.example).

**Out of scope:** Route 53 (AWS credentials); only needed if DNS target changes.

---

## Quick diagnosis

| Symptom | Likely cause | First check |
|---------|--------------|-------------|
| `oci.cloudstore893.com` timeout after apply | Reserved IP detached | `oci network public-ip get --public-ip-id $RESERVED_OCID` → state `AVAILABLE` |
| `confirm-public-url.sh` → `NotAuthorizedOrNotFound` | Stale `CLOUD_STORE_OCID` | `unset CLOUD_STORE_OCID` or `cloud-store-refresh-ocid` |
| OAuth redirect mismatch | IdP URIs for old IP | Browse via hostname; update IdCS |
| `404` on `/api/cashier/unlock` | Stale container image | `restart-container-instance.sh` or redeploy image |
| Ephemeral IP works, hostname does not | Reserved IP not attached | `./scripts/oci/reattach-reserved-ip.sh` |
