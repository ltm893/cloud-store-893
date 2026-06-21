# OCI dev environment

Pre-production stack at **`https://dev.oci.cloudstore893.com/`** — separate compartment, ADB, VCN, and load balancer from prod (`oci.cloudstore893.com`).

Related: [oci-deploy.md](oci-deploy.md) (prod + shared deploy procedures), [oci-load-balancer-https.md](oci-load-balancer-https.md) (TLS), [versioning.md](versioning.md) (promote dev → prod).

---

## Architecture

| | **Prod** | **Dev** |
|---|----------|---------|
| Hostname | `oci.cloudstore893.com` | `dev.oci.cloudstore893.com` |
| Compartment | `cloud-store` | `cloud-store-dev` |
| OCIR repo | `cloud-store` | `cloud-store-dev` |
| Terraform var-file | `terraform/terraform.tfvars` | `terraform/terraform.dev.tfvars` |
| Terraform state | `terraform/terraform.tfstate` | `terraform/terraform.dev.tfstate` |
| Container OCID env | `CLOUD_STORE_OCID` | `CLOUD_STORE_DEV_OCID` |
| Local env file | `.env` | `.env.dev` (optional) |
| Wrapper scripts | `redeploy-app-code.sh`, `deploy.sh`, … | `*-dev.sh` (sets `CLOUD_STORE_ENV=dev`) |

Both stacks share the same Terraform module under `terraform/`. Dev adds an **A record** in the existing OCI DNS zone `oci.cloudstore893.com` — no second Route 53 NS delegation.

Environment selection is handled by `scripts/oci/lib/terraform-env.sh`. **`CLOUD_STORE_ENV=dev`** (or `*-dev.sh` wrappers) always use dev var-file and state — do not export a stale `CLOUD_STORE_TF_STATE` pointing at prod.

---

## Promotion workflow

1. Merge to `dev` branch; CI passes (`npm test`).
2. Deploy to **OCI dev**; smoke test (curl + tablet).
3. Run any DDL on **dev ADB** first.
4. Deploy the **same git SHA** to prod with the **same label**:
   ```bash
   ./scripts/oci/redeploy-app-code.sh "same label as dev deploy"
   ```
5. Apply the same DDL on prod ADB if needed.

---

## One-time setup

### 1. Terraform var-file

```bash
cp terraform/terraform.dev.tfvars.example terraform/terraform.dev.tfvars
./scripts/oci/bootstrap-dev-tfvars.sh   # copies OCI auth + namespace from prod tfvars
```

Edit `terraform/terraform.dev.tfvars` and set a **unique** `adb_admin_password`.

### 2. Greenfield deploy

```bash
./scripts/oci/deploy-dev.sh
```

Add to `~/.zshrc`:

```bash
export CLOUD_STORE_DEV_OCID="<container_instance_ocid from deploy output>"
```

Optional local ORDS URL for dev:

```bash
./scripts/sync-env-dev.sh   # writes .env.dev ORDS_BASE_URL from dev state
```

### 3. DNS

Run **after** deploy completes and the dev load balancer exists:

```bash
CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh
dig A dev.oci.cloudstore893.com +short @8.8.8.8
```

Uses `oci dns record domain patch` (not zone replace) so SOA/NS records stay intact.

### 4. HTTPS

Follow [oci-load-balancer-https.md](oci-load-balancer-https.md) for `dev.oci.cloudstore893.com`, set `lb_certificate_ocid` in `terraform.dev.tfvars`, then:

```bash
./scripts/oci/terraform-apply-container-dev.sh
```

### 5. IdP (optional)

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-....identity.us-ashburn-1.oci.oraclecloud.com"
./scripts/oci/idp-update-redirect-uris-dev.sh
```

### 6. Tablet

```bash
cd android-pos
API_BASE_URL=https://dev.oci.cloudstore893.com/ ./RebuildReinstall.sh
```

---

## Day-to-day: deploy app code to dev

Most common path after changing server code:

```bash
./scripts/oci/redeploy-app-code-dev.sh "what changed"
```

Non-interactive (when Terraform warns the container instance will be replaced):

```bash
AUTO_YES=1 ./scripts/oci/redeploy-app-code-dev.sh "what changed"
# or: ./scripts/oci/redeploy-app-code-dev.sh "what changed" --yes
```

This script:

1. Builds and pushes `cloud-store-dev:<BUILD_ID>` and `:latest` to OCIR.
2. Runs `terraform apply` with `-var ocir_image_tag=<BUILD_ID>` against **dev state**.
3. Waits for `GET https://dev.oci.cloudstore893.com/api/build-info` with matching `buildId`.
4. If the container was replaced, runs **`dev-dns-a-record.sh`** so the A record matches the new LB IP.

**After replace**, refresh shell OCID if scripts warn it is stale:

```bash
export CLOUD_STORE_DEV_OCID="$(cd terraform && terraform output -state=terraform.dev.tfstate -raw container_instance_ocid)"
```

### Verify dev

```bash
APP=$(CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh)
curl -s "$APP/api/build-info" | jq .
```

If hostname returns an **old `buildId`** but direct LB IP is correct, DNS is stale:

```bash
CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # macOS local cache
```

---

## Day-to-day command reference

| Task | Dev command |
|------|-------------|
| App code deploy | `./scripts/oci/redeploy-app-code-dev.sh "what changed"` |
| Env / IdP flags | `./scripts/oci/sync-container-env-to-terraform-dev.sh` → `./scripts/oci/terraform-apply-container-dev.sh` |
| DNS A record | `CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh` |
| Live URL | `CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh` |
| Promote to prod | `./scripts/oci/redeploy-app-code.sh "same label"` |

Use `CLOUD_STORE_ENV=dev` on any OCI script when a `*-dev.sh` wrapper does not exist. Default is prod.

**Do not use `restart-container-instance.sh` to ship new code** — it re-runs the cached image digest only.

---

## Implementation notes

- `scripts/oci/lib/terraform-env.sh` — selects var-file, state file, hostname per `CLOUD_STORE_ENV`.
- Prod container env: `container_env.prod.tfvars` (legacy `container_env.auto.tfvars` still loaded if present).
- Dev container env: `container_env.dev.tfvars` (from `.env.dev` via sync script).
- App code deploys change `ocir_image_tag` → Terraform **replaces** the container instance (expected on both dev and prod).
