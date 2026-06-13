# Deploy to OCI

**Living doc** — how to push local changes to the running stack at **`https://oci.cloudstore893.com/`**.

Related: [README.md](../README.md), [CONTENTS.md](../CONTENTS.md), [oci-network-recovery.md](oci-network-recovery.md), [idp-setup.md](idp-setup.md), [testing.md](testing.md#oci-deploy-verification-manual).

---

## Prerequisites (once per machine)

```bash
cd /path/to/cloud-store-893

colima start                    # if Docker isn’t running
oci setup config                # if OCI CLI isn’t configured
docker login iad.ocir.io        # OCIR auth token when prompted
```

Terraform state and `terraform/terraform.tfvars` must already exist (greenfield: [README — Deploy from scratch](../README.md#deploy-from-scratch)).

---

## Quick decision guide

| What changed | What to run |
|--------------|-------------|
| Node server, `lib/`, admin UI (`public/admin/`) | `./scripts/oci/redeploy-app-code.sh` |
| `.env` flags (Model B, IdP, session secure, TTL) | `sync-container-env-to-terraform.sh` → `terraform-apply-container.sh` → maybe `reattach-reserved-ip.sh` |
| PINs only | Edit `terraform/terraform.tfvars` (`cashier_pin`, `admin_pin`) → `terraform apply` |
| New DB tables / ORDS endpoints | Schema step below, then redeploy app |
| Oracle IdP redirect URIs | `./scripts/oci/idp-update-redirect-uris.sh` |
| Tablet Kotlin UI or API client | Rebuild APK (`android-pos/RebuildReinstall.sh`) + redeploy server if APIs changed |

**Prefer `redeploy-app-code.sh` for code** — it rebuilds, pushes, and restarts the **same** container instance (keeps public IP / LB attachment).

**Avoid unnecessary `terraform apply` on the container** — env changes **replace** the instance and may detach the reserved IP. See [oci-network-recovery.md](oci-network-recovery.md).

---

## 1. App code only (most common)

After changes to `server.js`, `lib/`, `public/`, etc.:

```bash
./scripts/oci/redeploy-app-code.sh
# optional BUILD_ID label for GET /api/build-info:
# ./scripts/oci/redeploy-app-code.sh close-till-20260611
```

Builds `linux/arm64`, pushes to the OCIR tag in Terraform state, restarts the container instance.

### Verify

```bash
APP=$(./scripts/oci/confirm-public-url.sh)

curl -s "$APP/api/build-info"

curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "$APP/api/cashier/unlock" \
  -H 'Content-Type: application/json' \
  -d '{"pin":"8930"}'
```

| Result | Meaning |
|--------|---------|
| **200** on unlock | New image is live (PIN allowed on server) |
| **403** on unlock | Image is live; **Model B** on (`CASHIER_SUPERVISOR_APPROVAL=true`) — PIN blocked; use IdP sign-in |
| **404** on unlock | Stale image **or** double-slash URL — see below |

`confirm-public-url.sh` prints a base URL **without** a trailing slash. Always use:

```bash
APP=$(./scripts/oci/confirm-public-url.sh)
curl -s "$APP/api/build-info"
```

If `$APP` ends with `/`, `"$APP/api/..."` becomes `//api/...` and Express returns **404** (`Cannot GET //api/build-info`). Re-export `APP` or use `"${APP%/}/api/..."`.

Live URLs:

- POS: `https://oci.cloudstore893.com/`
- Admin: `https://oci.cloudstore893.com/admin/`

Optional read-only API smoke:

```bash
BASE_URL="$APP" SKIP_DESTRUCTIVE=yes ./scripts/test-api-curl.sh
```

---

## 2. Environment variables (`.env` → OCI container)

When you change Model B, IdP, session flags, or similar in repo `.env`:

```bash
./scripts/oci/sync-container-env-to-terraform.sh
./scripts/oci/terraform-apply-container.sh
```

PINs are **not** synced from `.env` — set `cashier_pin` / `admin_pin` in `terraform/terraform.tfvars`.

### After apply (if instance was replaced)

```bash
./scripts/oci/reattach-reserved-ip.sh
export CLOUD_STORE_OCID="$(cd terraform && terraform output -raw container_instance_id)"
```

Full checklist: [oci-network-recovery.md](oci-network-recovery.md).

### Env keys synced from `.env`

`sync-container-env-to-terraform.sh` copies: `CASHIER_SUPERVISOR_APPROVAL`, `CASHIER_APPROVAL_TTL_SEC`, `IDP_*`, `APP_PUBLIC_URL_FROM_REQUEST`, `CASHIER_SESSION_SECURE`, Cloudflare tunnel vars, etc. See script `KEYS=(…)` for the full list.

| Setting | Local | OCI |
|---------|-------|-----|
| `ORDS_BASE_URL` | `.env` | Terraform (from ADB; do not sync) |
| `CASHIER_PIN`, `ADMIN_PIN` | `.env` | `terraform.tfvars` |
| `OPENING_CASH_FLOAT` | `.env` | `sync-container-env-to-terraform.sh` → `terraform apply` |
| OAuth redirect host | N/A on OCI | `APP_PUBLIC_URL_FROM_REQUEST=true` (default) — browse via `https://oci.cloudstore893.com/` |

---

## 3. Database schema

Schema source of truth: `scripts/seed.sql` (tables + ORDS enablement).

### Destructive full reseed (wipes data)

```bash
./scripts/reset-db.sh --yes
```

### Incremental (keep data)

Run only the new DDL in Database Actions / SQLcl. Examples in repo:

| Migration | Script |
|-----------|--------|
| Login approval till columns | `./scripts/migrate-login-approval-till.sh` |
| Shift close, `sales.shift_id`, etc. | Apply relevant sections from `scripts/seed.sql` manually (no dedicated migrate script yet) |

After schema changes, redeploy app code (step 1).

---

## 4. Oracle Identity (IdP redirect URIs)

When hostname or callback paths change:

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-XXXX....identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="oci.cloudstore893.com"
export APP_PUBLIC_SCHEME="https"
export APP_PUBLIC_PORT=""   # empty = omit :443

./scripts/oci/idp-update-redirect-uris.sh
```

Local / tablet LAN dev uses the same script with `APP_PUBLIC_HOST=<Mac LAN IP>` and `APP_PUBLIC_SCHEME=http` — see [idp-setup.md](idp-setup.md).

---

## 5. Tablet APK

Server deploy does **not** update the installed tablet app.

```bash
cd android-pos
./RebuildReinstall.sh   # default API: https://oci.cloudstore893.com/
```

Rebuild when Kotlin UI or baked-in `API_BASE_URL` changes.

---

## 6. Greenfield (new OCI environment)

Only when infrastructure does not exist yet:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill OCIDs, passwords

cd ..
./scripts/oci/deploy.sh
```

End-to-end: compartment, OCIR, image push, VCN, ADB, container instance, DB seed.

---

## 7. Alternate paths (less common)

| Script | When |
|--------|------|
| `./scripts/oci/restart-container-instance.sh` | Image already pushed; only need restart |
| `./scripts/oci/deploy-app-oci.sh <tag>` | New OCIR **tag** via Terraform (may replace instance) |
| `./scripts/oci/confirm-public-url.sh` | Resolve live URL after IP drift (prefer over stale `terraform output app_url`) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `POST /api/cashier/unlock` → **404** | Old container image | `redeploy-app-code.sh` |
| `invalid_redirect_uri` after deploy | IdP missing hostname callback | `idp-update-redirect-uris.sh` |
| URL / IP changed after apply | Instance replace | `reattach-reserved-ip.sh` + recovery doc |
| Shift close / till APIs → **500** | Schema not on ADB | Run DDL from `seed.sql` or `reset-db.sh` |
| `build-info` → `unknown` locally | No `BUILD_ID` at dev start | Normal for `npm run dev:up`; redeploy sets it on OCI |

---

## Journey log

| Date | Notes |
|------|-------|
| 2026-06-11 | Consolidated deploy guide (code, env, DB, IdP, tablet, decision table). |
