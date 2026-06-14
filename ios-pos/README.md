# Cloud Store POS (iOS iPad)

Native SwiftUI register for **Cloud Store 893**, mirroring `android-pos/`. **iPad-only**, landscape.

**Status (2026-06-14):** Auth + opening till (P0–P2, **P3.1**) + **register selling (P3.2)**. Layout matches Android tablet: scan/Add Id + numpad (no product browse grid). Till close (P3.3) next.

---

## What works today

| Feature | API / behavior |
|---------|----------------|
| Launch session probe | `GET /api/cashier/session` |
| Oracle OIDC sign-in | `WKWebView` → `/oauth/login?client_kind=ios&register_id=…` |
| Cookie bridge | `WebViewCookieSync` → `CookieStore` → `URLSession` |
| Waiting for supervisor | Poll `GET /api/cashier/approval/status` every **2.5s** |
| Cancel approval | `POST /api/cashier/approval/cancel` |
| Break | `POST /api/cashier/logout` — till stays open; re-sign-in resumes |
| Opening till count | `GET /api/cashier/till/config`, `POST /api/cashier/approval/till`, denomination numpad |
| **Register selling** | Scan/Add Id numpad → cart (Android-style rows) → Pay → cash/card split tender → receipt |

## Not implemented yet (P3.3+)

- PIN numpad unlock
- Camera barcode scan
- Customer find / member discount
- Cart quantity edit panel
- Till close + close approval wait
- Admin WebView (menu item)
- Offline checkout queue

---

## Project layout

```text
ios-pos/
  Config/                    # API_BASE_URL xcconfig (mirrors ios-admin)
  CloudStorePos/
    Config/                  # AppConfig, OIDC URL helpers
    Session/                 # RegisterId, CookieStore, WebViewCookieSync, OidcRedirectLogic
    API/                     # PosAPIClient, session + sale models
    Logic/                   # TillCountLogic, CartTotalsLogic, CheckoutPaymentLogic
    ViewModels/              # PosSessionViewModel, PosRegisterViewModel
    Views/                   # OpeningTillScreen, RegisterScreen, CheckoutPaymentPanel, PosNumberPad
    WebViews/                # OidcWebView
    PosRootView.swift        # Gate router UI
  CloudStorePosTests/
```

Same **top-level shape** as `ios-admin/` (sibling Xcode app); POS has more layers because the register is native, not a single WebView.

---

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- iPad simulator or device
- Apple Developer signing team (Xcode → Signing & Capabilities)

## API host

Default: `https://oci.cloudstore893.com/` via `Config/Debug.xcconfig` and `Config/Release.xcconfig`.

**Local dev** (`npm run dev:up` from repo root):

```bash
npm run ios-pos:local-config
```

Rebuild in Xcode after LAN IP changes. Or copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`.

## Open and run

```bash
open ios-pos/CloudStorePos.xcodeproj
```

Select an **iPad** simulator (not iPhone — `TARGETED_DEVICE_FAMILY = 2`), set **Team**, Run.

## Automated tests

```bash
npm run test:ios-pos
```

27 XCTests (config, register id, OIDC redirect, till count/summary, approval JSON, cart/checkout math). Requires macOS + Xcode.

## Manual test checklist

Use **OCI** (`https://oci.cloudstore893.com/`) with Model B (supervisor approval) unless testing locally.

1. **Happy path:** Sign in with Oracle → supervisor waiting screen → approve in admin → app shows **Signed in**.
2. **Poll:** Waiting screen shows expiry timer and till summary; no manual refresh needed.
3. **Cancel:** Cancel on waiting screen → sign-in; re-login works.
4. **Denied/expired:** Supervisor denies or wait for expiry → message + sign-in gate.
5. **Break:** Signed in → Break → sign-in; next OIDC forces fresh login (`prompt=login`).
6. **Resume:** After break, same cashier on same iPad resumes active till (`cashier_resume`).
7. **Cash float:** If server has `OPENING_CASH_FLOAT`, OIDC → opening till count → submit → supervisor approval (or signed in if approval off) → register.
8. **Sell:** Enter product ID or barcode → **Add** → **Pay** → cash/card → receipt → **New sale**.
9. **Credit-only till:** Card payments only; cash buttons hidden when till is credit-only.

## Related docs

- [docs/ios-pos-port-plan.md](../docs/ios-pos-port-plan.md) — full port plan
- [docs/pos-session-cookies.md](../docs/pos-session-cookies.md) — cookie / OIDC state machine
- [docs/pos-client-identifiers.md](../docs/pos-client-identifiers.md) — `client_kind=ios`, `register_id`
- [ios-admin/README.md](../ios-admin/README.md) — admin WebView reference

## Resume development

Next: **P3.3** till close. See [CONTENTS.md](../CONTENTS.md) session handoff.
