# HTTPS with OCI Load Balancer

Required path when HTTPS must terminate on **OCI** (not Cloudflare Tunnel).

**Current production setup (2026-06-07):** Let's Encrypt → **OCI Certificates** → LB listener by **certificate OCID**. DNS for `oci.cloudstore893.com` is delegated to **OCI DNS** (Route 53 NS records).

---

## Architecture

```text
Internet
   │
   │  HTTPS :443
   ▼
┌─────────────────────────────────────┐
│  OCI Flexible Load Balancer         │
│  Listener: https                  │
│  Cert: OCI Certificates OCID        │  ◄── auto-picks up new cert versions
└──────────────┬──────────────────────┘
               │  HTTP :3000 (VCN only)
               ▼
┌─────────────────────────────────────┐
│  Node container (Docker)            │
└─────────────────────────────────────┘
```

- No TLS cert in the Docker image.
- `cashier_session_secure` is set automatically when LB HTTPS is enabled.
- Keep `APP_PUBLIC_URL_FROM_REQUEST=true` (default) so OAuth uses `https://` via `X-Forwarded-Proto`.

---

## Certificate flow (Let's Encrypt + OCI Certificates)

```text
                    ┌─────────────────────────────────────────┐
                    │  Route 53 (cloudstore893.com)           │
                    │  oci.cloudstore893.com  NS  ────────────┼──┐
                    └─────────────────────────────────────────┘  │
                                                                 ▼
┌──────────────┐   DNS-01 TXT    ┌──────────────────────────────┐
│  Certbot     │ ──────────────► │  OCI DNS zone                │
│  dns-oci     │ ◄────────────── │  oci.cloudstore893.com       │
│  plugin      │   _acme-challenge                              │
└──────┬───────┘                 └──────────────────────────────┘
       │
       │  ACME (port 443 N/A — challenge is DNS only)
       ▼
┌──────────────┐
│ Let's Encrypt│  public CA, 90-day certs
└──────┬───────┘
       │  cert.pem / privkey.pem / chain.pem
       ▼
┌──────────────────────────────┐
│ OCI Certificates service     │  create-by-importing-config (first time)
│  name: oci-cloudstore893-com │  update-certificate-by-importing-config-details (renew)
└──────────────┬───────────────┘
               │  certificate OCID on listener
               ▼
┌──────────────────────────────┐
│ OCI Load Balancer :443       │  detects new cert version automatically
└──────────────────────────────┘

Future automation (not built yet):

  OCI Resource Scheduler ──► OCI Function ──► certbot renew + deploy hook ──► Certificates service
```

**Why OCI Certificates (not PEM on the LB directly)?**

- Named cert resource, OCID, expiry, version history in Console.
- LB listener references **OCID** — renewals update the same cert resource; no listener swap each time.
- Good POC story for “managed SSL certificate.”

---

## 1. DNS — delegate subdomain to OCI DNS

Parent zone `cloudstore893.com` can stay in **Route 53**. Delegate only **`oci.cloudstore893.com`** to OCI.

### 1a. Create zone in OCI

Console: **Networking → DNS management → Zones → Create zone**

- Zone name: `oci.cloudstore893.com`
- Type: Primary

CLI:

```bash
oci dns zone create \
  --compartment-id "$(oci iam compartment list --all --query \"data[?name=='cloud-store'].id | [0]\" --raw-output)" \
  --name "oci.cloudstore893.com" \
  --zone-type PRIMARY
```

Note the four **nameservers** (e.g. `ns1.p201.dns.oraclecloud.net`, …).

### 1b. Add A record in OCI (before cutover)

```bash
LB_IP="$(cd terraform && terraform output -raw load_balancer_public_ip)"

oci dns record zone update \
  --zone-name-or-id "oci.cloudstore893.com" \
  --items "[{\"domain\":\"oci.cloudstore893.com\",\"rtype\":\"A\",\"ttl\":300,\"rdata\":\"${LB_IP}\"}]"
```

### 1c. Delegate from Route 53

In hosted zone **`cloudstore893.com`**:

1. **Delete** the existing **`oci` A record** (if any).
2. **Create** record: name **`oci`**, type **NS**, values = all four OCI nameservers, TTL 300.

Verify:

```bash
dig NS oci.cloudstore893.com +short @8.8.8.8
dig A oci.cloudstore893.com +short @8.8.8.8
```

Pre-check script: `./scripts/oci/verify-certbot-dns-oci.sh`

---

## 2. Install certbot + OCI DNS plugin (Mac)

### 2a. Prerequisites

```bash
brew install certbot oci-cli
```

OCI CLI must work (`oci iam region list`). Your user needs IAM:

```text
Allow … to read dns-zones in compartment cloud-store
Allow … to manage dns-records in compartment cloud-store
```

### 2b. Install `certbot-dns-oci` plugin

Homebrew certbot uses its own Python — install the plugin **into that environment**:

```bash
git clone https://github.com/therealcmj/certbot-dns-oci.git /tmp/certbot-dns-oci

CERTBOT_SITE="$(/opt/homebrew/Cellar/certbot/*/libexec/bin/python3 -c 'import site; print(site.getsitepackages()[0])')"
/opt/homebrew/Cellar/certbot/*/libexec/bin/python3 -m pip install --target "$CERTBOT_SITE" /tmp/certbot-dns-oci

certbot plugins   # must list dns-oci
```

Certbot state lives under `certs/certbot/` (gitignored via `certs/`).

---

## 3. Obtain Let's Encrypt certificate (initial)

From repo root:

```bash
mkdir -p certs/certbot/{config,work,logs}

certbot certonly \
  --logs-dir certs/certbot/logs \
  --work-dir certs/certbot/work \
  --config-dir certs/certbot/config \
  --authenticator dns-oci \
  -d oci.cloudstore893.com \
  --agree-tos -m you@example.com \
  --non-interactive \
  --dns-oci-propagation-seconds 120
```

**Staging test first (optional):** add `--test-cert` for a fake cert (proves DNS path). Delete before production:

```bash
certbot delete --cert-name oci.cloudstore893.com \
  --config-dir certs/certbot/config \
  --work-dir certs/certbot/work \
  --logs-dir certs/certbot/logs \
  --non-interactive
```

Confirm production cert:

```bash
certbot certificates \
  --config-dir certs/certbot/config \
  --work-dir certs/certbot/work \
  --logs-dir certs/certbot/logs
```

Expect **`VALID`** and **no** `TEST_CERT`. PEMs:

```text
certs/certbot/config/live/oci.cloudstore893.com/cert.pem
certs/certbot/config/live/oci.cloudstore893.com/privkey.pem
certs/certbot/config/live/oci.cloudstore893.com/chain.pem
```

If certbot says **“Certificate not yet due for renewal”**, you already have a cert in that config dir — use `certbot delete` or `--force-renewal`.

---

## 4. Import into OCI Certificates

Console: **Identity & Security → Certificates → Import certificate**

CLI (**use inline PEM** — `file://` often fails with “incorrect format” on Mac):

```bash
CERT_DIR="certs/certbot/config/live/oci.cloudstore893.com"
COMP="$(oci iam compartment list --all --query \"data[?name=='cloud-store'].id | [0]\" --raw-output)"

CERT=$(cat "${CERT_DIR}/cert.pem")
CHAIN=$(cat "${CERT_DIR}/chain.pem")
KEY=$(cat "${CERT_DIR}/privkey.pem")

oci certs-mgmt certificate create-by-importing-config \
  --compartment-id "$COMP" \
  --name "oci-cloudstore893-com" \
  --certificate-pem "$CERT" \
  --private-key-pem "$KEY" \
  --cert-chain-pem "$CHAIN" \
  --wait-for-state ACTIVE \
  --query 'data.{id:id,name:name,lifecycleState:"lifecycle-state"}' \
  --output table
```

Save the **certificate OCID** from the output.

---

## 5. Point LB listener at certificate OCID

Replace `LB_OCID` and `CERT_OCID` with your values (see [CONTENTS.md](../CONTENTS.md) for current OCIDs):

```bash
LB_OCID="$(oci lb load-balancer list --compartment-id "$COMP" \
  --query 'data[?contains(\"display-name\", `lb-cloud`)].id | [0]' --raw-output)"
CERT_OCID="ocid1.certificate.oc1.iad...."

oci lb listener update \
  --load-balancer-id "$LB_OCID" \
  --listener-name https \
  --default-backend-set-name app-backend \
  --port 443 \
  --protocol HTTP \
  --ssl-certificate-ids "[\"$CERT_OCID\"]" \
  --wait-for-state SUCCEEDED
```

Add `--force` or answer `y` if the CLI warns about replacing ssl-configuration.

Verify **without** `-k`:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://oci.cloudstore893.com/api/build-info
echo | openssl s_client -connect oci.cloudstore893.com:443 -servername oci.cloudstore893.com 2>/dev/null \
  | openssl x509 -noout -issuer -dates
```

Issuer should be **Let's Encrypt**.

---

## 6. Renewal (manual on Mac)

Let's Encrypt certs expire in **90 days**; renew around **day 60**.

```bash
certbot renew \
  --config-dir certs/certbot/config \
  --work-dir certs/certbot/work \
  --logs-dir certs/certbot/logs \
  --authenticator dns-oci \
  --dns-oci-propagation-seconds 120
```

Deploy hook — update **same** certificate OCID in OCI Certificates (inline PEM):

```bash
CERT_OCID="ocid1.certificate.oc1.iad...."
CERT_DIR="certs/certbot/config/live/oci.cloudstore893.com"

oci certs-mgmt certificate update-certificate-by-importing-config-details \
  --certificate-id "$CERT_OCID" \
  --certificate-pem "$(cat "$CERT_DIR/cert.pem")" \
  --private-key-pem "$(cat "$CERT_DIR/privkey.pem")" \
  --cert-chain-pem "$(cat "$CERT_DIR/chain.pem")"
```

The LB listener **does not** need updating — it consumes the current version automatically.

---

## 7. Function-driven renewal (automated)

Code lives in `functions/cert-renew/` (Docker image + Terraform opt-in).

### Flow

```text
  OCI Resource Scheduler (cron, e.g. weekly)
           │
           ▼
  ┌─────────────────────┐
  │  OCI Function       │
  │  cert-renew         │
  └─────────┬───────────┘
            │
    ┌───────┴────────┐
    ▼                ▼
 Object Storage   certbot renew
 (certbot state)   dns-oci + resource principal
    ▲                │
    │                ▼
    └────────  deploy hook → OCI Certificates (CERT_OCID)
                              │
                              ▼
                    LB listener (unchanged; new cert version)
```

### 7a. Enable in Terraform (vars only first)

In `terraform/terraform.tfvars`:

```hcl
enable_cert_renew_function = true
lb_certificate_ocid        = "ocid1.certificate.oc1.iad...."   # same as listener
cert_renew_email           = "you@example.com"
```

### 7b. Push the function image **before** first `terraform apply`

OCI **rejects** `CreateFunction` if the image is not already in OCIR. Functions use **linux/amd64** (not arm64 like the app container):

```bash
./scripts/oci/deploy-cert-renew-function.sh --bootstrap
```

Image: `iad.ocir.io/<namespace>/cloud-store:cert-renew` (`terraform output -raw cert_renew_function_image` after apply).

### 7c. `terraform apply`

```bash
cd terraform && terraform apply
```

Creates: Object Storage bucket `cloud-store-certbot-state`, Functions application + function, dynamic group + IAM policies.

After code changes, rebuild with `./scripts/oci/deploy-cert-renew-function.sh` (updates the running function).

### 7d. Seed certbot state (once)

Copy your Mac certbot tree (account key + renewal config) to Object Storage:

```bash
./scripts/oci/seed-certbot-state.sh
```

Source defaults to `certs/certbot/` (config, work, logs from section 3).

### 7e. Test invoke

```bash
# Staging ACME — safe anytime
./scripts/oci/invoke-cert-renew-function.sh --dry-run

# Real renew (no-op until ~30 days before expiry)
./scripts/oci/invoke-cert-renew-function.sh

# POC only — forces new LE cert (rate limits apply)
./scripts/oci/invoke-cert-renew-function.sh --force-renew
```

### 7f. Schedule (Console)

1. **Governance → Resource Scheduler → Create schedule**
2. Resource type: **Functions → Function** → select `cert-renew`
3. Cron example: `0 3 * * 0` (Sundays 03:00 UTC)
4. IAM: dynamic group must include the schedule if OCI prompts (see [scheduling functions](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsscheduling.htm))

### Function config (set by Terraform)

| Key | Purpose |
|-----|---------|
| `CERT_HOSTNAME` | `oci.cloudstore893.com` |
| `CERT_OCID` | OCI Certificates resource to update |
| `CERTBOT_STATE_BUCKET` | Persist certbot between runs |
| `CERTBOT_EMAIL` | Let's Encrypt account email |

### When will it actually renew?

- `certbot renew` **skips** until ~**30 days** before expiry (unless `--force-renew`).
- Deploy the function **now**; schedule weekly — most runs log “not yet due” until ~**August 2026** for the current cert.

---

## Legacy POC path — self-signed PEM on LB (superseded)

For early bring-up only (browser/tablet warnings):

```bash
./scripts/generate-lb-tls.sh oci.cloudstore893.com
```

PEMs in gitignored `terraform/lb_tls.auto.tfvars` → `oci_load_balancer_certificate` in Terraform.

Debug tablet APK includes `PocSelfSignedTls` for this case. **Production path is Let's Encrypt + OCI Certificates above.**

---

## Enable load balancer in Terraform (first-time IaC)

In `terraform/terraform.tfvars`:

```hcl
enable_load_balancer   = true
lb_public_hostname     = "oci.cloudstore893.com"
cashier_session_secure = true   # optional; auto-enabled when TLS PEMs are set
```

```bash
cd terraform && terraform plan && terraform apply
```

**Terraform drift warning:** If the listener was updated via CLI to use **Certificates service OCID**, a later `terraform apply` may revert to inline PEM from `lb_tls.auto.tfvars`. Align `loadbalancer.tf` to use `certificate_ids`, or use `lifecycle { ignore_changes }` until IaC is updated.

---

## Oracle IdP redirect URIs

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-....identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="oci.cloudstore893.com"
export APP_PUBLIC_SCHEME="https"
export APP_PUBLIC_PORT=""
./scripts/oci/idp-update-redirect-uris.sh
```

---

## Tablet

```bash
cd android-pos && ./RebuildReinstall.sh
```

Default OCI build uses `https://oci.cloudstore893.com/` (no `:3000`).

---

## Verify

```bash
APP=$(./scripts/oci/confirm-public-url.sh)
curl -s -o /dev/null -w "%{http_code}\n" "${APP}api/build-info"

curl -s -D - -o /dev/null -X POST "${APP}api/cashier/unlock" \
  -H 'Content-Type: application/json' -d '{"pin":"8930"}' \
  | grep -i set-cookie
```

Expect `Secure` on session cookies. With Let's Encrypt, no `-k` needed.

DNS + certbot path: `./scripts/oci/verify-certbot-dns-oci.sh`

---

## Full rebuild checklist

Use when **building LB + HTTPS for the first time**, or after **`terraform-destroy-workloads.sh`**.

### What Terraform owns vs manual

| Terraform (IaC) | Manual / local |
|-----------------|----------------|
| VCN, subnet, security lists | DNS delegation (Route 53 NS → OCI) |
| Flexible load balancer + HTTPS listener | Let's Encrypt + OCI Certificates import |
| Container instance + env | LB listener `certificate_ids` (if not in TF yet) |
| OCIR repo, ADB | Oracle IdP redirect URIs |
| Compartment (**kept** on destroy) | certbot state in `certs/certbot/` |

### First-time build (summary)

1. `enable_load_balancer = true` in `terraform.tfvars` → `terraform apply`
2. Delegate DNS to OCI (section 1)
3. Install certbot + dns-oci (section 2)
4. Issue LE cert (section 3) → import to OCI Certificates (section 4)
5. Update LB listener (section 5)
6. IdP URIs + tablet rebuild
7. Verify

After destroy/rebuild: repeat DNS A record, cert import, and listener OCID if LB is recreated.

---

## Cloudflare Tunnel

If the requirement is **OCI LB**, do **not** set `CLOUDFLARE_TUNNEL_TOKEN`. See [cloudflare-tunnel.md](cloudflare-tunnel.md) for optional use only.

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| 502 from LB | Backend health: `GET /api/build-info` on container :3000 |
| OAuth http redirect | `APP_PUBLIC_URL_FROM_REQUEST=true`; browse via `https://` hostname |
| certbot “not due for renewal” | Delete staging/test cert or use `--force-renewal` |
| OCI import “incorrect PEM format” | Pass PEM inline (`$(cat file.pem)`), not `file://` |
| `dig` NXDOMAIN after delegation | NS in Route 53 for `oci`; A record in **OCI** zone |
| Browser reverts to untrusted cert | `terraform apply` may have restored self-signed PEM — re-run listener update |
| Tablet “can’t reach” HTTPS | Rebuild APK; release builds need public CA (LE now live) |

See also: [oci-network-recovery.md](oci-network-recovery.md), [idp-setup.md](idp-setup.md), [CONTENTS.md](../CONTENTS.md).
