# Cashier login — Model B (IdP + supervisor approval)

**Living doc** — update the [Journey log](#journey-log) and [Implementation checklist](#implementation-checklist) as work lands. Last updated: **2026-05-29**.

**Model B:** Cashier signs in with **Oracle Identity Domains (OIDC)**. The app creates a **pending login** and waits for a **supervisor** (admin IdP user in `store-supervisors`) to approve before issuing `cashier_session`.

Related: [idp-setup.md](idp-setup.md) (Phase 2 IdP), [CONTENTS.md](../CONTENTS.md) (session handoff).

---

## Journey log

| Date | Status | Notes |
|------|--------|-------|
| 2026-05-29 | **Designed** | Flow sketched; API contract agreed; no code in repo yet. |
| 2026-05-29 | **Branch** | Work on `feature/cashier-supervisor-approval` (from `dev`). Design doc added; implementation not started. |
| | | Next: ORDS table + `lib/login-approval.js` + supervisor routes. |

---

## Implementation checklist

| Step | Area | Status |
|------|------|--------|
| 1 | ORDS `login_approval_requests` + `seed.sql` | Not started |
| 2 | `lib/login-approval.js` | Not started |
| 3 | `lib/supervisor-auth.js` + `lib/supervisor-routes.js` | Not started |
| 4 | OIDC callback → pending (not immediate session) | Not started |
| 5 | Cashier poll APIs (`/api/cashier/approval/*`) | Not started |
| 6 | Web POS waiting screen + poll | Not started |
| 7 | Admin pending-approvals panel | Not started |
| 8 | Tablet WebView OIDC + poll | Not started |
| 9 | IdM groups + token claims in OCI Console | Not started |
| 10 | `scripts/test-login-approval.sh` | Not started |

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
| `IDP_ALLOW_PIN` | `true` | Set `false` with Model B (no shared-PIN bypass) |

Existing IdP vars unchanged: `IDP_POS_*`, `IDP_ADMIN_*`, `APP_PUBLIC_URL` — see [idp-setup.md](idp-setup.md).

---

## IdM setup (OCI Console)

1. Create groups **`store-cashiers`** and **`store-supervisors`** in the app identity domain.
2. Assign cashier users / manager users to the right groups.
3. On OIDC apps **cloud-store-pos** and **cloud-store-admin**: include **group membership** in ID token claims.
4. POS sign-on policy: password + MFA on cashier’s own device (optional; separate from supervisor step).

Supervisor approval is **app-level** — Identity Domains does not natively push “approve cashier Jane on register 2”; the admin UI (or future OCI Notifications email) handles that.

---

## Suggested build order

1. Database + `lib/login-approval.js`
2. Supervisor approve/deny via curl
3. OIDC callback → pending + poll → session cookie
4. Web POS + admin UI
5. Tablet WebView OIDC

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
| `public/admin/*` | Pending approvals panel |
| `android-pos/.../PosApi.kt` | Approval request + poll |
| `.env.example` | New env vars |
| `scripts/test-login-approval.sh` | Automated checks |

---

## Updating this doc

When you merge implementation work, update:

1. **Journey log** — date, status, one-line note.
2. **Implementation checklist** — mark steps done / in progress.
3. **Last updated** date at the top.
4. Diagrams only if the flow changes (new notification channel, tablet native OIDC, etc.).
