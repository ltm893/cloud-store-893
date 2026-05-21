# Cloud Store POS (Android / Kotlin)

Native Samsung-tablet cash register for **Cloud Store 893**, built with
Kotlin + Jetpack Compose. Theming: **Lister palette** (`ui/theme/`).

## Capabilities

- **Cashier login** — on-screen numpad + **Done**; PIN checked via `POST /api/cashier/unlock` (server `CASHIER_PIN` in `.env` / OCI container env)
- **☰ Menu** — show/hide status (connection, offline queue), **Admin** (in-app WebView → `/admin/`), **Lock**
- Barcode / product ID entry (`POST /api/cart`, `POST /api/cart/barcode`)
- Camera scanning (CameraX + ML Kit)
- Offline checkout queue — **Sync queued** in status panel (see caveats below)

## API wiring

| Endpoint | Use |
|----------|-----|
| `POST /api/cashier/unlock` | Login (`{ "pin": "…" }`) |
| `GET /api/products` | Loaded on unlock (not shown in UI) |
| `GET /api/customers` | Customer picker |
| `GET /api/cart` | Current sale |
| `POST /api/cart` / `POST /api/cart/barcode` | Add line |
| `DELETE /api/cart/:id` | Remove line |
| `POST /api/checkout` | Complete sale |
| `GET /api/sales/recent` | Fetched on refresh (not shown yet) |

## Base URL (`API_BASE_URL`)

Baked into the APK at **Gradle configuration** time (`BuildConfig.API_BASE_URL`):

1. `LAN_IP` env var if set
2. macOS `ipconfig getifaddr en0`, then `en1`
3. Fallback `10.0.0.122`

Watch the configure log: `[cloud-store-893] debug API_BASE_URL = http://…/`

```bash
# Mac on same Wi‑Fi as backend (npm run dev:up)
./RebuildReinstall.sh

# Or manually:
LAN_IP=$(ipconfig getifaddr en0) ./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

`RebuildReinstall.sh` detects `LAN_IP` from `en0`/`en1` (override with `LAN_IP=…`), builds debug, and installs via `adb`.

**Wrong URL symptoms:** `Failed to connect`, login **404** (server missing `/api/cashier/unlock` — redeploy Docker image), or **401** (wrong PIN).

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

- PIN entered via **number pad** (not soft keyboard).
- **Done** submits unlock to the server.
- Status line shows **Invalid PIN**, **Cannot reach server**, or **Server needs update (404)**.

## Sale screen layout

1. **Header** — ☰ menu, title
2. **Status card** (when menu → Show status) — API message, offline queue, **Sync queued**
3. **Middle** — scan field, **Scan** / **Add**, cart list | number pad
4. **Bottom** — totals, **Pay** → payment + **Complete Sale**

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
