# HTTPS with Cloudflare Tunnel (OCI) — optional

> **POC requirement is OCI Load Balancer?** Use **[oci-load-balancer-https.md](oci-load-balancer-https.md)** instead. Do not set `CLOUDFLARE_TUNNEL_TOKEN`.

Public URL: **`https://oci.cloudstore893.com/`** (no `:3000`). The container keeps serving HTTP on port 3000 locally; `cloudflared` connects outbound to Cloudflare and terminates TLS at the edge.

## Architecture

```text
Browser / tablet ──HTTPS──► Cloudflare edge
                                │
                           cloudflared (in container)
                                │
                           Node.js http://127.0.0.1:3000
```

No TLS cert in the Docker image. No OCI Load Balancer required.

---

## 1. Cloudflare — create the tunnel

1. [Cloudflare dashboard](https://dash.cloudflare.com) → add zone **`cloudstore893.com`** (or use an existing zone).
2. **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel**.
3. Name: e.g. `cloudstore893-oci`.
4. Connector: **Docker** — copy the **tunnel token** (treat as a secret).

## 2. Cloudflare — public hostname

In the tunnel, add a **Public Hostname**:

| Field | Value |
|-------|--------|
| Subdomain | `oci` |
| Domain | `cloudstore893.com` |
| Service | HTTP |
| URL | `localhost:3000` |

## 3. DNS

**If the zone uses Cloudflare nameservers:** the CNAME is created automatically.

**If DNS stays on Route 53:** replace the `oci` A record with:

```text
oci.cloudstore893.com  CNAME  <tunnel-id>.cfargotunnel.com
```

Keep the reserved OCI IP for optional direct HTTP debugging; users and tablets should use the HTTPS hostname.

## 4. Repo — inject the token on OCI

Add to `.env` (never commit):

```env
CLOUDFLARE_TUNNEL_TOKEN=eyJh...
CLOUDFLARE_TUNNEL_HOSTNAME=oci.cloudstore893.com
APP_PUBLIC_URL_FROM_REQUEST=true
```

Sync and apply (replaces container instance — may detach reserved IP):

```bash
./scripts/oci/sync-container-env-to-terraform.sh
./scripts/oci/terraform-apply-container.sh
```

Or set in `terraform/terraform.tfvars`:

```hcl
cloudflare_tunnel_token    = "eyJh..."
cloudflare_tunnel_hostname = "oci.cloudstore893.com"
```

`cashier_session_secure` is set automatically when the tunnel token is present.

**App code only** (token already in container env from a prior apply):

```bash
./scripts/oci/redeploy-app-code.sh
```

## 5. Oracle IdP redirect URIs

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-....identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="oci.cloudstore893.com"
export APP_PUBLIC_SCHEME="https"
export APP_PUBLIC_PORT=""
./scripts/oci/idp-update-redirect-uris.sh
```

## 6. Tablet APK

```bash
cd android-pos
./RebuildReinstall.sh
```

Default OCI build uses `https://oci.cloudstore893.com/`. Local Mac dev is unchanged: `USE_LOCAL=1 ./RebuildReinstall.sh`.

## 7. Verify

```bash
APP=$(./scripts/oci/confirm-public-url.sh)
curl -sS "${APP}api/build-info"

curl -sSI -X POST "${APP}api/cashier/unlock" \
  -H 'Content-Type: application/json' -d '{"pin":"8930"}' \
  | grep -i set-cookie
```

Expect `Secure` on `cashier_session` when `CASHIER_SESSION_SECURE=true`.

Terraform outputs:

```bash
cd terraform && terraform output app_url_https
```

---

## Local Docker test (optional)

```bash
export CLOUDFLARE_TUNNEL_TOKEN=eyJh...
docker buildx build --platform linux/arm64 -t cloud-store-test .
docker run --rm -p 3000:3000 \
  -e ORDS_BASE_URL="$ORDS_BASE_URL" \
  -e CLOUDFLARE_TUNNEL_TOKEN \
  cloud-store-test
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Hostname 522 / tunnel error | Container running? Token set? `cloudflared` logs in OCI Console |
| OAuth `invalid_redirect_uri` | IdP URIs must be `https://oci.cloudstore893.com/...` (no port) |
| Cookies not sticking | Browse via HTTPS hostname; `CASHIER_SESSION_SECURE=true` |
| Direct IP still works | Expected during migration; optional lockdown later |

See also: [oci-network-recovery.md](oci-network-recovery.md), [idp-setup.md](idp-setup.md).
