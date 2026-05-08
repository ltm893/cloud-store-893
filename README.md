# Cloud Store 893

A containerized Node.js shopping cart deployed on Oracle Cloud Infrastructure (OCI).
Built as a hands-on learning project for the OCI Foundations 2025 certification.

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
> `OCI Console → Autonomous Database → adb-cloud-store-893 → Database Actions → SQL`

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
5. Enter a description — e.g. `cloud-store-893 docker login`
6. Click **Generate Token**
7. **Copy the token immediately** — OCI only shows it once

When `deploy.sh` prompts for a password during `docker login`, paste the token.
The username format is: `<object_storage_namespace>/<your_email>`
(the script fills this in automatically from your OCI CLI config).

---

## Tear down everything

```bash
cd terraform
terraform destroy
```

Removes the container instance, ADB, networking, OCIR repo, and compartment.

---

## Local development

```bash
# Copy and fill in your local ADB ORDS URL
cp .env.example .env

npm install
node server.js
# → http://localhost:3000
```

## Native Samsung tablet app (Kotlin)

A native Android POS client is included in `android-pos/` using Kotlin + Jetpack Compose.

Quick start:

1. Start backend from project root: `node server.js`
2. Open `android-pos` in Android Studio
3. Run on emulator/tablet

For physical Samsung tablets, update `API_BASE_URL` in
`android-pos/app/build.gradle.kts` from `10.0.2.2` to your computer's LAN IP.

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
└── Compartment: cloud-store-893
    ├── Container Registry
    │   └── Repository: cloud-store-893 (Public)
    │       └── Image: latest (linux/arm64)
    ├── Networking
    │   └── VCN: vcn-cloud-store-893 (10.0.0.0/24)
    │       ├── Subnet: subnet-cloud-store-893 (public)
    │       ├── Internet Gateway: ig-cloud-store-893
    │       ├── Route Table: 0.0.0.0/0 → ig-cloud-store-893
    │       └── Security List:
    │           ├── Ingress: TCP 22 (SSH)
    │           ├── Ingress: TCP 3000 (App)
    │           └── Egress: All traffic
    ├── Autonomous Database: adb-cloud-store-893 (ATP, Always Free)
    │   └── ORDS API: /ords/admin/products/ and /ords/admin/cart_items/
    └── Container Instance: container-instance-cloud-store-893
        └── Shape: CI.Standard.A1.Flex (Ampere ARM, Always Free)
            └── Container: cloud-store-893-container-1
                └── Image: iad.ocir.io/<namespace>/cloud-store-893:latest
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
    ├── install-sqlcl.sh   # download and install SQLcl correctly on macOS
    ├── container.sh       # start / stop / status for the container instance
    ├── list-resources.sh  # list all OCI resources in the compartment
    └── seed.sql           # creates tables, enables ORDS, inserts sample products
```

---

## OCI Concepts Covered

| Concept | Implementation |
|---|---|
| Compartment | All resources isolated under `cloud-store-893` |
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

## Next Steps

- [ ] Connect OCI Load Balancer in front of the container instance
- [ ] Add CI/CD pipeline (GitHub Actions → OCIR → Terraform apply)
- [ ] Add order persistence (ORDERS table in ADB)
