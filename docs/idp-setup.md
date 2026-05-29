# Identity roadmap — Phase 1 done in repo, Phase 2 in OCI Console

**Starting over on IdP apps only?** Use **[idp-level1-reset.md](idp-level1-reset.md)** (delete/recreate `cloud-store-pos` + `cloud-store-admin`).

## Phase 1 (implemented): PIN sessions + network lockdown

### Cashier session (application)

- `POST /api/cashier/unlock` — PIN → HttpOnly `cashier_session` cookie (8h).
- `GET /api/cashier/session` — `{ ok: true|false }`.
- `POST /api/cashier/logout` — clears session.
- **Public without session:** `GET /api/products` only.
- **Requires session:** cart, checkout, customers, recent sales.
- Admin (`/admin/`, `/api/admin/*`) unchanged — separate `admin_session` cookie.

**Local:** use `credentials: 'include'` on fetches (web POS does). Tablet uses OkHttp cookie jar.

**OCI over HTTPS:** set in `terraform.tfvars`:

```hcl
cashier_session_secure = true
```

Then `terraform apply` (rebuild/push image if only env changed).

### Network lockdown (Terraform)

In `terraform.tfvars`:

```hcl
# Shop public IP only (example)
ingress_allowed_cidrs = ["203.0.113.50/32"]

# Optional: disable SSH from the internet
allow_ssh_ingress = false
```

Default remains `["0.0.0.0/0"]` (public app). **Tablets on LTE** will not reach a locked-down IP unless you use VPN, Cloudflare Tunnel, or keep `0.0.0.0/0` and rely on app auth.

After changing CIDRs: `cd terraform && terraform apply`.

---

## Phase 2: OCI Identity Domain (IdP) — console steps

Do **not** use the tenancy **Default** domain for POS apps. Create a **new** domain for application users.

### 1. Choose SKU

| Use case | Domain type | Billing |
|----------|-------------|---------|
| Few staff cashiers (employees) | **Premium** | Per user / month |
| Pay only when someone signs in | **External Active User** | Per active user / month (non-employee licensing) |

Check cost: **OCI Console → Billing → Cost Analysis** after creating the domain and 1–2 test users.

Docs: [IAM Identity Domain Types](https://docs.oracle.com/en-us/iaas/Content/Identity/sku/overview.htm)

### 2. Create domain

1. **Identity & Security → Domains → Create domain**
2. Name e.g. `cloud-store-apps`
3. Type: **Premium** (workforce) or **External Active User** (if appropriate)
4. Home region: same as your ADB/container (e.g. `us-ashburn-1`)

### 3. Create users (pilot)

- Domain → **Users** → Create (e.g. `cashier1`, `admin1`)
- Add to groups if you use group policies later

### 4. Register OIDC confidential clients

Create **two** applications (confidential clients):

| App name | Redirect URIs (examples) |
|----------|---------------------------|
| `cloud-store-pos` | `https://<app-host>/`, tablet custom scheme if needed |
| `cloud-store-admin` | `https://<app-host>/admin/` |

Per app:

1. **Applications → Add application → OIDC confidential**
2. Note **Client ID** and **Client secret**
3. Enable **Authorization code** (and refresh if offered)
4. Scopes: `openid` (and `profile` / `email` as needed)

Issuer URL format:

```text
https://idcs-<identity-domain-id>.identity.oraclecloud.com
```

(Find exact issuer under domain **Settings** or application **Configuration**.)

### 5. Wire into Node (implemented)

Add redirect URIs in OCI (in addition to `/` and `/admin/` if already set):

| App | Callback URL |
|-----|----------------|
| **cloud-store-pos** | `http://<host>:3000/oauth/callback` |
| **cloud-store-admin** | `http://<host>:3000/oauth/admin/callback` |

**Where in the Console:** On each app → **OAuth configuration** tab → right column **Redirect URL** (not inside **Edit OAuth configuration**, which only edits grant types / resources). Use **Add redirect URL** next to the existing list.

**CLI (easier if the edit modal hides redirects):**

```bash
# home-region-url from: oci iam domain list (no :443, no /admin/v1)
export IDP_DOMAIN_ENDPOINT="https://idcs-XXXX.us-ashburn-idcs-1.identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="150.136.37.236"
export APP_PORT="3000"
./scripts/idp-update-redirect-uris.sh
```

Copy `.env.example` IdP vars into `.env` (and container env on OCI when ready):

```env
APP_PUBLIC_URL=http://150.136.37.236:3000

IDP_POS_ISSUER=https://idcs-....identity.oraclecloud.com
IDP_POS_CLIENT_ID=...
IDP_POS_CLIENT_SECRET=...

IDP_ADMIN_ISSUER=https://idcs-....identity.oraclecloud.com
IDP_ADMIN_CLIENT_ID=...
IDP_ADMIN_CLIENT_SECRET=...

IDP_ALLOW_PIN=true
```

**Routes:**

| Route | Purpose |
|-------|---------|
| `GET /oauth/login` | Start POS IdP sign-in |
| `GET /oauth/callback` | POS OAuth callback → `cashier_session` cookie |
| `GET /oauth/admin/login` | Start admin IdP sign-in |
| `GET /oauth/admin/callback` | Admin callback → `admin_session` cookie |

Without IdP env vars, **PIN-only** behavior is unchanged. With IdP configured, web POS shows an Oracle sign-in link; APIs also accept `Authorization: Bearer <access_token>`.

### 6. HTTPS

OIDC redirects require HTTPS in production. Options:

- OCI Load Balancer + certificate in front of the container
- Cloudflare Tunnel / reverse proxy

Set `cashier_session_secure = true` when TLS terminates in front of the app.

---

## Phase 3 (planned): Supervisor approval after IdP login — Model B

After a cashier authenticates with Oracle IdP, a **supervisor** must approve before the register gets a `cashier_session` cookie. This is **not** a built-in Identity Domains feature — the Node app owns pending state and approval APIs; IdM provides **individual cashier identity** and **supervisor group** membership.

**Living design doc (flow diagram, API checklist, journey log):** [cashier-supervisor-approval.md](cashier-supervisor-approval.md)

Summary:

- Cashier: `GET /oauth/login` → callback creates **pending** row (no session yet).
- Register polls `GET /api/cashier/approval/status` until approved.
- Supervisor: admin UI → `POST /api/admin/login-approvals/:token/approve` (must be in `store-supervisors`).
- Enable with `CASHIER_SUPERVISOR_APPROVAL=true` and `IDP_ALLOW_PIN=false` (when implemented).

---

## Verify Phase 1

```bash
# Unlock
curl -s -c /tmp/cs-cookies -X POST http://127.0.0.1:3000/api/cashier/unlock \
  -H 'Content-Type: application/json' -d '{"pin":"8930"}'

# Cart without cookie → 401
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/api/cart

# Cart with cookie → 200
curl -s -b /tmp/cs-cookies -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/api/cart
```

---

## Deploy checklist (OCI)

1. `docker buildx build` + `docker push`
2. Set `ingress_allowed_cidrs` / `cashier_session_secure` in `terraform.tfvars`
3. `terraform apply`
4. Rebuild tablet APK if `app_url` or host changed
5. Test unlock from tablet and web POS
