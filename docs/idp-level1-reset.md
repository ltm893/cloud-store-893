# Level 1 — Reset IdP apps (clean start)

Keep: **cloud-store-apps** domain, users, groups (`pos-cashiers`, `store-admins`, `Domain_Administrators`), compartment, container, ADB, PIN login in Node.

Replace: **cloud-store-pos** and **cloud-store-admin** integrated applications only.

Get your app host:

```bash
cd terraform && terraform output -raw app_url
# e.g. http://150.136.37.236:3000  →  HOST=150.136.37.236  PORT=3000
```

Domain CLI base URL (no `:443`, no `/admin/v1`):

```bash
COMP=$(terraform output -raw compartment_ocid)
oci iam domain list --compartment-id "$COMP" \
  --query 'data[?"display-name"==`cloud-store-apps`].["display-name","url","home-region-url"]' \
  --output table
```

Use **home-region-url** without `:443` for scripts:

```text
https://idcs-de480a55965c46e0a69fb7988416090f.us-ashburn-idcs-1.identity.us-ashburn-1.oci.oraclecloud.com
```

Issuer (for `.env`, usually without port):

```text
https://idcs-de480a55965c46e0a69fb7988416090f.identity.oraclecloud.com
```

---

## Step 1 — PIN-only while you rebuild (optional)

Comment out all `IDP_*` lines in `.env`. Restart Node. POS/admin still work on PIN.

---

## Step 2 — Delete old apps

**Domains → cloud-store-apps → Integrated applications**

1. **cloud-store-pos** → Actions → Delete  
2. **cloud-store-admin** → Actions → Delete  

Old Client ID / secret are invalid after this.

---

## Step 3 — Create `cloud-store-pos`

1. **Add application → Confidential Application → Launch workflow**
2. **Details**
   - Name: `cloud-store-pos`
   - Description: `POS OIDC client`
   - Application URL: `http://150.136.37.236:3000` (your `app_url` host/port)
   - Leave custom sign-in/out/error URLs **empty**
3. **Configure OAuth → Client configuration → Configure this application as a client now**
   - **Resource server:** No  
   - **Authorization:** Authorization code + Refresh token  
   - **Allow non-HTTPS URLs:** On  
   - **Redirect URL** — add **each** line (use Add redirect URL):
     ```text
     http://150.136.37.236:3000
     http://150.136.37.236:3000/oauth/callback
     http://127.0.0.1:3000/
     http://127.0.0.1:3000/oauth/callback
     ```
4. **Web tier policy:** Skip / do later  
5. **Finish → Activate**

**Configuration tab:** copy **Client ID**, **Client secret** (once), confirm **Issuer**.

---

## Step 4 — Create `cloud-store-admin`

Same flow:

| Field | Value |
|-------|--------|
| Name | `cloud-store-admin` |
| Application URL | `http://150.136.37.236:3000/admin/` |
| Grants | Authorization code + Refresh token |
| Allow HTTP | On |
| Redirect URLs | `http://150.136.37.236:3000/admin/` |
| | `http://150.136.37.236:3000/oauth/admin/callback` |
| | `http://127.0.0.1:3000/admin/` |
| | `http://127.0.0.1:3000/oauth/admin/callback` |

Activate. Copy **new** Client ID + secret.

---

## Step 5 — Assign groups to apps

| Application | Assign group |
|-------------|----------------|
| cloud-store-pos | `pos-cashiers` (+ yourself for testing) |
| cloud-store-admin | `store-admins` |

---

## Step 6 — `.env` (local)

```env
APP_PUBLIC_URL=http://150.136.37.236:3000

IDP_POS_ISSUER=https://idcs-de480a55965c46e0a69fb7988416090f.identity.oraclecloud.com
IDP_POS_CLIENT_ID=<new from cloud-store-pos>
IDP_POS_CLIENT_SECRET=<new from cloud-store-pos>
IDP_POS_REDIRECT_URI=http://150.136.37.236:3000/oauth/callback

IDP_ADMIN_ISSUER=https://idcs-de480a55965c46e0a69fb7988416090f.identity.oraclecloud.com
IDP_ADMIN_CLIENT_ID=<new from cloud-store-admin>
IDP_ADMIN_CLIENT_SECRET=<new from cloud-store-admin>
IDP_ADMIN_REDIRECT_URI=http://150.136.37.236:3000/oauth/admin/callback

IDP_ALLOW_PIN=true
```

`IDP_*_REDIRECT_URI` must match a redirect URL registered in OCI **exactly** (including trailing slash).

Restart: `npm run dev` or redeploy container with same vars.

---

## Step 7 — Test

| Test | URL / command |
|------|----------------|
| PIN still works | `curl -X POST http://150.136.37.236:3000/api/cashier/unlock -H 'Content-Type: application/json' -d '{"pin":"8930"}'` |
| IdP POS | Browser: `http://150.136.37.236:3000/oauth/login` → Oracle login → lands on site signed in |
| IdP admin | `http://150.136.37.236:3000/oauth/admin/login` → `/admin/` |
| Web POS | “Sign in with store account (Oracle)” or PIN |

---

## Optional: CLI instead of typing redirects in wizard

After apps exist, if redirects are missing:

```bash
export IDP_DOMAIN_ENDPOINT="https://idcs-de480a55965c46e0a69fb7988416090f.us-ashburn-idcs-1.identity.us-ashburn-1.oci.oraclecloud.com"
export APP_PUBLIC_HOST="150.136.37.236"
export APP_PORT="3000"
./scripts/idp-update-redirect-uris.sh
```

---

## Checklist

- [ ] Deleted old pos + admin apps  
- [ ] Created both confidential apps with 4 redirect URLs each  
- [ ] Activated both  
- [ ] Assigned groups  
- [ ] Updated `.env` with new secrets  
- [ ] Tested `/oauth/login` and PIN  

See also: [idp-setup.md](idp-setup.md) for Phase 1 PIN / network / HTTPS notes.
