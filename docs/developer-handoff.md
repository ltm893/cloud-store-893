# Developer handoff checklist

Onboard a second developer with **git clone + a secrets tarball** (local env and Terraform state are gitignored). Updated for dev IdP automation (`scripts/oci/idp/`), destroy/rebuild, and tablet builds.

Related: [oci-dev-environment.md](oci-dev-environment.md), [testing.md](testing.md), [scripts/oci/idp/README.md](../scripts/oci/idp/README.md), [idp-setup.md](idp-setup.md) (prod Console), [CONTENTS.md](../CONTENTS.md).

---

## Access model (pick one)

| Level | IAM | Can do |
|-------|-----|--------|
| **A — App dev (local)** | None | `git clone`, `npm run dev:up`, tablet → Mac LAN |
| **B — Dev deployer** | `cloud-store-dev` compartment | `deploy-dev.sh`, `redeploy-app-code-dev.sh`, IdP bootstrap |
| **C — Full ops** | `cloud-store` + `cloud-store-dev` + DNS | Prod + dev deploy, destroy, certs |

For **full ops**, add the user to **Administrators** (Default domain) or an equivalent ops group. For **dev only**, use the policy below.

### Dev-only IAM policy

```text
Allow group cloud-store-developers to manage all-resources in compartment cloud-store-dev
Allow group cloud-store-developers to manage identity-domains in compartment cloud-store-dev
Allow group cloud-store-developers to read dns-zones in compartment cloud-store
Allow group cloud-store-developers to manage dns-records in compartment cloud-store
```

(`identity-domains` is required for `./scripts/oci/idp/bootstrap-dev.sh`.)

---

## Part 1 — Tenancy admin (you)

### 1. OCI user

1. **Identity → Users → Create user** (their email).
2. Add to **Administrators** (full ops) or **cloud-store-developers** (dev only).

### 2. Their credentials (each person — never shared)

| Item | Where |
|------|--------|
| API key + `~/.oci/oci_api_key.pem` | Profile → API keys — they create |
| Auth token | Profile → Auth Tokens — for `docker login iad.ocir.io` |
| Console login | Their user — not your password |

### 3. Repo access

```bash
git clone https://github.com/ltm893/cloud-store-893.git
cd cloud-store-893
git checkout dev
```

### 4. Build handoff tarball (your Mac)

Secrets + Terraform state — **not** in git.

```bash
cd ~/Dev/projects/cloud-store-893

TARFILE="cloud-store-893-handoff-$(date +%Y%m%d).tar.gz"

CANDIDATES=(
  .env
  .env.dev
  terraform/terraform.tfvars
  terraform/terraform.dev.tfvars
  terraform/container_env.auto.tfvars
  terraform/container_env.prod.tfvars
  terraform/container_env.dev.tfvars
  terraform/lb_tls.auto.tfvars
  terraform/terraform.tfstate
  terraform/terraform.dev.tfstate
)

FILES=()
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] && FILES+=("$f")
done

tar -czf "$TARFILE" "${FILES[@]}"

ls -lh "$TARFILE"
printf 'Included:\n'; printf '  %s\n' "${FILES[@]}"
```

**Send via AirDrop or encrypted 1:1** — contains pins, IdP client secrets, ADB passwords.

**Before sending:** either redact and tell them to replace `user_ocid` + `fingerprint` in both tfvars, or leave yours in place and they **must** swap to their API key before any `oci` / `terraform` command.

**Never include:** `~/.oci/oci_api_key.pem`, `~/.oci/config` (they run `oci setup config`).

List archive contents without extracting:

```bash
tar -tzf "$TARFILE"
```

### 5. Optional shell exports (message separately)

```bash
export CLOUD_STORE_OCID="<prod container OCID>"
export CLOUD_STORE_DEV_OCID="<dev container OCID>"
export CLOUD_STORE_RESERVED_PUBLIC_IP_OCID="<if prod uses reserved IP>"
```

They can also read OCIDs from Terraform state after extract.

---

## Part 2 — New developer (after clone + tarball)

### 1. Extract tarball

```bash
cd ~/Dev/projects/cloud-store-893
tar -xzf ~/Downloads/cloud-store-893-handoff-YYYYMMDD.tar.gz
```

### 2. Fix OCI identity in tfvars

Edit **only** these in `terraform/terraform.tfvars` and `terraform/terraform.dev.tfvars`:

- `user_ocid` → their user OCID
- `fingerprint` → their API key fingerprint

Leave `tenancy_ocid`, `adb_admin_password`, `object_storage_namespace`, pins, and IdP secrets unchanged unless intentionally rotating.

### 3. OCI CLI

```bash
brew install oci-cli
oci setup config
# region: us-ashburn-1, key file: ~/.oci/oci_api_key.pem

oci iam region list --query 'data[0].name' --raw-output   # sanity check
```

### 4. Toolchain

```bash
brew install colima docker terraform jq node
brew install --cask temurin@21   # Android / SQLcl
colima start
docker info
```

### 5. Local app (no OCI deploy)

```bash
cp .env.example .env   # if .env not in tarball
npm install
npm run dev:up
# → http://localhost:3000
```

### 6. Verify handoff files

```bash
ls -la .env .env.dev \
  terraform/terraform.tfvars terraform/terraform.dev.tfvars \
  terraform/container_env.dev.tfvars \
  terraform/terraform.tfstate terraform/terraform.dev.tfstate
```

---

## Part 3 — Dev OCI (read-only first)

```bash
CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh
curl -sk "https://dev.oci.cloudstore893.com/api/build-info" | jq .
curl -sk "https://dev.oci.cloudstore893.com/oauth/login" -I | grep -i location
# → dev issuer (e.g. idcs-e1486cc4...), NOT prod cloud-store-apps
```

**IdP domain:** Console → compartment **`cloud-store-dev`** → Domains → `cloud-store-app-1`  
(Not `cloud-store` / `cloud-store-apps` — that is prod.)

---

## Part 4 — Dev deploy workflow

| Task | Command |
|------|---------|
| App code to dev | `./scripts/oci/redeploy-app-code-dev.sh "what changed"` |
| IdP env → container | `./scripts/oci/sync-container-env-to-terraform-dev.sh` → `./scripts/oci/terraform-apply-container-dev.sh --yes` |
| DNS fix | `CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh` |
| List dev resources | `./scripts/oci/list-resources.sh --dev` |
| IdP greenfield | `./scripts/oci/idp/bootstrap-dev.sh --apply` |
| IdP after destroy | `./scripts/oci/idp/bootstrap-dev.sh --resume --apply` |

### Tablet → dev cloud

```bash
cd android-pos
API_BASE_URL=https://dev.oci.cloudstore893.com/ ./RebuildReinstall.sh
```

Default `./RebuildReinstall.sh` alone points at **prod** (`oci.cloudstore893.com`).

### Dev sign-in

- Web: `https://dev.oci.cloudstore893.com/oauth/login`
- User: email in `.env.dev` (`IDP_DEV_USER_EMAIL` or bootstrap output)
- Password: from bootstrap printout, or Oracle password reset flow

---

## Part 5 — Destroy / rebuild (dev only — coordinate first)

Identity Domains are **not** Terraform-managed — `cloud-store-app-1` survives workload destroy.

```bash
./scripts/oci/terraform-destroy-workloads-dev.sh --yes
./scripts/oci/deploy-dev.sh
CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh
./scripts/dev/sync-env-dev.sh
./scripts/oci/idp/bootstrap-dev.sh --resume --apply
```

---

## Part 6 — Prod (full ops only)

| Task | Command |
|------|---------|
| Deploy app | `./scripts/oci/redeploy-app-code.sh "label"` |
| What is live | `curl -s https://oci.cloudstore893.com/api/build-info \| jq .gitSha` |
| Destroy workloads | `./scripts/oci/terraform-destroy-workloads.sh --yes` |
| IdP | Manual — [idp-setup.md](idp-setup.md) (`cloud-store-apps`) |

**Rule:** DDL on **dev ADB first**, then prod. Same git SHA / deploy label when promoting.

---

## Part 7 — Cursor prompts (paste in order)

1. *"I extracted `cloud-store-893-handoff-*.tar.gz` into my clone. Walk me through what each handoff file is for and what I must not commit."*

2. *"Help me update `terraform/terraform.tfvars` and `terraform/terraform.dev.tfvars` with my `user_ocid` and `fingerprint` only."*

3. *"Verify my OCI CLI and Docker setup for cloud-store-893 (colima, oci, terraform, jq, node, JDK 21)."*

4. *"Run read-only checks: dev `build-info`, OAuth Location header, and `list-resources.sh --dev`."*

5. *"I need to deploy a small server change to dev — walk me through `redeploy-app-code-dev.sh` and verify."*

6. *(Tablet)* *"Build and install the Android POS APK against dev: `API_BASE_URL=https://dev.oci.cloudstore893.com/`"*

---

## Quick reference card

```text
Repo:     github.com/ltm893/cloud-store-893  (branch: dev)
Dev URL:  https://dev.oci.cloudstore893.com/
Prod URL: https://oci.cloudstore893.com/
Dev IdP:  cloud-store-app-1  (compartment cloud-store-dev)
Prod IdP: cloud-store-apps   (compartment cloud-store)

Handoff:  cloud-store-893-handoff-YYYYMMDD.tar.gz → extract into clone root
Keys:     own API key + auth token (not in tarball)
Docs:     docs/oci-dev-environment.md, scripts/oci/idp/README.md, CONTENTS.md
```
