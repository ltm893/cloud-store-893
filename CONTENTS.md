# Cloud Store 893 - Resume Notes

Last updated: 2026-05-11

## Where we left off

- Local dev tooling is in place. After a fresh deploy, the canonical "start
  developing" sequence is:

  ```bash
  cd /Users/ltm893/Dev/projects/cloud-store-893
  ./scripts/deploy.sh   # only when cloud is missing/destroyed
  npm run sync-env      # sync .env's ORDS_BASE_URL from terraform output
  npm run dev:up        # preflight + node --watch server.js
  ```

- `dev-up.sh` probes ORDS health (`/metadata-catalog/`) before starting the
  Node tier. It distinguishes "ADB stopped" (no response), "ADB up but ORDS
  schema not enabled" (404), and "healthy" (200), and prints the LAN URL the
  tablet should target.
- `oci-costs.sh` reports OCI spend (defaults to month-to-date, grouped by
  service). Always Free tier is currently $0.

## Tablet POS app — current state

- Cashier PIN screen (`8930` via `BuildConfig`).
- **Lister-palette** Compose theme in `android-pos/.../ui/theme/` (burgundy,
  dark teal, snow, light cyan / light rose; dark variants).
- **Layout (three bands):**
  1. **Header** — **“Cloud Store 893 POS”** centered; **Show status** /
     **Hide status** reveals status text, offline queue + **Sync queued**, and
     **Lock**.
  2. **Middle** — Left card: scan/ID field (read-only), **Scan** + **Add**,
     **Current Sale** list. Right column (`360.dp`): number pad in a card using
     **half** the column height (top-aligned).
  3. **Bottom** — Left card: **Sale totals** + **Pay**. After **Pay**, the
     compact payment picker and **Complete Sale** move to the **bottom-right**
     column (under the pad column).
- **Scan** opens CameraX + ML Kit; **Add** uses the same dispatch as the pad.
- Numeric input ≤ 6 digits → `POST /api/cart {productId}`; longer values →
  `POST /api/cart/barcode {barcode}`.
- `API_BASE_URL` is set at **Gradle configuration** (`ipconfig getifaddr en0` /
  `en1`, or `LAN_IP`). See root `README.md` and `android-pos/README.md`.
- Install loop: `./gradlew :app:assembleDebug` then
  `adb install -r app/build/outputs/apk/debug/app-debug.apk` (debug is enough
  for a personal tablet until signing is configured for release).

## Backend / API status

- `/api/products`, `/api/cart`, `/api/cart/barcode`, `/api/cart/:id`,
  `/api/checkout`, `/api/sales/recent` all live.
- Tables: `products`, `cart_items`, `sales`, `sale_items`, plus
  `cart_view` (joins `cart_items` + `products` for the cart endpoint).
- Foreign keys: `cart_items.product_id → products.id`,
  `sale_items.product_id → products.id`.
- ORDS schema enablement is part of `seed.sql` (steps 6–11). If
  `npm run dev:up` reports HTTP 404 from `/metadata-catalog/`, paste the
  ORDS-only PL/SQL block (or the full `seed.sql`) into Database Actions to
  re-enable the REST endpoints.

## Quick test checklist

1. `npm run dev:up` from the project root — confirm `✅ ORDS is healthy`.
2. Launch the app on the tablet, enter PIN `8930`.
3. On-screen number pad: type `3`, press **Add** → "Cloud Architecture
   Poster" lands in Current Sale.
4. Type `100000000001`, press **Add** → "OCI Foundations Study Guide" lands
   in cart (barcode lookup path).
5. Press **Scan** → camera dialog opens; scan a printed barcode.
6. **Pay** → choose payment on the right → **Complete Sale**.
7. **Show status** → toggle Wi-Fi off, complete another sale (queues offline).
8. Wi-Fi back on → **Sync queued**.

## Housekeeping (open follow-ups)

These were noticed during earlier work but may still apply — verify in git:

1. **`.gitignore` gaps for the Android module.** Build/IDE artifacts under
   `android-pos/` can pollute `git status`. Add a proper Android `.gitignore`,
   then `git rm -r --cached` for tracked build dirs if needed.

2. **`scripts/terraform.tfstate`** — stray state file under `scripts/` vs
   canonical `terraform/`. Confirm unused and remove if so.

3. **`package-lock.json`** — refresh with `npm install` when dependencies
   change; commit separately from feature work when possible.

4. **`scripts/install-sqlcl.sh`** — ensure it is committed if README references
   it.

5. **`scripts/deploy.sh`** — review any local edits vs `main` and commit when
   ready.

## Suggested next work

- User-visible error banner when the backend is unreachable (beyond status text).
- Beep/vibration on successful barcode scan.
- Replace hardcoded PIN with secure auth (e.g. hashed PINs in ADB).
- Receipt / print after **Complete Sale**.
- Optional: **Recent Sales** panel; optional `dev-up.sh` ADB auto-start via OCI CLI.

## Branch & commit pointers

- Confirm active branch and last commit with `git branch --show-current` and
  `git log -1 --oneline`.
- Feature work has lived on `feature/kotlin-tablet-pos` in the past; push
  target is typically `git push origin <branch>`.
