# Agent instructions — cloud-store-893

## Color and theming (Android POS)

- **Single source of truth:** `android-pos/app/src/main/java/com/cloudstore/pos/ui/theme/`
  - `Color.kt` — brand hex values (Lister-aligned palette)
  - `Theme.kt` — `CloudStorePosTheme` + `lightColorScheme` / `darkColorScheme` mapping
  - `Type.kt` — shared typography

- **Prefer semantic colors in UI:** In Compose screens and components, use
  `MaterialTheme.colorScheme.*` and `MaterialTheme.typography.*`. Avoid scattering
  `Color(0xFF…)` literals in feature code unless there is a deliberate, documented
  exception.

- **Root / surfaces:** Respect Material roles — e.g. full-screen chrome uses
  `colorScheme.background`; cards and elevated panels use `surface` /
  `surfaceVariant` as appropriate. Do not repurpose tokens in ways that confuse
  “page” vs “card” hierarchy without discussion.

### When the user asks for a color change

1. **Default:** Implement by updating `Color.kt` and/or the `ColorScheme` mapping in
   `Theme.kt`, then use existing semantic slots in composables.

2. **If the request would override or break the scheme** — for example:
   - hard-coding colors in a screen that duplicate or contradict theme tokens,
   - using `surface` where `background` (or vice versa) is correct for hierarchy,
   - one-off colors that won’t exist in dark mode,
   - changes that likely hurt contrast or accessibility,

   **stop and notify the user** before implementing. Offer: (A) adjust the shared
   theme so the app stays coherent, or (B) an explicit documented exception in code
   if they insist.

3. **Do not** silently fragment the palette across many files.

## Other notes

- **Session handoff:** [CONTENTS.md](CONTENTS.md) — current state, APIs, OCI redeploy, tablet caveats.
- **Local dev:** `npm run dev:up` from repo root; `npm run sync-env` after infra
  changes that alter ORDS URL. See `README.md`.
- **Env:** `.env` — `ORDS_BASE_URL`, `CASHIER_PIN`, `ADMIN_PIN` (see `.env.example`).
- **Admin:** `/admin/` + `lib/admin-*.js`; PIN session cookie.
- **Tablet builds:** `android-pos` Gradle sets `API_BASE_URL` at configure time;
  override with `LAN_IP=…`. Cashier PIN is server-side (`POST /api/cashier/unlock`).
- **OCI code updates:** `docker push` then `terraform apply`; 404 on unlock = stale image.
