# Cloud Store 893

A containerized Node.js shopping cart deployed on Oracle Cloud Infrastructure (OCI).


---

## Project Overview

A simple Express.js shopping cart with product listing, cart management, and an
Autonomous Database (ATP) backend via ORDS. The app is fully containerized with Docker
and all OCI infrastructure is managed by Terraform.

**Stack:**
- Node.js + Express (backend)
- Vanilla HTML/CSS/JS (frontend)
- Docker / Colima (containerization)
- Terraform (infrastructure as code)
- OCI Container Registry (image storage)
- OCI Container Instances — CI.Standard.A1.Flex (Always Free, ARM64)
- OCI Autonomous Database ATP (Always Free, ORDS API)
- OCI VCN / Subnet / Internet Gateway / Security List (networking)

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
> Run `scripts/seed.sql` manually via OCI Database Actions:
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

Typical flow after a `terraform apply` that may have changed the ADB
hostname:

```bash
npm run sync-env
npm run dev:up
```

## Native Samsung tablet app (Kotlin)

A native Android POS client lives in `android-pos/` (Kotlin + Jetpack
Compose). Theming uses the **Lister palette** via `CloudStorePosTheme` in
`android-pos/app/src/main/java/com/cloudstore/pos/ui/theme/`. See
`android-pos/README.md` for module-specific notes.

Quick start:

1. Backend running on the Mac: `npm run dev:up`
2. Tablet on the same Wi-Fi as the Mac
3. Install a debug build (USB debugging, device authorized):

   ```bash
   cd android-pos
   ./gradlew :app:assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

   Or `./gradlew :app:installDebug` if a single default device is connected.

`API_BASE_URL` is resolved at **Gradle configuration** time (not runtime):
`ipconfig getifaddr en0` with fallback `en1`, then `BuildConfig.API_BASE_URL`.
The chosen URL is printed in the build log, e.g.
`[cloud-store-893] debug API_BASE_URL = http://10.0.0.122:3000/`.

Overrides:

```bash
LAN_IP=192.168.4.7 ./gradlew :app:installDebug               # custom dev IP
RELEASE_API_BASE_URL=https://prod.example.com/ \
  ./gradlew :app:assembleRelease                            # release URL only
```

Release APKs need a **`signingConfig`** in `android-pos/app/build.gradle.kts`
before `adb install` will accept them; for day-to-day dev on your own tablet,
**debug** is enough.

POS UI (high level):

- **Band 1:** Title **“Cloud Store 893 POS”** centered; **Show status** /
  **Hide status** reveals connection text, offline queue (**Sync queued**),
  and **Lock**.
- **Band 2:** Left — scan field, **Scan** / **Add**, **Current Sale** list.
  Right — number pad in a card using **half** the column height (top-aligned).
- **Band 3:** Left — sale totals and **Pay**. After **Pay**, **Payment** (compact
  picker) and **Complete Sale** appear in the **right** column under the pad.
- Cashier PIN (`BuildConfig.CASHIER_PIN`, default `8930`); read-only barcode
  field (number pad + scanner); **Scan** uses CameraX + ML Kit.
- Numeric input ≤ 6 digits → `POST /api/cart {productId}`; longer values →
  `POST /api/cart/barcode {barcode}`.
- Offline checkout queue; flush from the status drawer (**Sync queued**).
- Root screen uses **`navigationBarsPadding()`** so the pay controls clear
  the gesture bar when **edge-to-edge** is enabled in `MainActivity`.

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
                    ENV: PORT=3000, ORDS_BASE_URL=<from terraform>
```

---

## Project Structure

```
cloud-store-893/
├── server.js              # Express app — products + cart API routes via ORDS
├── package.json
├── Dockerfile             # node:20-alpine, linux/arm64, PORT=3000
├── .dockerignore
├── .env.example           # template for local dev ORDS URL
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

- [ ] Connect OCI Load Balancer in front of the container instance
- [ ] Add CI/CD pipeline (GitHub Actions → OCIR → Terraform apply)
- [ ] Add order persistence (ORDERS table in ADB)
- [ ] Tighten `.gitignore` so Android `build/`, `.gradle/`, and `.idea/`
      stop tracking
