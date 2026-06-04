# Cloud Store 893

A containerized Node.js shopping cart deployed on Oracle Cloud Infrastructure (OCI).


---

## Project Overview

A simple Express.js shopping cart with product listing, cart management, and an
Autonomous Database (ATP) backend via ORDS. The app is fully containerized with Docker
and all OCI infrastructure is managed by Terraform.

**Stack:**
- Node.js + Express (backend)
- Vanilla HTML/CSS/JS (web POS + admin UI)
- Kotlin + Jetpack Compose (Samsung tablet POS in `android-pos/`)
- Docker / Colima (containerization)
- Terraform (infrastructure as code)
- OCI Container Registry (image storage)
- OCI Container Instances — CI.Standard.A1.Flex (Always Free, ARM64)
- OCI Autonomous Database ATP (Always Free, ORDS API)
- OCI VCN / Subnet / Internet Gateway / Security List (networking)

### Authentication (summary)

Two **separate** app sessions — cashier (POS) and admin — each with its own cookie and optional IdP sign-in.

| Surface | Session | Default sign-in | Optional |
|---------|---------|-----------------|----------|
| Web POS `/`, tablet | `cashier_session` | PIN → `POST /api/cashier/unlock` | OIDC (`/oauth/login`) |
| Admin `/admin/` | `admin_session` | PIN on `/admin/login.html` | OIDC (`/oauth/admin/login`) |

**Model B (supervisor approval)** — on branch `feature/cashier-supervisor-approval`: when `CASHIER_SUPERVISOR_APPROVAL=true`, cashier OIDC creates a **pending** login; a supervisor approves in admin before `cashier_session` is issued. Web POS, admin panel, and Android tablet support this flow. See [docs/cashier-supervisor-approval.md](docs/cashier-supervisor-approval.md).

- **Protected:** cart, checkout, customers, sales APIs; all `/api/admin/*`.
- **Public:** `GET /api/products` (catalog only).
- **Local dev:** PINs and IdP settings in **`.env`** (see `.env.example`).
- **OCI container:** PINs from **`terraform.tfvars`** (`cashier_pin`, `admin_pin`); IdP vars are **not** copied from `.env` automatically — add them via Terraform or the container console, then re-apply/restart.
- **IdP:** Optional Oracle Identity Domain confidential clients; redirect URIs must match `APP_PUBLIC_URL` / callback paths on the host you deploy. Details: [docs/idp-setup.md](docs/idp-setup.md), app reset: [docs/idp-level1-reset.md](docs/idp-level1-reset.md).

With IdP configured, `IDP_ALLOW_PIN=true` (default) keeps PIN login available alongside Oracle sign-in. With Model B enabled, PIN unlock is blocked (`403`) and IdP sign-in is required.

---

## Deploy from scratch

### Prerequisites
- Docker via Colima: `brew install colima docker` then `colima start`
- OCI CLI: `brew install oci-cli` then `oci setup config`
- Terraform: `brew install terraform`
- SQLcl (automated database seed): see **Installing SQLcl** below — use the provided script

### 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in tenancy_ocid, user_ocid, fingerprint,
# object_storage_namespace, and adb_admin_password
```

Full Terraform documentation (file layout, dependency graph, outputs, workload tear-down, state recovery): [terraform/README.md](terraform/README.md).

### 2. Run the deploy script

```bash
chmod +x scripts/deploy.sh   # first time only
./scripts/deploy.sh
```

The script handles everything end-to-end:
1. **Phase 1** — Creates the compartment and OCIR repository
2. Builds and pushes the linux/arm64 Docker image to OCIR
3. **Phase 2** — Provisions the VCN, Autonomous Database, and Container Instance via Terraform
4. **Phase 3** — Waits for ORDS to be ready, then seeds the database via SQLcl (creates tables, enables ORDS endpoints, inserts sample products)
5. Prints the app URL and all relevant OCIDs

> **Note:** You will be prompted for your OCI Auth Token during the `docker login` step.
> See **Creating an OCI Auth Token** below if you haven't done this yet.

> **SQLcl not installed?** The deploy will complete but skip the seed.
> Run `./scripts/reset-db.sh` after installing SQLcl, or run `scripts/seed.sql` manually via OCI Database Actions:
> `OCI Console → Autonomous Database → adb-cloud-store → Database Actions → SQL`

---

## Installing SQLcl

SQLcl is Oracle's command-line SQL client used by `deploy.sh` to seed the database.
`brew install sqlcl` no longer works — the formula was removed from Homebrew.
Use the provided install script instead, which handles everything correctly.

### Why Java 21 specifically?

SQLcl requires **Java 11–21**. Java 22+ introduced module system changes that break
SQLcl's classloader (symptoms: `ClassNotFoundException` even when the jar is present).
Java 21 is the current LTS release and the safest choice. You can have multiple JDKs
installed — `JAVA_HOME` controls which one SQLcl uses.

### Gotcha: zip extracts with root:wheel permissions

Oracle's zip sets jars as `-rw-r-----` (root-readable only). Since Java runs as your
user, it can't read the jars without a `chmod a+r` fix. The install script handles
this automatically.

### Install

```bash
chmod +x scripts/install-sqlcl.sh   # first time only
./scripts/install-sqlcl.sh
```

The script:
1. Installs Temurin 21 via Homebrew if Java 21 isn't present
2. Removes any existing `/opt/sqlcl`
3. Downloads `sqlcl-latest.zip` directly from Oracle
4. Extracts to `/opt/sqlcl` and fixes permissions (`chmod a+r`)
5. Adds `/opt/sqlcl/bin` and `JAVA_HOME=21` to `~/.zshrc`
6. Verifies with `sql -version`

After the script finishes:

```bash
source ~/.zshrc
sql -version
# → SQLcl: Release 26.x.x.x Production Build: ...
```

### Re-installing

To wipe and reinstall cleanly (e.g. after a failed install):

```bash
sudo rm -rf /opt/sqlcl
./scripts/install-sqlcl.sh
```

---

## Creating an OCI Auth Token

An Auth Token is a password OCI generates for you — it's used anywhere OCI needs
a password that isn't your console login, including `docker login` to OCIR.

1. Open the OCI Console and click your **Profile** icon (top-right)
2. Click **My Profile**
3. Scroll down to **Auth Tokens** in the left sidebar and click it
4. Click **Generate Token**
5. Enter a description — e.g. `cloud-store docker login`
6. Click **Generate Token**
7. **Copy the token immediately** — OCI only shows it once

When `deploy.sh` prompts for a password during `docker login`, paste the token.
The username format is: `<object_storage_namespace>/<your_email>`
(the script fills this in automatically from your OCI CLI config).

---

## Tear down workloads (compartment kept)

```bash
./scripts/terraform-destroy-workloads.sh
```

Removes Terraform-managed **workloads** in the `cloud-store` compartment (default
`project_name`; change in `terraform.tfvars` if needed). The **compartment is not
destroyed** (`lifecycle { prevent_destroy = true }` in `terraform/compartment.tf`).
Targets are derived from `terraform state list`, so you do not maintain a static
resource list in the script.

A plain `cd terraform && terraform destroy` **fails planning** because that run
includes destroying the compartment, which `prevent_destroy` blocks.

To remove the **compartment** too: delete it in the OCI console only; repo scripts
never remove the compartment from Terraform state.

---

## Local development

```bash
cp .env.example .env   # fill in ORDS_BASE_URL
npm install
npm run dev:up
```

`dev:up` runs `scripts/dev-up.sh`, which:

1. Verifies `.env` has an `ORDS_BASE_URL`
2. Compares it to `terraform output -raw ords_base_url` and warns on drift
3. Probes `${ORDS_BASE_URL}/metadata-catalog/` to detect ADB-stopped vs.
   ORDS-not-enabled vs. healthy
4. Prints the LAN URL the tablet should target
5. Execs `node --watch server.js` so file edits auto-reload

Available npm scripts:

| Script | Effect |
|---|---|
| `npm start` | `node server.js` (no watch) |
| `npm run dev` | `node --watch server.js` (auto-reload, no preflight) |
| `npm run dev:up` | preflight + `node --watch server.js` (recommended) |
| `npm run sync-env` | rewrites `.env`'s `ORDS_BASE_URL` from `terraform output` |
| `npm run lan-url` | prints `http://<your-mac-lan-ip>:3000/` |
| `npm run test:auth` | curl checks that POS/admin APIs require sessions (manual; server must be running) |
| `npm run test:api` | curl smoke tests for POS/admin APIs (manual; destructive phase — see script) |
| `npm run test:login-approval` | ORDS smoke test for Model B login-approval store (manual; live ADB) |
| `npm run test:supervisor-routes` | HTTP smoke test for supervisor approval routes (manual; server + env — see [docs/cashier-supervisor-approval.md](docs/cashier-supervisor-approval.md#testing-manual-today)) |
| `npm run test:cashier-approval-session` | Pending cookie + `/api/cashier/session` for Model B (manual; server needs `CASHIER_SUPERVISOR_APPROVAL=true`) |
| `npm run test:cashier-approval-poll` | Poll → supervisor approve → session cookie E2E (manual; server + supervisor env) |

`npm test` is not wired to these yet — they are opt-in. Planned CI / `npm test` aggregation: [docs/cashier-supervisor-approval.md](docs/cashier-supervisor-approval.md#later--wire-into-normal-workflow-todo).

Typical flow after a `terraform apply` that may have changed the ADB
hostname:

```bash
npm run sync-env
npm run dev:up
```

### Environment variables (`.env`)

Copy `.env.example` → `.env`. Never commit `.env`.

| Variable | Purpose |
|----------|---------|
| `ORDS_BASE_URL` | ADB ORDS admin base (from `npm run sync-env` or `terraform output`) |
| `PORT` | Node listen port (default `3000`) |
| `CASHIER_PIN` | Cashier unlock — `POST /api/cashier/unlock` (default `8930`) |
| `ADMIN_PIN` | Admin UI PIN (defaults to `CASHIER_PIN` if unset) |
| `APP_PUBLIC_URL` | Public base URL of the Node app (IdP redirects; use `terraform output app_url`) |
| `IDP_POS_*` / `IDP_ADMIN_*` | Optional OIDC issuer, client id/secret, redirect URI per app |
| `IDP_ALLOW_PIN` | When `true` (default), PIN remains available if IdP is configured |
| `CASHIER_SESSION_SECURE` | Set `true` when served over HTTPS (Secure cookie flag) |

**Where values apply**

| Setting | Local (`npm run dev`) | OCI container |
|---------|----------------------|---------------|
| `ORDS_BASE_URL` | `.env` | Terraform → container env |
| `CASHIER_PIN`, `ADMIN_PIN` | `.env` | `cashier_pin`, `admin_pin` in `terraform.tfvars` → `terraform apply` |
| `IDP_*`, `APP_PUBLIC_URL` | `.env` | Not deployed by default — add to container env or extend `terraform/container.tf` |

After changing only PINs on OCI: edit `terraform.tfvars`, then `cd terraform && terraform apply` (no image rebuild required).

### OCI env parity checklist

Local `.env` changes do **not** apply to the OCI container until you copy them there and restart. Use this after `terraform apply` (public IP may change) or when OAuth shows `invalid_redirect_uri` / `idpEnabled: false`.

1. **Current app URL** — `cd terraform && terraform output app_url` (e.g. `http://150.136.208.81:3000`).
2. **Set on the container** (Console → Container instance → container → Environment variables), matching `.env`:
   - `APP_PUBLIC_URL` = that URL (no trailing slash)
   - `IDP_POS_ISSUER`, `IDP_POS_CLIENT_ID`, `IDP_POS_CLIENT_SECRET`
   - `IDP_ADMIN_ISSUER`, `IDP_ADMIN_CLIENT_ID`, `IDP_ADMIN_CLIENT_SECRET`
   - Optional Model B: `CASHIER_SUPERVISOR_APPROVAL`, `CASHIER_APPROVAL_TTL_SEC`, group names, etc.
   - **Do not** set `IDP_POS_REDIRECT_URI` / `IDP_ADMIN_REDIRECT_URI` unless you need an override — omit them so redirects are built from `APP_PUBLIC_URL` (see [docs/idp-setup.md](docs/idp-setup.md#51-oauth-flow-at-code-level)).
3. **Oracle Identity** — on `cloud-store-pos` and `cloud-store-admin`, add redirect URLs for the **current** host (`/oauth/callback`, `/oauth/admin/callback`). Update Application URL if it still shows an old IP.
4. **Restart container** — `./scripts/restart-container-instance.sh` (waits for restart to succeed).
5. **Verify on OCI host** (not Mac localhost):
   ```bash
   APP=$(cd terraform && terraform output -raw app_url)
   curl -s "$APP/api/cashier/session"    # expect "idpEnabled": true when IdP is wired
   curl -sI "$APP/oauth/login" | grep -i '^location:'   # expect 302 to Oracle with redirect_uri matching APP
   ```
6. **Tablet** — rebuild only if `API_BASE_URL` changed: `RELEASE_API_BASE_URL=<app_url> ./RebuildReinstall.sh` in `android-pos/`.

### Admin UI

- **URL:** `/admin/` (e.g. `http://localhost:3000/admin/` or `terraform output app_url` + `/admin/`)
- **Sign-in:** `/admin/login.html` — PIN and/or “Sign in with Oracle” when IdP env is set
- **API:** `/api/admin/*` — CRUD on `products`, `customers`, `cart_items`, `sales`, `sale_items`; read-only `cart_view`
- **Implementation:** `lib/admin-auth.js`, `lib/admin-routes.js`, `lib/cashier-auth.js`, `lib/oidc-*.js`, `public/admin/`

### Web POS

- **URL:** `/` — product grid, cart, checkout; PIN gate (and optional IdP link) before cart/checkout APIs

---

## Update the OCI container (after code changes)

The tablet and browser talk to **whatever image is running** on the container instance. After changing `server.js` or admin UI, **push a new Docker image before** (or with) Terraform:

```bash
cd /Users/ltm893/Dev/projects/cloud-store-893   # repo root
IMAGE=$(cd terraform && terraform output -raw ocir_image_path)

docker buildx build --platform linux/arm64 -t "$IMAGE" .
docker push "$IMAGE"

cd terraform
terraform apply    # recreates container if needed; see terraform/README.md
```

Verify cashier login API (expect **200**, not **404**):

```bash
APP=$(cd terraform && terraform output -raw app_url)
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "$APP/api/cashier/unlock" \
  -H 'Content-Type: application/json' \
  -d '{"pin":"8930"}'
```

If `terraform apply` fails on **Always Free ADB** with a 403 about OCPU/storage updates, see [terraform/README.md](terraform/README.md) — `database.tf` uses `lifecycle { ignore_changes = … }` so only the container should change.

---

## Native Samsung tablet app (Kotlin)

A native Android POS client lives in `android-pos/` (Kotlin + Jetpack
Compose). Theming uses the **Lister palette** via `CloudStorePosTheme` in
`android-pos/app/src/main/java/com/cloudstore/pos/ui/theme/`. See
`android-pos/README.md` for module-specific notes.

Quick start (local backend on Mac):

1. `npm run dev:up` (with `.env` including `CASHIER_PIN`)
2. Tablet on the same Wi-Fi as the Mac
3. Build and install (set `LAN_IP` to your Mac’s Wi‑Fi address):

   ```bash
   cd android-pos
   LAN_IP=$(ipconfig getifaddr en0) ./gradlew :app:assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

Quick start (OCI backend — use **public IP** from `terraform output app_url`):

```bash
cd android-pos
# Use IP only — no http:// or :3000
LAN_IP=150.136.44.64 ./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

`API_BASE_URL` is baked in at **Gradle configure** time (`BuildConfig`). Check the log line:
`[cloud-store-893] debug API_BASE_URL = http://…/`

| Target | Build command |
|--------|----------------|
| Mac on LAN | `LAN_IP=$(ipconfig getifaddr en0) ./gradlew :app:assembleDebug` |
| OCI | `LAN_IP=<app-url-host> ./gradlew :app:assembleDebug` |
| Release | `RELEASE_API_BASE_URL=http://<host>:3000/ ./gradlew :app:assembleRelease` |

**Cashier PIN** is validated by the server (`CASHIER_PIN` in `.env` or container env), not in the APK. Changing the PIN does not require rebuilding the app.

Full tablet notes: [android-pos/README.md](android-pos/README.md).

POS UI (high level):

- **☰ Menu** — **Show/Hide status** (connection + offline queue), **Admin** (opens `/admin/` in browser), **Lock**
- **Login** — on-screen number pad + **Done** (calls `POST /api/cashier/unlock`)
- **Sale screen** — scan field, **Scan** / **Add**, numpad, cart, **Pay** → **Complete Sale**
- Numeric input ≤ 6 digits → `POST /api/cart {productId}`; longer → `POST /api/cart/barcode`
- Offline checkout queue — **Sync queued** in status panel; queue stores payment only (see [CONTENTS.md](CONTENTS.md))

---

## Manage the running container instance

```bash
chmod +x scripts/container.sh   # first time only

./scripts/container.sh start
./scripts/container.sh stop
./scripts/container.sh status
```

The script auto-discovers the container instance OCID from OCI, or reads
`CLOUD_STORE_OCID` from your environment (printed by deploy.sh).

---

## OCI Architecture

```
OCI Tenancy
└── Compartment: cloud-store
    ├── Container Registry
    │   └── Repository: cloud-store (Public)
    │       └── Image: latest (linux/arm64)
    ├── Networking
    │   └── VCN: vcn-cloud-store (10.0.0.0/24)
    │       ├── Subnet: subnet-cloud-store (public)
    │       ├── Internet Gateway: ig-cloud-store
    │       ├── Route Table: 0.0.0.0/0 → ig-cloud-store
    │       └── Security List:
    │           ├── Ingress: TCP 22 (SSH)
    │           ├── Ingress: TCP 3000 (App)
    │           └── Egress: All traffic
    ├── Autonomous Database: adb-cloud-store (ATP, Always Free)
    │   └── ORDS API: /ords/admin/products/ and /ords/admin/cart_items/
    └── Container Instance: container-instance-cloud-store
        └── Shape: CI.Standard.A1.Flex (Ampere ARM, Always Free)
            └── Container: cloud-store-container-1
                └── Image: iad.ocir.io/<namespace>/cloud-store:latest
                    Port: 3000
                    ENV: PORT, ORDS_BASE_URL, CASHIER_PIN, ADMIN_PIN (+ optional IDP_*)
```

---

## Project Structure

```
cloud-store-893/
├── server.js              # Express — POS API, admin API, cashier unlock
├── lib/                   # admin-auth, admin-routes, cashier-auth
├── public/
│   ├── index.html         # web POS
│   └── admin/             # admin CRUD UI
├── package.json
├── Dockerfile             # node:20-alpine, linux/arm64
├── .env.example           # ORDS, PINs, optional IdP (see Authentication)
├── CONTENTS.md            # session resume / handoff notes
├── android-pos/           # Kotlin + Compose tablet POS (see android-pos/README.md)
├── terraform/
│   ├── main.tf            # OCI provider
│   ├── variables.tf       # all inputs
│   ├── compartment.tf     # oci_identity_compartment
│   ├── network.tf         # VCN, IG, route table, security list, subnet
│   ├── registry.tf        # OCIR repository
│   ├── database.tf        # Autonomous Database (ATP, Always Free)
│   ├── container.tf       # Container Instance wired to ADB ORDS URL
│   ├── outputs.tf         # app URL, image path, ORDS URL, OCIDs
│   ├── terraform.tfvars.example
│   └── README.md
└── scripts/
    ├── deploy.sh          # end-to-end: terraform + docker build/push + DB seed
    ├── dev-up.sh          # local dev: ORDS preflight + node --watch server.js
    ├── sync-env.sh        # rewrite .env's ORDS_BASE_URL from terraform output
    ├── oci-costs.sh       # query OCI usage-api and print spend by service / range
    ├── install-sqlcl.sh   # download and install SQLcl correctly on macOS
    ├── container.sh       # start / stop / status for the container instance
    ├── list-resources.sh  # list all OCI resources in the compartment
    └── seed.sql           # creates tables, enables ORDS, inserts sample products
```

---

## OCI Concepts Covered

| Concept | Implementation |
|---|---|
| Compartment | All resources isolated under `cloud-store` (default `project_name`) |
| Terraform | All resources created and destroyed via IaC |
| Container Registry (OCIR) | Docker image storage for ARM64 image |
| Container Instances | Serverless container deployment (no VMs, no K8s) |
| Autonomous Database | ATP with ORDS REST API for products and cart |
| VCN | Private virtual network |
| Subnet | Public subnet with internet access |
| Internet Gateway | Required for container instance to pull images from OCIR |
| Route Table | 0.0.0.0/0 → Internet Gateway |
| Security List | TCP 22 + TCP 3000 ingress, all egress |
| Always Free | A1.Flex shape + ATP free tier — zero cost |

---

## Cost monitoring

```bash
./scripts/oci-costs.sh                  # month-to-date by service
./scripts/oci-costs.sh --prev-month     # previous full month
./scripts/oci-costs.sh --week --total   # last 7 days, single total
./scripts/oci-costs.sh --by-compartment
./scripts/oci-costs.sh --since 2026-01-01 --until 2026-05-01
./scripts/oci-costs.sh --help
```

Uses `oci usage-api` and prints a sorted table with a `TOTAL` row.
On Always Free tier this should report `$0.0000 USD`. Requires a policy
allowing your user/group to read usage-report in the tenancy.

---

## Next Steps

- [ ] HTTPS / Load Balancer in front of the container instance (required for production IdP)
- [ ] Wire optional `IDP_*` / `APP_PUBLIC_URL` through Terraform for OCI deploys
- [ ] CI/CD (GitHub Actions → OCIR → container refresh)
- [ ] Restrict ingress (`ingress_allowed_cidrs` in `terraform.tfvars`) when not on public IP
- [ ] Tablet: native OIDC or keep PIN-via-API; discard offline queue; snapshot cart on queue
- [ ] **Cash rounding (server/books)** — tablet UI rounds to $0.05 today; persist on checkout, reports, web — see [CONTENTS.md](CONTENTS.md#cash-rounding-todo)
- [ ] **Card terminal / payment pad** — no pad API today; Card is manual “paid” only — see [CONTENTS.md](CONTENTS.md#card-terminal--payment-pad-todo)
- [ ] Receipt / print after **Complete Sale**
