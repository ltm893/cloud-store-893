# Cloud Store Admin (iOS)

Standalone iOS app for the **Cloud Store 893** admin console. It loads the existing web admin (`/admin/`) in a `WKWebView` — same approach as the Android tablet’s **Admin** menu item (`AdminWebScreen.kt`).

## What you get

- Full admin UI: table CRUD, inventory views, supervisor login approvals
- PIN and Oracle IdP sign-in (handled by the web app; `admin_session` cookie stays in the WebView)
- **iPhone:** portrait-only (native lock + injected CSS/JS hides the web “rotate to landscape” overlay — works even before OCI is redeployed)
- **iPad:** landscape-only (matches `admin-orientation.js`)

No native rewrite of `public/admin/*.js` — one admin codebase for web, Android WebView, and iOS.

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- Apple Developer signing team (set **Signing & Capabilities** in Xcode)

## API host (`API_BASE_URL`)

Baked in at build time via `Config/Debug.xcconfig` and `Config/Release.xcconfig` (default: `https://oci.cloudstore893.com/`).

**Local Mac dev** (`npm run dev:up`):

1. Copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`
2. Set `API_BASE_URL = http://192.168.x.x:3000/` (use `npm run lan-url`)
3. In Xcode: Project → Info → Configurations → include `Local.xcconfig` for Debug, or edit `Debug.xcconfig` to `#include "Local.xcconfig"`

`Info.plist` enables `NSAllowsLocalNetworking` for HTTP on LAN.

## Open and run

```bash
open ios-admin/CloudStoreAdmin.xcodeproj
```

Select a simulator or device, set your **Team**, then Run. Sign in with `ADMIN_PIN` (default `8930`) or Oracle when IdP is configured on the server.

## Project layout

| Path | Purpose |
|------|---------|
| `CloudStoreAdmin/AdminWebView.swift` | `WKWebView` wrapper |
| `CloudStoreAdmin/Config.swift` | Reads `API_BASE_URL` from bundle |
| `Config/*.xcconfig` | Build-time API host |

## Native admin vs WebView

A full SwiftUI CRUD port would duplicate `lib/admin-tables.js` and `public/admin/admin.js` and still miss inventory POST endpoints that are not in the web UI today. WebView keeps admin behavior identical to production with minimal maintenance.

If you later need a **native iOS POS** (register, cart, checkout), follow `android-pos/` — admin can stay as an embedded WebView there too.

## Tests

```bash
# Node portrait/orientation tests (CI-friendly) + XCTest on macOS
npm run test:ios-admin

# Or from repo root unit suite (includes admin-orientation + ios-admin-portrait)
npm test
```

After editing `lib/ios-admin-portrait-scripts.js`, sync bundled resources:

```bash
node scripts/sync-ios-portrait-resources.js
```
