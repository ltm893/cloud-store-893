# Cloud Store POS (Android / Kotlin)

Native Samsung-tablet cash register app for **Cloud Store 893**, built with
Kotlin + Jetpack Compose. Theming: **Lister palette** (`ui/theme/`).

## Capabilities

- Cashier PIN on launch (`CASHIER_PIN` in Gradle `BuildConfig`, default `8930`)
- Barcode / product ID entry (`POST /api/cart`, `POST /api/cart/barcode`)
- Camera scanning (CameraX + ML Kit)
- Offline checkout queue with **Sync queued** (from **Show status**)

## API wiring

The app talks to the Node backend:

- `GET /api/products`
- `GET /api/cart`
- `POST /api/cart`
- `DELETE /api/cart/:id`
- `POST /api/checkout`
- `GET /api/sales/recent`

## Base URL (`API_BASE_URL`)

Do **not** hardcode the tablet URL in source for local dev. Gradle sets
`BuildConfig.API_BASE_URL` at **configuration** time:

1. Environment variable `LAN_IP` (if set)
2. macOS `ipconfig getifaddr en0`, then `en1`
3. Fallback `10.0.0.122` so non-mac CI still builds

Watch the configure log:

`[cloud-store-893] debug API_BASE_URL = http://…/`

The **release** build type uses `RELEASE_API_BASE_URL` when set, otherwise the
same detected dev URL.

```bash
LAN_IP=192.168.1.50 ./gradlew :app:assembleDebug
RELEASE_API_BASE_URL=https://api.example.com/ ./gradlew :app:assembleRelease
```

## Run on a tablet (same LAN as the Mac)

1. From repo root: `npm run dev:up` (or `node server.js` on port 3000).
2. Tablet Wi-Fi same as the Mac; Mac firewall allows TCP **3000** if needed.
3. Build and install debug (USB debugging on, device authorized):

   ```bash
   cd android-pos
   ./gradlew :app:assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

   Or `./gradlew :app:installDebug` when a single device is the default.

## UI layout (three horizontal bands)

1. **Header** — Title **“Cloud Store 893 POS”** centered; **Show status** toggles
   connection text, offline queue + **Sync queued**, and **Lock**.
2. **Middle** — Left: scan field, **Scan** / **Add**, **Current Sale** list.
   Right: number pad in a card using **half** the column height (top-aligned).
3. **Bottom** — Left: sale totals and **Pay**. After **Pay**, payment picker
   (compact) and **Complete Sale** sit in the **right** column under the pad.

The main screen applies **`navigationBarsPadding()`** so pay controls clear the
system gesture area with **edge-to-edge** enabled in `MainActivity`.

## Release vs debug

**Debug** APKs are debug-signed and fine for personal tablets and iteration.

**Release** requires a `signingConfig` in `app/build.gradle.kts`; otherwise
Gradle emits an **unsigned** APK that `adb install` will reject. Add signing
before distributing or publishing.

## Open in Android Studio

Open the `android-pos` folder, sync Gradle, run on an emulator or device.
Emulator loopback: use `LAN_IP=10.0.2.2` if the backend runs on the host
machine from the emulator’s perspective.
