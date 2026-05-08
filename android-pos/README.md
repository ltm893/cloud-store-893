# Cloud Store POS (Android / Kotlin)

Native Samsung-tablet cash register app built with Kotlin + Jetpack Compose.

## Current POS capabilities

- Cashier PIN gate on launch (`CASHIER_PIN` in Gradle build config)
- Barcode entry flow (`POST /api/cart/barcode`)
- Camera barcode scanning (CameraX + ML Kit)
- Offline checkout queue (failed checkout attempts are stored locally and can be synced)

## API wiring

The app talks to the existing Node backend:

- `GET /api/products`
- `GET /api/cart`
- `POST /api/cart`
- `DELETE /api/cart/:id`
- `POST /api/checkout`
- `GET /api/sales/recent`

Base URL is set in `app/build.gradle.kts`:

```kotlin
buildConfigField("String", "API_BASE_URL", "\"http://10.0.2.2:3000/\"")
buildConfigField("String", "CASHIER_PIN", "\"8930\"")
```

## Run locally

1. Start backend:
   - From repo root: `node server.js`
2. Open `android-pos` in Android Studio.
3. Let Android Studio sync Gradle.
4. Run on emulator or Samsung tablet.

## Samsung tablet network setup

If app runs on a physical Samsung device, `10.0.2.2` will not work.
Use your Mac LAN IP instead, for example:

```kotlin
buildConfigField("String", "API_BASE_URL", "\"http://192.168.1.12:3000/\"")
```

Then ensure:

- tablet and backend host are on the same Wi-Fi
- firewall allows inbound `3000`
- backend binds on host (default Express setup is fine for local network testing)
