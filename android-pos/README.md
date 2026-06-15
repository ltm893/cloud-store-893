# Cloud Store POS (Android / Kotlin)

Native Samsung-tablet cash register for **Cloud Store 893**, built with
Kotlin + Jetpack Compose. Theming: **Lister palette** (`ui/theme/`).

## Capabilities

- **Cashier login** — on-screen numpad + **Done** when PIN is allowed; **Sign in with Oracle** (WebView → `/oauth/login?client_kind=tablet`) when IdP / Model B is on; supervisor approval waiting screen with poll + cancel
- **☰ Menu** — **Show status** (API message + offline queue), **Find customer**, **Admin**, **Sign out**, **Close till**
- Barcode / product ID entry (`POST /api/cart`, `POST /api/cart/barcode`)
- Camera scanning (CameraX + ML Kit)
- Offline checkout queue — **Sync queued** in status panel (see caveats below)

## API wiring

| Endpoint | Use |
|----------|-----|
| `POST /api/cashier/unlock` | Login (`{ "pin": "…" }`) — **403** when Model B supervisor approval is on |
| `GET /api/cashier/session` | Startup probe; pending / IdP flags |
| `GET /api/cashier/approval/status` | Poll while waiting for supervisor |
| `POST /api/cashier/approval/cancel` | Cancel pending login |
| `GET /oauth/login?client_kind=tablet` | WebView OIDC sign-in (Model B) |
| `GET /api/products` | Loaded on unlock (not shown in UI) |
| `GET /api/customers` | Customer picker |
| `GET /api/cart` | Current sale |
| `POST /api/cart` / `POST /api/cart/barcode` | Add line |
| `DELETE /api/cart/:id` | Remove line |
| `POST /api/checkout` | Complete sale |
| `GET /api/sales/recent` | Fetched on refresh (not shown yet) |

## JDK for Gradle builds

Use **JDK 21 or 17** (e.g. Temurin). **JDK 26** fails with `JdkImageTransform` / `jlink` during `:app:compileDebugJavaWithJavac`.

`RebuildReinstall.sh` sets `JAVA_HOME` automatically when possible. Otherwise:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
./gradlew :app:assembleDebug
```

## Base URL (`API_BASE_URL`)

Baked into the APK at **Gradle configuration** time (`BuildConfig.API_BASE_URL`):

1. `RELEASE_API_BASE_URL` if set (`RebuildReinstall.sh` sets `https://oci.cloudstore893.com/` for OCI)
2. Private LAN IP (`LAN_IP` or `ipconfig en0`) → `http://192.168.x.x:3000/`
3. Default OCI → `https://oci.cloudstore893.com/` (HTTPS LB, **no** `:3000`)

Watch the configure log: `[cloud-store-893] API_BASE_URL = https://…/`

```bash
# OCI cloud (HTTPS)
./RebuildReinstall.sh

# Local Mac dev (npm run dev:up)
USE_LOCAL=1 ./RebuildReinstall.sh
# or: LAN_IP=192.168.1.10 ./RebuildReinstall.sh
```

`RebuildReinstall.sh` builds debug and installs via `adb`. **Rebuild required** after changing the API host — the URL is compiled in.

**Wrong URL symptoms:** `Failed to connect`, login **404** (server missing `/api/cashier/unlock` — redeploy Docker image), or **401** (wrong PIN).

**OCI self-signed LB cert:** `generate-lb-tls.sh` uses a self-signed cert. Browsers may warn; the **debug APK** trusts it automatically (`PocSelfSignedTls`, debug builds only). For production, install a public CA cert on the OCI load balancer instead.

**PIN works on Mac but add-to-cart returns 401 on tablet:** the APK must target your Mac’s **current** Wi‑Fi IP (not `localhost`). Rebuild with the IP shown by `npm run lan-url` or `scripts/dev-up.sh`, then reinstall:

```bash
LAN_IP=$(ipconfig getifaddr en0) ./RebuildReinstall.sh
```

Confirm the status line after **Done** does not say “Sign-in did not persist”. Mac browser and tablet must hit the **same** Node server (`dev-up` on your Mac, not only OCI).

Changing `CASHIER_PIN` only requires updating `.env` (local) or Terraform/container env (OCI) and restarting Node — **no APK rebuild**.

## Sales tax and sales fee

Rates are read from **`pos.properties`** at Gradle configure time and baked into the APK
(`BuildConfig.POS_TAX_RATE`, `BuildConfig.POS_SALES_FEE_RATE`). Use **decimal fractions**, not
percent labels — e.g. `pos.tax.rate=0.0825` for 8.25%.

```properties
pos.sales.fee.rate=0.0
pos.tax.rate=0.0825
```

Copy `pos.properties.example` if you need a starting point. After editing, rebuild and reinstall:

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Tax is computed on the tablet only (pre-tax payable + sales fee); the server still stores
pre-tax line totals.

## Login screen

- PIN entered via **number pad** (not soft keyboard). Size: `PosLayoutMetrics.kt` (`PosNumpadColumnWidth`, `PosNumpadCardHeight`, …).
- **Oracle sign-in** uses a WebView; Samsung **keyboard size** in Settings often has no effect in **landscape**. Page zoom: `PosWebViewTextZoomPercent` in `ui/PosWebView.kt` (default 140%).
- **Done** submits unlock to the server.
- Status line shows **Invalid PIN**, **Cannot reach server**, or **Server needs update (404)**.

## Sale screen layout

Box diagrams (login, sale, drawer, customer find, payment) with color notes: [CONTENTS.md § Tablet POS UI layout (ASCII)](../CONTENTS.md#tablet-pos-ui-layout-ascii).

1. **Header** — ☰ menu, title, version (burgundy bar)
2. **Status card** (☰ → **Show status**) — API message, offline queue, **Sync queued**
3. **Middle** — scan field, **Scan** / **Add**, cart (+ payments list during checkout) | right slot: status (optional) + numpad **or** customer find **or** payment panel
4. **Bottom** — totals, **Pay** → split tender on right (amount numpad, **Cash** / **Card** / **CardOnFile**); sale completes when balance is $0

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ ☰ │        Cloud Store 893 POS                              │ v1.x       │
├───┴──────────────────────────────────────────────────────────────────────────┤
│ ┌───────────────────────────────┐ ┌────────────────────────────────────┐ │
│ │ Scan / Add Id, Scan, Add        │ │ Status (optional)                  │ │
│ │ Current Sale · cart lines       │ │ Numpad | Find customer | Payment   │ │
│ └───────────────────────────────┘ └────────────────────────────────────┘ │
│ ┌───────────────────────────────┐                                          │
│ │ Totals · [ Pay ]              │                                          │
│ └───────────────────────────────┘                                          │
└────────────────────────────────────────────────────────────────────────────┘
```

### Cash — no pennies + change

1. **Pay** → choose **Cash** (right panel becomes cash mode).
2. Enter **cash received** on the number pad (or tap **Exact** or the three bill shortcuts — e.g. due **$4.50** → **$5**, **$10**, **$20**).
3. **Give change** updates live; **Complete Sale** when enough cash was entered.

Cash due and change use the total rounded **down** to the nearest **$0.05** (e.g. $19.06 → $19.05, $19.08 → $19.05). Card/Mobile use the exact register total.

`navigationBarsPadding()` keeps pay controls above the gesture bar.

## Offline queue

- Failed **Complete Sale** (network down) enqueues `{ paymentMethod, customerId }` only.
- **Sync queued** calls checkout once per queued row against the **current** server cart.
- To clear a bad queue: Android **Settings → Apps → Cloud Store POS → Clear data**, or reinstall.

## Release vs debug

**Debug** is fine for a personal tablet. **Release** needs `signingConfig` in `app/build.gradle.kts`.

## Open in Android Studio

Open the `android-pos` folder, sync Gradle, run on device or emulator.

Emulator → host machine: `LAN_IP=10.0.2.2 ./gradlew :app:installDebug`
