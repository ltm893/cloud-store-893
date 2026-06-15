# iOS iPad POS port — master plan

Last updated: 2026-06-11

Native SwiftUI register for iPad, reusing server APIs and patterns from `android-pos/`. Admin stays in `ios-admin/` (WKWebView). **Do not** ship register as web POS in a WebView — web POS lacks till open/close parity.

**Prerequisites:** Till/POS session schema (`pos_sessions`, `tills`, `till_*_approvals`) is live on `dev` and OCI.

---

## Session pause (2026-06-14)

**P3.5 offline queue complete** (2026-06-11). Checkout network failures enqueue locally; sync replays cart + checkout on reconnect.

| Phase | Status |
|-------|--------|
| P0 — contracts | Done (docs + `lib/pos-client-kind.js`) |
| P2 — iOS auth | Done (`ios-pos` through approval poll) |
| P3.1 — opening till | Done |
| P3.2 — selling | Done (scan/Add Id, cart rows, checkout, split tender) |
| P3.3 — till close | **Done** (close count, credit-only close, close approval poll) |
| P1 — OpenAPI / Swift payment math | Partial (cart/checkout logic in Swift) |
| P3.5 — offline queue | **Done** (enqueue on network failure, sync/discard UI) |
| P3.4+ — admin, customer find | **Done** |

**Resume here:** PIN unlock, camera barcode, card on file, receipt print. See [ios-pos/README.md](../ios-pos/README.md) manual test checklist.

---

## Architecture

| Layer | iOS approach | Reference |
|-------|--------------|-----------|
| Register UI | Native SwiftUI | Port `android-pos` screens + `CashierAuthGate` |
| OIDC sign-in | WKWebView → cookie bridge | `CashierOidcWebScreen.kt`, `WebViewCookieSync.kt` |
| REST API | `URLSession` + shared cookie store | `PosApi.kt`, `MemoryCookieJar.kt` |
| Admin | WKWebView (`client_kind=ios`) | `ios-admin/CloudStoreAdmin/` |
| Config | xcconfig `API_BASE_URL` | `ios-admin/Config/` |

```text
ios-pos/                          (Xcode project — exists)
  Config/                         Debug.xcconfig, Release.xcconfig, Local.xcconfig.example
  CloudStorePos/
    Session/                      CookieStore, WebViewCookieSync, RegisterId, OidcRedirectLogic
    API/                          PosAPIClient, CashierSessionModels, ApprovalStatusModels
    Logic/                        TillApprovalSummaryLogic
    ViewModels/                   PosSessionViewModel
    WebViews/                     OidcWebView
    PosRootView.swift             Gate router (auth only today)
  CloudStorePosTests/             18 XCTests
```

---

## Phases

### Phase 0 — Contract & session (blockers)

| ID | Task | Deliverable | Status |
|----|------|-------------|--------|
| **P0.1** | Cookie + OIDC state machine | [pos-session-cookies.md](pos-session-cookies.md) | **Done** |
| **P0.2** | `register_id` + `client_kind=ios` contract | [pos-client-identifiers.md](pos-client-identifiers.md) + `lib/pos-client-kind.js` | **Done** |
| **P0.3** | Logout vs sign-off semantics | Section in session doc + iOS/Android alignment note | Partial (in P0.1) |

### Phase 1 — API contract & portable logic

| ID | Task | Deliverable | Status |
|----|------|-------------|--------|
| **P1.1** | OpenAPI / YAML spec | `docs/pos-api.yaml` from `PosApi.kt` + `PosModels.kt` | Pending |
| **P1.2** | Stable error `code` fields | Audit `lib/cashier-auth.js`, `lib/approval-errors.js`, till guards | Pending |
| **P1.3** | Port payment/till math to Swift | `CheckoutPaymentLogic`, till denomination sums + tests | Pending |
| **P1.4** | Consolidate till-sales ORDS queries | `lib/till-sales-query.js` (server; reduces close/report bugs) | Pending |

### Phase 2 — iOS scaffold & session proof

| ID | Task | Deliverable | Status |
|----|------|-------------|--------|
| **P2.1** | `ios-pos` Xcode project | Config, empty SwiftUI shell | **Done** |
| **P2.2** | Cookie bridge + session probe | `CookieStore`, `WebViewCookieSync`, `OidcWebView`, gates | **Done** |
| **P2.3** | Session probe on launch | (merged into P2.2) | **Done** |
| **P2.4** | OIDC full flow + approval poll | Poll, cancel, till summary UI | **Done** |

### Phase 3 — Register UI port

| ID | Task | Deliverable | Status |
|----|------|-------------|--------|
| **P3.1** | Opening till + auth polish | Till count UI, PIN (dev); waiting/OIDC already done | **Done** |
| **P3.2** | Selling | Scan/Add Id, cart rows, checkout, split tender | **Done** |
| **P3.3** | Till close | Close count, waiting close approval | **Done** |
| **P3.4** | Break | `POST /api/cashier/logout` — done in register header | **Done** |
| **P3.5** | Offline queue | Port Android queued checkout if needed | **Done** |

### Phase 4 — API cleanup (aliases, no breaking changes)

| ID | Task | Deliverable | Status |
|----|------|-------------|--------|
| **P4.1** | Till close path aliases | `/api/cashier/till/close/*` alongside `shift/close/*` | Pending |
| **P4.2** | Admin path aliases (optional) | `till-closes` alongside `shift-closes` | Pending |
| **P4.3** | Doc sweep | Update stale `shift_*` / `login_approval` references | Pending |

### Phase 5 — Quick wins (parallel, non-blocking)

- Fix admin `cash_and_card` → `cash_and_credit` in `public/admin/admin.js`
- `probeTillColumns()` for `till_type`
- Deprecate `migrate-login-approval-till.*`
- `package.json` `main` → `server.js`
- Add `pos_sessions` to admin read-only tables

---

## Client identifiers

| Platform | `client_kind` | `register_id` |
|----------|---------------|-----------------|
| Android tablet | `tablet` | `tablet-{ANDROID_ID}` |
| iOS iPad | `ios` | `tablet-{identifierForVendor}` |
| Web POS | `web` | (none) |

OIDC login URL (tablet/iOS):

```http
GET /oauth/login?client_kind=ios&register_id=tablet-{uuid}&prompt=login
```

`prompt=login` after **Break** forces fresh IdP credentials (Android sets `requireFreshIdpLogin`).

---

## Auth gate mapping (Android → iOS)

Port `CashierAuthGate` from `PosViewModel.kt` one-to-one:

| Gate | Trigger |
|------|---------|
| `Checking` | App start, post-OIDC cookie sync |
| `PinSignIn` | No session; PIN allowed |
| `OidcSignIn` | User taps Oracle sign-in |
| `OpeningTill` | `cashier_awaiting_till` or `session.awaitingTill` |
| `WaitingApproval` | `cashier_pending` or `session.pending` |
| `SignedIn` | `session.ok` |
| `ClosingTill` / `ClosingCreditOnly` | User starts EOD close |
| `WaitingCloseApproval` | Close submitted, supervisor pending |

Probe: always `GET /api/cashier/session` after cookie sync.

---

## Defer (do not block iOS)

| Item | Reason |
|------|--------|
| Kotlin Multiplatform UI | SwiftUI rewrite is clearer |
| Split Android `PosViewModel` | Port structure to Swift instead |
| Bearer-token auth | Only if WKWebView cookies fail on iOS |
| Web POS till parity | Tablet-only till is intentional |
| Wire Android `sign-off` in UI | Break uses `logout`; close uses till close flow |
| Server-side tax unification | Tablet computes tax client-side today |

---

## Test plan (end-to-end)

### iOS auth (testable now — P2 complete)

1. OCI OIDC → supervisor approval poll → signed-in stub.
2. Cancel pending approval → clean sign-in.
3. Break → logout; re-OIDC with fresh login.
4. Resume active till after break (`cashier_resume=1`).
5. Opening-till stub when `OPENING_CASH_FLOAT` configured (full count UI in P3).

### Full register (after P3)

1. **Credit-only OCI:** OIDC → supervisor approval → sell → break → resume same till.
2. **Cash float** (`OPENING_CASH_FLOAT=200`): OIDC → opening count → supervisor approval → cash checkout → EOD close → supervisor approve close.
3. **Register lock:** Second device same `register_id` → 409 `REGISTER_IN_USE`.
4. **Cookie expiry:** `cashier_awaiting_till` TTL 30m → `AWAITING_TILL_EXPIRED`.

---

## Related docs

- [ios-pos/README.md](../ios-pos/README.md) — run, XCTest, manual test checklist
- [pos-session-cookies.md](pos-session-cookies.md) — P0.1 cookie/OIDC state machine
- [pos-client-identifiers.md](pos-client-identifiers.md) — P0.2 `client_kind` + `register_id`
- [cashier-supervisor-approval.md](cashier-supervisor-approval.md) — Model B supervisor flow
- [cash-till-opening-and-close.md](cash-till-opening-and-close.md) — till open/close (some names stale)
- [idp-setup.md](idp-setup.md) — Oracle IdP configuration
- `ios-admin/README.md` — admin WebView pattern

---

## Suggested implementation order

```text
P0.1–P0.2  session + client id docs     ✓
P2.1–P2.4  ios-pos auth scaffold       ✓  ← paused here (2026-06-13)
P1.1       pos-api.yaml                 (helpful before P3.2)
P3.1       opening till UI              ✓ done
P3.2       products/cart/checkout       ✓ done
P3.3       till close                   ✓ done
P3.5       offline queue                ✓ done
P1.3       Swift payment logic          (parallel with P3.2)
P4.x       API aliases
```
