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

| What changed | Prod | Dev |
|--------------|------|-----|
| Node server, `lib/`, admin UI (`public/admin/`) | `./scripts/oci/redeploy-app-code.sh "label"` | `./scripts/oci/redeploy-app-code-dev.sh "label"` |
| `.env` flags (Model B, IdP, session secure, TTL) | `sync-container-env-to-terraform.sh` → `terraform-apply-container.sh` | `sync-container-env-to-terraform-dev.sh` → `terraform-apply-container-dev.sh` |
| PINs only | Edit `terraform/terraform.tfvars` → `terraform apply` | Edit `terraform/terraform.dev.tfvars` → dev apply script |
| New DB tables / ORDS endpoints | Schema step below, then redeploy app | Same DDL on **dev ADB first**, then redeploy dev, then prod |
| Oracle IdP (greenfield) | Manual Console — [idp-setup.md](idp-setup.md) | `./scripts/oci/idp/bootstrap-dev.sh --apply` |
| Oracle IdP redirect URIs | `./scripts/oci/idp-update-redirect-uris.sh` | `./scripts/oci/idp-update-redirect-uris-dev.sh` |
| Tablet Kotlin UI or API client | Rebuild APK + redeploy server if APIs changed | Point APK at dev URL (see [oci-dev-environment.md](oci-dev-environment.md)) |

**Prefer `redeploy-app-code*.sh` for code** — builds, pushes a **unique OCIR tag** (`BUILD_ID`), runs **terraform apply**, and waits for `/api/build-info`.

**Do not use `restart-container-instance.sh` to deploy new code** — OCI caches the image digest at instance create time; restart re-runs the **same** image.

**App code deploy may replace the container instance** (new image tag → Terraform forces replacement). After replace:
- **Prod:** run `./scripts/oci/reattach-reserved-ip.sh` if the hostname stops responding — [oci-network-recovery.md](oci-network-recovery.md).
- **Dev:** redeploy auto-runs `dev-dns-a-record.sh` when the LB IP changes; refresh `CLOUD_STORE_DEV_OCID` from deploy output.

**Full dev stack reference:** [oci-dev-environment.md](oci-dev-environment.md).

---

## App code deploy (prod and dev)

After changes to `server.js`, `lib/`, `public/`, etc.:

### Production (`oci.cloudstore893.com`)

```bash
git checkout dev && git pull   # integration branch

./scripts/oci/redeploy-app-code.sh "short description of this deploy"
# non-interactive (skips "container will be replaced" prompt):
# AUTO_YES=1 ./scripts/oci/redeploy-app-code.sh "short description"
# or: ./scripts/oci/redeploy-app-code.sh "short description" --yes
```

What it does:

1. Sets `BUILD_ID` (`YYYYMMDDHHmmss`), `BUILD_LABEL` (your quoted string), `GIT_SHA` from git.
2. Builds `linux/arm64`, tags `iad.ocir.io/…/cloud-store:<BUILD_ID>` and `:latest`, pushes both.
3. `terraform plan` / `apply` with `-var ocir_image_tag=<BUILD_ID>` (prod state: `terraform.tfstate`).
4. Polls `GET /api/build-info` until HTTP 200 and matching `buildId`.

If the instance was replaced and **`oci.cloudstore893.com` times out**:

```bash
./scripts/oci/reattach-reserved-ip.sh
export CLOUD_STORE_OCID="$(cd terraform && terraform output -raw container_instance_ocid)"
```

### Pre-production (`dev.oci.cloudstore893.com`)

```bash
./scripts/oci/redeploy-app-code-dev.sh "what you tested on dev"
# non-interactive:
# AUTO_YES=1 ./scripts/oci/redeploy-app-code-dev.sh "what you tested"
```

Same flow as prod, but uses dev Terraform state (`terraform.dev.tfstate`), OCIR repo `cloud-store-dev`, and hostname `dev.oci.cloudstore893.com`.

After a container replace, update shell env if prompted:

```bash
export CLOUD_STORE_DEV_OCID="$(CLOUD_STORE_ENV=dev ./scripts/oci/lib/terraform-env.sh 2>/dev/null; \
  cd terraform && terraform output -state=terraform.dev.tfstate -raw container_instance_ocid)"
```

Or from deploy / apply output directly.

If `dev.oci.cloudstore893.com` still serves an old build after deploy, sync DNS manually:

```bash
CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh
dig A dev.oci.cloudstore893.com +short @8.8.8.8   # should match terraform load_balancer_public_ip
```

### Verify (either environment)

```bash
# Prod (default):
APP=$(./scripts/oci/confirm-public-url.sh)

# Dev:
APP=$(CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh)

curl -s "$APP/api/build-info" | jq .

curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "$APP/api/cashier/unlock" \
  -H 'Content-Type: application/json' \
  -d '{"pin":"8930"}'
```

| Result | Meaning |
|--------|---------|
| **200** on unlock | New image is live (PIN allowed on server) |
| **403** on unlock | Image is live; **Model B** on (`CASHIER_SUPERVISOR_APPROVAL=true`) — PIN blocked; use IdP sign-in |
| **404** on unlock | Stale image **or** double-slash URL — redeploy again; see below |
| HTTP 200 but old `buildId` | Wrong LB/DNS target (common on dev after replace) — run `dev-dns-a-record.sh` or flush local DNS |

`confirm-public-url.sh` prints a base URL **without** a trailing slash. Always use:

```bash
APP=$(./scripts/oci/confirm-public-url.sh)
curl -s "$APP/api/build-info"
```

If `$APP` ends with `/`, `"$APP/api/..."` becomes `//api/...` and Express returns **404** (`Cannot GET //api/build-info`).

Live URLs:

- Prod POS: `https://oci.cloudstore893.com/`
- Prod admin: `https://oci.cloudstore893.com/admin/`
- Dev: `https://dev.oci.cloudstore893.com/`

Optional read-only API smoke:

```bash
BASE_URL="$APP" SKIP_DESTRUCTIVE=yes ./scripts/test-api-curl.sh
```

### Promote dev → prod

1. Deploy and smoke-test on dev (same git SHA you intend to ship).
2. Run any new DDL on dev ADB first.
3. `./scripts/oci/redeploy-app-code.sh "same label as dev deploy"`.
4. Apply the same DDL on prod ADB if needed.
5. Rebuild tablet APK only if the server API or baked-in prod URL changed.

See [versioning.md](versioning.md) and [oci-dev-environment.md](oci-dev-environment.md).

### Prune stale OCIR images

Repeated `docker push` leaves untagged manifests in the `cloud-store` repo. Dry-run first:

```bash
./scripts/oci/prune-ocir-images.sh
./scripts/oci/prune-ocir-images.sh --apply
```

Keeps `latest`, `cert-renew`, the Terraform `ocir_image_tag`, and the three most recent deploy tags (override with `--keep-recent N` or `--keep <tag>`).

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

**Pre-production (dev stack):** separate compartment/ADB at `dev.oci.cloudstore893.com` — [oci-dev-environment.md](oci-dev-environment.md).

End-to-end: compartment, OCIR, image push, VCN, ADB, container instance, DB seed.

---

## 7. Alternate paths (less common)

| Script | When |
|--------|------|
| `./scripts/oci/deploy-dev.sh` | Greenfield **dev** stack (`dev.oci.cloudstore893.com`) |
| `./scripts/oci/redeploy-app-code-dev.sh "label"` | App code to **dev** (preferred) |
| `./scripts/oci/redeploy-app-code.sh "label"` | App code to **prod** (preferred) |
| `./scripts/oci/restart-container-instance.sh` | Re-run **same cached image** (crash recovery only — does **not** deploy new code) |
| `./scripts/oci/deploy-app-oci.sh <tag>` | Same as redeploy with explicit tag (legacy alias; use redeploy script instead) |
| `./scripts/oci/dev-dns-a-record.sh` | Point `dev.oci.cloudstore893.com` A record at dev LB IP |
| `./scripts/oci/confirm-public-url.sh` | Resolve live URL (`CLOUD_STORE_ENV=dev` for dev) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `POST /api/cashier/unlock` → **404** | Old container image | `redeploy-app-code.sh` / `redeploy-app-code-dev.sh` |
| HTTP 200 but **old `buildId`** on dev hostname | Stale DNS A record (LB IP changed) | `CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh` |
| `invalid_redirect_uri` after deploy | IdP missing hostname callback | `idp-update-redirect-uris.sh` (or `-dev.sh`) |
| URL / IP changed after apply | Instance replace | Prod: `reattach-reserved-ip.sh`; dev: DNS script above |
| Shift close / till APIs → **500** | Schema not on ADB | Run DDL on dev first, then prod |
| `build-info` → `unknown` locally | No `BUILD_ID` at dev start | Normal for `npm run dev:up`; redeploy sets it on OCI |
| Terraform **Invalid flags before subcommand** | Old wrapper calling global `-state` | Update repo; use `scripts/oci/lib/terraform-env.sh` helpers |

---

## Journey log

| Date | Notes |
|------|-------|
| 2026-06-20 | App deploy: unique OCIR tag + terraform apply; dev/prod split; DNS sync after dev replace. |
| 2026-06-11 | Consolidated deploy guide (code, env, DB, IdP, tablet, decision table). |
