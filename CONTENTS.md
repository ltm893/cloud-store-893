# Cloud Store 893 - Resume Notes

Last updated: 2026-05-10

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

- Cashier PIN screen (`8930`).
- Single-screen POS (Compose) with **Lister-palette theme** in
  `android-pos/.../ui/theme/` (Burgundy / Dark Teal / Snow / Light Cyan /
  Light Rose; dark-mode variants included).
- Layout (post-rework):
  - Header: "Cloud Store POS" + status line.
  - Left card (`weight(1f)`): scan/ID input field, then a row with **Scan**
    and **Add** buttons, then **Current Sale** list, total, payment picker,
    and Complete Sale button.
  - Right column: **Number Pad** in a top-aligned card taking ~2/3 of the
    column height, with empty space below.
- Input dispatch: numeric input ≤ 6 digits hits `POST /api/cart {productId}`;
  longer values hit `POST /api/cart/barcode {barcode}`. Camera scanner still
  works for real barcodes.
- Single-line text field with `ImeAction.Done`; pressing Enter (or Done on
  the soft keyboard) submits the same way the **Add** button does. The field
  is `readOnly = true` so the system keyboard does not pop — the on-screen
  number pad is the typing surface.
- `API_BASE_URL` is now **auto-detected** at Gradle configuration time using
  `ipconfig getifaddr en0` (fallback `en1`). Override with
  `LAN_IP=… ./gradlew :app:installDebug` or
  `RELEASE_API_BASE_URL=… …` for release builds. No more hand-editing the
  hostname in `build.gradle.kts`.

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
6. **Complete Sale**.
7. Toggle Wi-Fi off, complete another sale (queues offline).
8. Toggle Wi-Fi back on; tap **Sync queued**.

## Housekeeping (open follow-ups)

These were noticed during the May 10 commit but deferred:

1. **`.gitignore` gaps for the Android module.** Several
   build/IDE-state directories are currently tracked and mutate on every
   build, polluting `git status`:
   - `android-pos/.gradle/`
   - `android-pos/.idea/` (caches/, deploymentTargetSelector.xml at minimum)
   - `android-pos/app/build/`
   - `android-pos/build/`

   Fix: add a proper Android `.gitignore`, then
   `git rm -r --cached <path>` for each of the above and commit.

2. **`scripts/terraform.tfstate`** — stray Terraform state file in
   `scripts/`. The real state lives in `terraform/`; this looks like a
   leftover from a script run. Verify it isn't referenced by anything and
   delete.

3. **`package-lock.json`** drifted to add `dotenv` even though `dotenv` was
   already in `package.json`. A single `npm install` will refresh it; commit
   that separately so it doesn't bundle with feature work.

4. **`scripts/install-sqlcl.sh`** is untracked but referenced in `README.md`.
   Decide whether to commit it or remove the README reference.

5. **`scripts/deploy.sh`** has uncommitted changes from a prior session
   (added `find_sqlcl` helper). Review and commit or revert separately —
   not bundled with current feature work.

## Suggested next work

- Add a user-friendly error banner on the tablet when the backend is
  unreachable (currently shows "Add failed: …" status text).
- Beep/vibration on successful barcode scan for cashier feedback.
- Replace hardcoded PIN with secure auth storage
  (e.g. `cashiers` table in ADB with hashed PINs + `/api/auth/pin`).
- Receipt screen / print export after Complete Sale.
- Optional: re-introduce a "Recent Sales" panel (was removed during the
  number-pad layout rework).
- Optional: extend `dev-up.sh` to auto-start a stopped ADB via OCI CLI.

## Branch & commit pointers

- Active branch: `feature/kotlin-tablet-pos` (ahead of `main`).
- Last commit: `Add local dev tooling and refresh tablet POS UI with number
  pad`.
- Push: `git push origin feature/kotlin-tablet-pos`.
