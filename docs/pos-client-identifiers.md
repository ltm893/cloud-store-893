# POS client identifiers — `client_kind` & `register_id`

Last updated: 2026-06-11

Contract for **native register clients** (Android `android-pos`, iOS `ios-pos`). Web POS uses `client_kind=web` and typically omits `register_id`.

**Implementation:** `lib/pos-client-kind.js`

---

## `client_kind`

| Value | Client | Notes |
|-------|--------|-------|
| `tablet` | Android POS APK | Gradle / `PosViewModel.resolveIdpLoginUrl` |
| `ios` | iPad POS (planned) | Same server paths as tablet; mirrors `ios-admin` |
| `web` | Browser POS at `/` | Default when query param omitted |

Passed as:

- OIDC: `GET /oauth/login?client_kind=…&register_id=…`
- JSON body: `{ "clientKind": "ios" }` on `/api/cashier/unlock`, `/api/cashier/approval/request`, till approval rows

Stored on `till_open_approvals.client_kind`, awaiting-till drafts, and OIDC flow state.

### Native vs web behavior

| Feature | `tablet` / `ios` | `web` |
|---------|------------------|-------|
| Till resume redirect | `/?cashier_resume=1` | `/?resumed=1` |
| OIDC completion detection | `cashier_resume` query param | `resumed` query param |
| Register lock (`register_id`) | Expected on sign-in | Optional |

Server helper: `isNativePosClient(kind)` → `true` for `tablet` and `ios`.

---

## `register_id`

One active till per physical device. Format on **both** Android and iOS:

```text
tablet-{deviceStableId}
```

| Platform | Device id source | Example |
|----------|------------------|---------|
| Android | `Settings.Secure.ANDROID_ID` | `tablet-a1b2c3d4e5f67890` |
| iOS | `UIDevice.identifierForVendor` (UUID string) | `tablet-550E8400-E29B-41D4-A716-446655440000` |
| Fallback | Unknown id | `tablet-unknown` |

**Validation (server):** when `client_kind` is `tablet` or `ios` and `register_id` is sent, it must match `tablet-{nonEmptySuffix}`. Otherwise **400** `{ code: "INVALID_REGISTER_ID" }`.

Omit `register_id` only for web POS or legacy paths — native clients should always send it on OIDC login.

### Where `register_id` is used

| Step | Field |
|------|-------|
| OIDC login query | `register_id` |
| OIDC callback / awaiting till draft | `registerId` |
| `pos_sessions.register_id` | Set on POS session create |
| `tills.register_id` | Set on till open; used for resume + register-in-use guard |
| PIN unlock (optional) | `registerId` in JSON body |

### Register-in-use

`lib/tills.js` → `assertRegisterAvailable(registerId, cashierSub)`:

- **409** `REGISTER_IN_USE` if another cashier has an **active** till on this `register_id`
- Same cashier may resume (see [pos-session-cookies.md](pos-session-cookies.md))

---

## OIDC login URL (iPad)

```http
GET /oauth/login?client_kind=ios&register_id=tablet-{uuid}&prompt=login
```

After **Break** (`POST /api/cashier/logout`), append `prompt=login` so Oracle asks for credentials again (Android: `requireFreshIdpLogin`).

---

## iOS reference (planned)

```swift
// RegisterId.swift
static func get() -> String {
    let vendor = UIDevice.current.identifierForVendor?.uuidString ?? ""
    return vendor.isEmpty ? "tablet-unknown" : "tablet-\(vendor)"
}
```

OIDC WebView completion URLs to handle (same as Android):

- `/?awaiting_till=1`
- `/?approval=pending&request_token=…`
- `/?cashier_resume=1`

---

## Android reference

- `TabletRegisterId.kt` — `tablet-{ANDROID_ID}`
- `PosViewModel.resolveIdpLoginUrl` — appends `client_kind=tablet` and `register_id`

---

## Related

- [pos-session-cookies.md](pos-session-cookies.md) — cookie state machine
- [ios-pos-port-plan.md](ios-pos-port-plan.md) — port phases (P0.2)
