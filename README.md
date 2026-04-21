# Cloud Store 893

A containerized Node.js shopping cart application deployed on Oracle Cloud Infrastructure (OCI). Built as a hands-on learning project for the OCI Foundations 2025 certification.

---

## Project Overview

A simple Express.js shopping cart with a product listing, cart management, and in-memory order state. The app is fully containerized with Docker and deployed to OCI Container Instances backed by OCI Container Registry.

**Stack:**
- Node.js + Express (backend)
- Vanilla HTML/CSS/JS (frontend)
- Docker (containerization)
- OCI Container Registry (image storage)
- OCI Container Instances (deployment)

---

## Local Development

### Prerequisites
- Node.js 20+
- Docker (via Homebrew + Colima on Mac)
- Colima (Mac Docker runtime)
- OCI CLI (`brew install oci-cli`)

### Install dependencies
```bash
npm install
```

### Run locally
```bash
node server.js
```

Open http://localhost:3000

### Start Docker runtime (Mac)
```bash
colima start
```

> Add to ~/.zshrc to fix Docker socket path:
> ```bash
> export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
> ```

---

## Docker

### Build image (ARM64 for OCI Ampere)
```bash
docker buildx build --platform linux/arm64 -t cloud-store-893 .
```

### Run container locally
```bash
docker run -p 3000:3000 cloud-store-893
```

### View running containers
```bash
docker ps
```

### Stop all containers
```bash
docker stop $(docker ps -q)
```

---

## OCI Deployment

### OCI Account Details
| Property | Value |
|---|---|
| Home Region | US East (Ashburn) — IAD |
| Compartment | cloud-store-893 |

> Find your Object Storage Namespace in OCI Console → Governance & Administration → Tenancy Details

### Image Path Format
```
iad.ocir.io/<object-storage-namespace>/cloud-store-893:latest
```

---

## Deployment Steps

### 1. Authenticate with OCI Container Registry
```bash
docker login iad.ocir.io -u <object-storage-namespace>/<oracle-username>
```
Password: OCI Auth Token (generated from Profile → Auth Tokens in OCI Console)

### 2. Tag the image
```bash
docker tag cloud-store-893 iad.ocir.io/<object-storage-namespace>/cloud-store-893:latest
```

### 3. Push to OCI Container Registry
```bash
docker push iad.ocir.io/<object-storage-namespace>/cloud-store-893:latest
```

### 4. Deploy to OCI Container Instances
Done via OCI Console — Developer Services → Container Instances → Create container instance.

---

## Managing the Container Instance

Use the included shell script to start, stop, and check the status of the OCI container instance from the command line.

### Setup

Make the script executable (first time only):
```bash
chmod +x scripts/container.sh
```

The script auto-discovers your container instance OCID from OCI using the CLI. To skip the lookup on every run, save it to `~/.zshrc`:
```bash
export CLOUD_STORE_OCID="<your-container-instance-ocid>"
```

### Usage

```bash
# Start the container instance
./scripts/container.sh start

# Stop the container instance
./scripts/container.sh stop

# Check current status
./scripts/container.sh status
```

### How the script works

1. Checks OCI CLI is installed and available
2. If `CLOUD_STORE_OCID` is set in the environment, uses it directly
3. If not, looks up the `cloud-store-893` compartment OCID via OCI CLI
4. Then finds the container instance named `container-instance-cloud-store-893` within it
5. Fails with a clear error message if either lookup fails
6. On first successful lookup, prints the OCID and suggests saving it to `~/.zshrc`

### Error handling

| Error | Cause | Fix |
|---|---|---|
| `OCI CLI not found` | oci-cli not installed | `brew install oci-cli` |
| `Could not find compartment` | OCI CLI not configured or wrong tenancy | Run `oci setup config` |
| `Could not find container instance` | Instance was deleted or renamed | Check OCI Console → Container Instances |

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
    └── Container Instance: container-instance-cloud-store-893
        └── Shape: CI.Standard.A1.Flex (Ampere ARM, Always Free)
            └── Container: cloud-store-893-container-1
                └── Image: iad.ocir.io/<namespace>/cloud-store-893:latest
                    Port: 3000
                    ENV: PORT=3000
```

---

## OCI Console Navigation Reference

| Task | Path |
|---|---|
| Container Registry | Developer Services → Container Registry |
| Container Instances | Developer Services → Container Instances |
| VCN / Networking | Networking → Virtual Cloud Networks |
| Security Lists | VCN → subnet → Security tab |
| Internet Gateway | VCN → Gateways tab |
| Route Tables | VCN → Routing tab |
| Tenancy Details | Governance & Administration → Tenancy Details |
| Auth Tokens | Profile icon → My Profile → Auth tokens |
| Compartments | Governance & Administration → Compartments |

---

## OCI Concepts Covered

| Concept | What We Did |
|---|---|
| Compartment | Isolated all project resources under cloud-store-893 |
| Container Registry (OCIR) | Pushed Docker image to OCI-managed registry |
| Container Instances | Deployed container without managing VMs or Kubernetes |
| VCN | Created private virtual network for the instance |
| Subnet | Public subnet within the VCN |
| Internet Gateway | Enabled outbound internet access to pull image from OCIR |
| Route Table | Directed 0.0.0.0/0 traffic to the Internet Gateway |
| Security List | Opened TCP port 3000 for inbound app traffic |
| Availability Domain | Deployed to US-ASHBURN-AD-1 |
| Always Free Shape | Used CI.Standard.A1.Flex (Ampere ARM) — no cost |

---

## Lessons Learned

- **Architecture matters** — built image must match deployment target. Mac M-series builds ARM64 by default which matches OCI Ampere (A1) but requires explicit `--platform linux/arm64` flag with buildx.
- **Internet Gateway is required** for Container Instances to pull images from OCIR — even within OCI. Without it the container fails with "inadequate network configuration."
- **Object Storage Namespace** (not tenancy name) is used for OCIR authentication — found in Tenancy Details page.
- **E4 shapes are not Always Free** — use A1.Flex (Ampere) for free tier container deployments.
- **Colima** replaces Docker Desktop on Mac. Requires `DOCKER_HOST` env var set to `unix://${HOME}/.colima/default/docker.sock`.
- **docker-buildx** must be installed separately via Homebrew and configured in `~/.docker/config.json` when not using Docker Desktop.

---

## Project Structure

```
cloud-store-893/
├── server.js          # Express app, API routes, in-memory cart
├── package.json
├── Dockerfile         # node:20-alpine, EXPOSE 3000
├── .dockerignore      # excludes node_modules
├── scripts/
│   └── container.sh   # OCI container instance start/stop/status
└── public/
    └── index.html     # Product listing + cart UI
```

---

## Next Steps

- [ ] Connect OCI Autonomous Database (replace in-memory cart)
- [ ] Add order persistence
- [ ] Set up OCI Load Balancer
- [ ] Add CI/CD pipeline (GitHub Actions → OCIR → Container Instance)
- [ ] Clean up duplicate VCN from failed deployments
