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
- Node.js 20+
- Docker via Colima: `brew install colima docker` then `colima start`
- OCI CLI: `brew install oci-cli` then `oci setup config`
- Terraform: `brew install terraform`

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

The script handles everything in order:
1. Creates the OCIR repository
2. Builds the linux/arm64 Docker image
3. Logs in and pushes it to OCIR
4. Provisions the VCN, Autonomous Database, and Container Instance via Terraform
5. Prints the app URL and all relevant OCIDs

### 3. Add ORDS tables (first deploy only)

After deploy, the ADB needs the PRODUCTS and CART_ITEMS tables created.
Run the SQL from `scripts/seed.sql` in the OCI Database Actions SQL Worksheet.

Access Database Actions:
```
OCI Console → Oracle Database → Autonomous Database → adb-cloud-store-893 → Database Actions
```

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
    ├── deploy.sh          # end-to-end terraform + docker build/push
    └── container.sh       # start / stop / status for the container instance
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

- [ ] Add `scripts/seed.sql` for PRODUCTS and CART_ITEMS table creation
- [ ] Connect OCI Load Balancer in front of the container instance
- [ ] Add CI/CD pipeline (GitHub Actions → OCIR → Terraform apply)
- [ ] Add order persistence (ORDERS table in ADB)
