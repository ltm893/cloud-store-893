# Cashier login — Model B (IdP + supervisor approval)

**Living doc** — update the [Journey log](#journey-log) and [Implementation checklist](#implementation-checklist) as work lands. Last updated: **2026-05-29** (step 8 landed).

**Model B:** Cashier signs in with **Oracle Identity Domains (OIDC)**. The app creates a **pending login** and waits for a **supervisor** (admin IdP user in `store-supervisors`) to approve before issuing `cashier_session`.

Related: [idp-setup.md](idp-setup.md) (Phase 2 IdP), [CONTENTS.md](../CONTENTS.md) (session handoff).

---

## Journey log

| Date | Status | Notes |
|------|--------|-------|
| 2026-05-29 | **Designed** | Flow sketched; API contract agreed; no code in repo yet. |
| 2026-05-29 | **Branch** | Work on `feature/cashier-supervisor-approval` (from `dev`). Design doc added; implementation not started. |
| 2026-05-29 | **Step 1** | `login_approval_requests` table + ORDS in `scripts/seed.sql`; read-only admin meta in `lib/admin-tables.js`. Apply via `reset-db.sh` or Database Actions. |
| 2026-05-29 | **Step 2** | `lib/login-approval.js` — ORDS create/list/approve/deny/cancel/expire; `npm run test:login-approval` smoke test. |
| 2026-05-29 | **Step 3** | `lib/supervisor-auth.js` + `lib/supervisor-routes.js` wired in `server.js`; admin OIDC stores `groups`; `npm run test:supervisor-routes`. |
| 2026-05-29 | **Step 5** | `GET/POST /api/cashier/approval/*` — poll issues session when approved; cancel; Bearer `request`; `npm run test:cashier-approval-poll`. |
| 2026-05-29 | **Step 6** | Web POS — `#approvalGate` waiting overlay, 2.5s poll on `/api/cashier/approval/status`, cancel, IdP-only sign-in when supervisor approval on. |
| 2026-05-29 | **Step 7** | Admin — `admin-approvals.js` panel (list/approve/deny, 4s refresh); session exposes `supervisorApprovalEnabled` + `isSupervisor`. |
| 2026-05-29 | **Step 8** | Tablet — WebView OIDC (`CashierOidcWebScreen`), cookie sync to Retrofit, approval poll/cancel, IdP-only login when Model B on. |
| | | Next: IdM groups + token claims in OCI Console (step 9). |

---

## Implementation checklist

| Step | Area | Status |
|------|------|--------|
| 1 | ORDS `login_approval_requests` + `seed.sql` | **Done** |
| 2 | `lib/login-approval.js` | **Done** |
| 3 | `lib/supervisor-auth.js` + `lib/supervisor-routes.js` | **Done** |
| 4 | OIDC callback → pending (not immediate session) | **Done** |
| 5 | Cashier poll APIs (`/api/cashier/approval/*`) | **Done** |
| 6 | Web POS waiting screen + poll | **Done** |
| 7 | Admin pending-approvals panel | **Done** |
| 8 | Tablet WebView OIDC + poll | **Done** |
| 9 | IdM groups + token claims in OCI Console | Not started |
| 10 | Automated test suite + CI | **Later** — manual scripts exist; see [Testing](#testing-manual-today) |

---

## High-level flow (ASCII)

```text
  CASHIER (register)              NODE APP                 ORACLE IdP           SUPERVISOR (admin)
        |                            |                          |                        |
        |  GET /oauth/login          |                          |                        |
        |--------------------------->|  redirect to IdP         |                        |
        |                            |------------------------->|                        |
        |                            |                          |  password (+ MFA)      |
        |                            |                          |<-----------------------|
        |                            |  GET /oauth/callback     |                        |
        |                            |<-------------------------|  (auth code)           |
        |                            |                          |                        |
        |                            |  verify id_token         |                        |
        |                            |  INSERT pending row      |                        |
        |                            |  Set cashier_pending     |                        |
        |                            |  (NO cashier_session)    |                        |
        |  redirect /?approval=pending                          |                        |
        |<---------------------------|                          |                        |
        |                            |                          |                        |
        |  poll GET /api/cashier/approval/status (every ~2s)    |                        |
        |--------------------------->|                          |                        |
        |<---------------------------|  { status: pending }     |                        |
        |                            |                          |                        |
        |                            |                          |  GET /admin/           |
        |                            |                          |  login-approvals       |
        |                            |<---------------------------------------------------|
        |                            |  POST …/approve          |                        |
        |                            |<---------------------------------------------------|
        |                            |  row → approved          |                        |
        |                            |                          |                        |
        |  poll approval/status      |                          |                        |
        |--------------------------->|                          |                        |
        |<---------------------------|  { status: approved }    |                        |
        |  Set-Cookie: cashier_session                          |                        |
        |                            |                          |                        |
        |  GET /api/cart → 200       |                          |                        |
        |--------------------------->|                          |                        |
```

---

## Components (ASCII)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Cloud Store 893 (Node)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  lib/oidc-pos.js          OIDC callback → pending OR immediate session      │
│  lib/login-approval.js    create / approve / deny / expire requests         │
│  lib/supervisor-routes.js GET list, POST approve/deny (admin auth)          │
│  lib/cashier-auth.js      cashier_session gate; cashier_pending cookie      │
└─────────────────────────────────────────────────────────────────────────────┘
         │                                    │
         │ ORDS REST                          │ OIDC
         ▼                                    ▼
┌──────────────────────┐            ┌──────────────────────┐
│  login_approval_     │            │  OCI Identity Domain │
│  requests (ATP)      │            │  store-cashiers      │
│                      │            │  store-supervisors   │
└──────────────────────┘            └──────────────────────┘

Clients:
  Web POS (/)     ── poll until approved ──► sale APIs (cart, checkout)
  Admin (/admin/) ── supervisor approves ──► login-approvals APIs
  Tablet          ── WebView OIDC or Bearer ──► same poll path
```

---

## Cookie and session states

```text
                    ┌─────────────────┐
                    │  Not signed in  │
                    │  (no cookies)   │
                    └────────┬────────┘
                             │ OIDC OK + approval required
                             ▼
                    ┌─────────────────┐
                    │    PENDING      │
                    │ cashier_pending │──── poll /api/cashier/approval/status
                    └────────┬────────┘
              deny/expiry/cancel │                    │ supervisor approve
                                 ▼                    ▼
                    ┌─────────────────┐     ┌─────────────────┐
                    │  Back to start  │     │    APPROVED     │
                    │  (retry IdP)    │     │ cashier_session │
                    └─────────────────┘     └────────┬────────┘
                                                     │ 8h TTL / logout
                                                     ▼
                                            cart, checkout, customers OK
```

When `CASHIER_SUPERVISOR_APPROVAL=false` (today’s behavior), OIDC callback skips **PENDING** and sets `cashier_session` immediately.

---

## API routes (planned)

### Cashier (register)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/oauth/login` | public | Start IdP sign-in |
| GET | `/oauth/callback` | public | IdP return; creates pending or session |
| GET | `/api/cashier/session` | public | `{ ok, pending, approval, … }` |
| GET | `/api/cashier/approval/status` | `cashier_pending` cookie | Poll; sets `cashier_session` when approved |
| POST | `/api/cashier/approval/request` | Bearer (tablet) | Create pending after native OIDC |
| POST | `/api/cashier/approval/cancel` | `cashier_pending` | Cashier cancels wait |
| POST | `/api/cashier/unlock` | public | **403** when Model B (`IDP_ALLOW_PIN=false`) |

### Supervisor (admin)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/admin/login-approvals` | admin + supervisor group | List pending |
| POST | `/api/admin/login-approvals/:token/approve` | admin + supervisor group | Approve login |
| POST | `/api/admin/login-approvals/:token/deny` | admin + supervisor group | Deny login |

POS APIs (`/api/cart`, `/api/checkout`, …) unchanged: require **`cashier_session`** only (not pending).

---

## Environment variables (planned)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CASHIER_SUPERVISOR_APPROVAL` | `false` | Enable Model B |
| `CASHIER_APPROVAL_TTL_SEC` | `300` | Pending request lifetime |
| `IDP_POS_CASHIER_GROUP` | `store-cashiers` | Cashiers allowed to request login |
| `IDP_SUPERVISOR_GROUP` | `store-supervisors` | Who may approve |
| `CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR` | `false` | Local dev: admin PIN counts as supervisor when IdP groups absent |
| `IDP_ALLOW_PIN` | `true` | Set `false` with Model B (no shared-PIN bypass) |

Existing IdP vars unchanged: `IDP_POS_*`, `IDP_ADMIN_*`, `APP_PUBLIC_URL` — see [idp-setup.md](idp-setup.md).

---

## IdM setup (OCI Console)

1. Create groups **`store-cashiers`** and **`store-supervisors`** in the app identity domain.
2. Assign cashier users / manager users to the right groups.
3. On OIDC apps **cloud-store-pos** and **cloud-store-admin**: include **group membership** in ID token claims.
   - **cloud-store-admin** → open app → **General information** (or **Resources**) → ensure **`groups`** is in **Allowed scopes**.
   - **Sign-on policies** (or app **Token issuance** / **Claims**): add a claim so **`groups`** appears in the **ID token** (group names like `store-supervisors`, not just app assignment).
   - Server requests `IDP_SCOPES=openid profile email groups` (default after recent deploy).
4. POS sign-on policy: password + MFA on cashier’s own device (optional; separate from supervisor step).

Supervisor approval is **app-level** — Identity Domains does not natively push “approve cashier Jane on register 2”; the admin UI (or future OCI Notifications email) handles that.

ORDS REST path (after seed): `{ORDS_BASE_URL}/login_approval_requests/`

---

## Testing (manual today)

These checks are **opt-in**. They do **not** run on `npm start`, `npm run dev`, `npm run dev:up`, Docker build, or Terraform apply. There is **no GitHub Actions CI** yet; `npm test` is still a placeholder.

Run them after changing login-approval or supervisor code, or before merging `feature/cashier-supervisor-approval`.

### What exists now

| Script | Needs | Effect |
|--------|-------|--------|
| `npm run test:login-approval` | Live ORDS (`ORDS_BASE_URL`) | Creates a pending row via `lib/login-approval.js`, approves it, verifies ORDS |
| `npm run test:supervisor-routes` | Server running **and** same env on server | HTTP tests for `GET/POST /api/admin/login-approvals/*` |
| `npm run test:cashier-approval-session` | Server with `CASHIER_SUPERVISOR_APPROVAL=true` | Pending cookie + `/api/cashier/session`; PIN blocked when approval on |
| `npm run test:cashier-approval-poll` | Server + supervisor PIN fallback | Poll → approve → `cashier_session` E2E |
| `npm run test:auth` | Server running | Existing POS/admin session guards (unrelated feature, same pattern) |

`test:login-approval` writes test rows to `login_approval_requests` (approved/denied). Safe for dev ADB; avoid on production.

### How to run (supervisor routes)

```bash
# Terminal 1 — flag must be on the *server* process for PIN-based supervisor tests
CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run dev:up

# Terminal 2
CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run test:supervisor-routes
CASHIER_SUPERVISOR_APPROVAL=true npm run test:cashier-approval-session
CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run test:cashier-approval-poll
```

ORDS module only (no HTTP server):

```bash
ORDS_BASE_URL="$(cd terraform && terraform output -raw ords_base_url)" npm run test:login-approval
```

Verify ORDS endpoint (note slash after `admin`):

```bash
ORDS=$(cd terraform && terraform output -raw ords_base_url)
curl -s "${ORDS}/login_approval_requests/" | head
```

### Later — wire into normal workflow (TODO)

Pick up when Model B is merge-ready or CI is added:

- [ ] Add `npm run test:approval` that runs `test:login-approval` + documents server prerequisite for `test:supervisor-routes` (or starts server in script).
- [ ] Point root `npm test` at a small runner (`test:auth` + `test:approval` when server/ORDS available).
- [ ] GitHub Actions (or similar): ORDS smoke on schedule or PR; HTTP tests with ephemeral Node + env secrets.
- [ ] Optional: extend `scripts/test-auth-protection.sh` for `/api/admin/login-approvals` 401/403 matrix.
- [ ] Document `CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR` only for local dev — production uses IdP group `store-supervisors`.

Until then, treat the scripts above as **manual regression checks**, not release gates.

### End-to-end manual (web + admin + tablet)

Prerequisites: POS IdP configured (`IDP_POS_*`, `APP_PUBLIC_URL` matches the URL browsers/tablet use — **LAN IP**, not only `127.0.0.1`); `login_approval_requests` ORDS endpoint applied (`scripts/seed.sql` or `reset-db.sh`).

```bash
# Terminal 1
CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run dev:up
```

| Step | Where | Action |
|------|--------|--------|
| 1 | Web `/` or tablet | Cashier: **Sign in with Oracle** (PIN hidden when Model B on) |
| 2 | Same client | **Waiting for supervisor** — poll every ~2.5s |
| 3 | `/admin/` | Supervisor: sign in (PIN with `CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true` locally, or IdP `store-supervisors` in OCI) |
| 4 | Admin → **Login approvals** | **Approve** the pending cashier |
| 5 | Web or tablet | Register loads; add to cart / checkout works |

**Tablet only:** rebuild APK with current Mac LAN IP (`LAN_IP=… ./RebuildReinstall.sh` in `android-pos/`).

**Windows PC:** use Chrome/Edge at `http://<LAN_IP>:3000/` as cashier; tablet or another browser tab for admin — no APK needed.

**Cancel / deny:** cashier **Cancel request** or supervisor **Deny** → cashier returns to IdP sign-in with message.

---

## Database apply

**Apply locally / OCI** (destructive — recreates all tables):

```bash
./scripts/reset-db.sh
# or paste scripts/seed.sql in Database Actions → SQL → Run Script
```

Verify ORDS:

```bash
ORDS=$(cd terraform && terraform output -raw ords_base_url)
curl -s "${ORDS}/login_approval_requests/" | head
# expect {"items":[]} or empty items array
```

---

## Suggested build order (completed)

1. ORDS + `login-approval.js` store
2. Supervisor approve/deny routes
3. OIDC callback → pending + poll APIs
4. Web POS waiting + poll (step 6)
5. Admin pending-approvals panel (step 7)
6. Tablet WebView OIDC + poll (step 8)
7. **Next:** IdM groups in OCI Console (step 9); CI / `npm test` (step 10)

---

## Files to touch (when implementing)

| File | Role |
|------|------|
| `scripts/seed.sql` | `login_approval_requests` table + ORDS |
| `lib/login-approval.js` | Core pending/approve logic |
| `lib/supervisor-auth.js` | Group membership check |
| `lib/supervisor-routes.js` | Admin approval APIs |
| `lib/oidc-pos.js` | Defer session until approved |
| `lib/cashier-auth.js` | Pending cookie + extended `/session` |
| `lib/admin-auth.js` | Store `groups` on admin OIDC session |
| `public/app.js` | Waiting + poll UI |
| `public/admin/admin-approvals.js` | Pending approvals panel |
| `android-pos/.../PosApi.kt` | Session + approval poll/cancel APIs |
| `android-pos/.../CashierOidcWebScreen.kt` | WebView OIDC login |
| `android-pos/.../WebViewCookieSync.kt` | WebView → OkHttp cookie bridge |
| `.env.example` | New env vars |
| `scripts/test-login-approval-lib.js` | ORDS smoke (step 2) |
| `scripts/test-supervisor-routes.sh` | HTTP smoke (step 3) |
| `scripts/create-test-pending-approval.js` | Helper for supervisor route test |

---

## Updating this doc

When you merge implementation work, update:

1. **Journey log** — date, status, one-line note.
2. **Implementation checklist** — mark steps done / in progress.
3. **Last updated** date at the top.
4. Diagrams only if the flow changes (new notification channel, tablet native OIDC, etc.).
