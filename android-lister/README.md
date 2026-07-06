# Cloud Store Lister (Android / Kotlin)

Inventory lookup and list management for **Cloud Store 893**, ported from **ios-lister**.
Built with Kotlin + Jetpack Compose and the shared Lister palette (`ui/theme/`).

## Auth (Oracle OIDC)

No custom Android **intent URI** / app link is required. The WebView uses the same server redirect as **ios-lister** and **android-pos**:

`https://oci.cloudstore893.com/oauth/callback`

That URL must be registered in your Oracle IDCS app (same POS client). Flow:

1. WebView → `GET /oauth/login?client_kind=lister&register_id=lister-{deviceId}`
2. Oracle IdP login
3. Redirect → `/oauth/callback` → server sets `cashier_session` cookie
4. Redirect → `/?lister_signed_in=1` → app closes WebView and probes session

If the WebView stays **blank**, rebuild after pulling latest — WebView needs `domStorageEnabled` for Oracle pages, and the app now shows “Checking session…” instead of a blank WebView after redirect.


- **Oracle OIDC sign-in** — WebView → `/oauth/login?client_kind=lister` (no till / supervisor approval)
- **Input tab** — manual numpad + ML Kit barcode scanner
- **Results tab** — product detail card; add to named lists
- **Lists tab** — pull counts, CSV share, list operations (union, diff, split, sort, batch query)
- **Barcode normalization** — client-side EAN-13 / UPC variant retry (matches server + ios-lister)

## API wiring

| Endpoint | Use |
|----------|-----|
| `GET /oauth/login?client_kind=lister` | WebView OIDC sign-in |
| `GET /api/cashier/session` | Startup session probe |
| `POST /api/cashier/logout` | Sign out |
| `GET /api/inventory/lookup` | Product lookup by ID or barcode |

Register ID: `lister-{ANDROID_ID}` (sent on session probe).

## JDK for Gradle builds

Use **JDK 21 or 17**. **JDK 26** can fail with `JdkImageTransform` / `jlink`.

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
cd android-lister
./gradlew :app:assembleDebug
```

## Base URL (`API_BASE_URL`)

Baked into the APK at Gradle configure time (`BuildConfig.API_BASE_URL`):

1. `RELEASE_API_BASE_URL` if set
2. Private LAN IP (`LAN_IP` or `ipconfig en0`) → `http://192.168.x.x:3000/`
3. Default OCI → `https://oci.cloudstore893.com/`

```bash
# Local dev server on LAN
LAN_IP=192.168.1.10 ./gradlew :app:assembleDebug

# OCI prod
RELEASE_API_BASE_URL=https://oci.cloudstore893.com/ ./gradlew :app:assembleDebug
```

## Install on device

**Default (OCI prod)** — `./RebuildReinstall.sh` bakes `https://oci.cloudstore893.com/` into the APK and stops the Gradle daemon so `BuildConfig` refreshes:

```bash
./RebuildReinstall.sh
```

**Local dev** (`npm run dev:up` on your Mac):

```bash
USE_LOCAL=1 ./RebuildReinstall.sh
# or
LAN_IP=192.168.1.10 ./RebuildReinstall.sh
```

**One-liner** (env must be on the same command as the script, or exported):

```bash
RELEASE_API_BASE_URL=https://oci.cloudstore893.com/ ./RebuildReinstall.sh
```

Watch for `==> API_BASE_URL=https://oci.cloudstore893.com/` and the Gradle line
`[cloud-store-893] android-lister API_BASE_URL = https://oci.cloudstore893.com/`
before installing. The sign-in screen shows the host from `BuildConfig` (`oci.cloudstore893.com` for prod).

```bash
./gradlew :app:installDebug
```
