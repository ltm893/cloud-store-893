# Cloud Store 893 — session handoff

Last updated: 2026-05-16

Use this file to resume work in a new session. Canonical setup details live in [README.md](README.md).

---

## Current state (what works)

| Area | Status |
|------|--------|
| **Web POS** (`/`) | Product grid, cart, checkout |
| **Admin** (`/admin/`) | CRUD on DB tables; PIN login (`ADMIN_PIN`) |
| **Tablet POS** | Numpad login → `POST /api/cashier/unlock`; sale flow; ☰ menu |
| **Local dev** | `npm run dev:up` + `.env` |
| **OCI** | Container + ADB; app at `terraform output app_url` |
| **Git** | Feature work on branch `dev` (pushed May 2026) |

**PINs (defaults):** `CASHIER_PIN=8930`, `ADMIN_PIN=8930` (or admin defaults to cashier). Set in `.env` locally; on OCI via `terraform/container.tf` (`cashier_pin`, `admin_pin` variables).

---

## Start developing (local)

```bash
cd /Users/ltm893/Dev/projects/cloud-store-893
cp .env.example .env          # set ORDS_BASE_URL, CASHIER_PIN, ADMIN_PIN
npm install
npm run sync-env              # after terraform output changes
npm run dev:up
```

- Web POS: http://127.0.0.1:3000/
- Admin: http://127.0.0.1:3000/admin/
- Tablet: `LAN_IP=$(ipconfig getifaddr en0) ./gradlew :app:installDebug` from `android-pos/`

---

## Start developing (OCI / tablet on cloud URL)

1. **Push latest image** (required after server changes):

   ```bash
   IMAGE=$(cd terraform && terraform output -raw ocir_image_path)
   docker buildx build --platform linux/arm64 -t "$IMAGE" .
   docker push "$IMAGE"
   ```

2. **Apply Terraform** (container only if `database.tf` has `ignore_changes`):

   ```bash
   cd terraform && terraform apply
   ```

3. **Note new `app_url`** — public IP may change when the container instance is recreated.

4. **Verify API:**

   ```bash
   APP=$(cd terraform && terraform output -raw app_url)
   curl -s -o /dev/null -w "%{http_code}\n" \
     -X POST "$APP/api/cashier/unlock" \
     -H 'Content-Type: application/json' -d '{"pin":"8930"}'
   ```

   Must be **200**. **404** = old image still running (push + apply again).

5. **Rebuild tablet APK** with new host:

   ```bash
   cd android-pos
   LAN_IP=<host-from-app_url> ./gradlew :app:assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

---

## API surface (Node → ORDS)

| Route | Purpose |
|-------|---------|
| `GET /api/products` | Product list (POS) |
| `GET/POST /api/cart`, `POST /api/cart/barcode`, `DELETE /api/cart/:id` | Cart |
| `POST /api/checkout` | Sale (requires `created_at` on ORDS `sales/` insert) |
| `GET /api/sales/recent` | Recent sales |
| `POST /api/cashier/unlock` | Cashier login (`{ pin }`) → session cookie |
| `GET /api/cashier/session`, `POST /api/cashier/logout` | Session check / sign-out |
| `GET /oauth/login`, `GET /oauth/callback` | POS IdP (when `IDP_POS_*` set) |
| `GET /oauth/admin/login`, `GET /oauth/admin/callback` | Admin IdP (when `IDP_ADMIN_*` set) |
| Cart, checkout, customers, sales | Require cashier session (products list is public) |
| `GET /api/admin/meta`, `GET/POST/PUT/DELETE /api/admin/:table` | Admin CRUD |
| `POST /api/admin/login`, `GET /api/admin/session` | Admin session cookie |

**Tables:** `products`, `customers`, `cart_items`, `sales`, `sale_items`, view `cart_view` — see `scripts/seed.sql`.

---

## Tablet POS (`android-pos/`)

- **Login:** Numpad + **Done** → server PIN check (not in APK).
- **Menu (☰):** Status panel, Admin (browser), Lock.
- **Add item:** Numpad digit(s) + **Add**, or **Scan** (camera), or full barcode string.
- **`API_BASE_URL`:** Gradle configure time — see build log; override with `LAN_IP=…`.
- **Theme:** Lister palette in `ui/theme/` — see [AGENTS.md](AGENTS.md).

### Offline queue caveat

- Queue stores **payment method + customer only**, not cart contents.
- **Sync queued** replays `POST /api/checkout` against the **current** server cart.
- Stale queue entries (from failed syncs while offline) — **clear app data** or reinstall; do not sync 16+ junk entries with items in cart.
- `flushOfflineQueue` runs on unlock and via **Sync queued**.

---

## Security / IdP roadmap

- **Phase 1 (in repo):** Cashier session cookies + optional ingress CIDR lockdown — see [docs/idp-setup.md](docs/idp-setup.md).
- **Phase 2 (OCI Console):** Separate Identity Domain + OIDC clients for POS and admin.
- **Start over (Level 1):** [docs/idp-level1-reset.md](docs/idp-level1-reset.md) — delete/recreate integrated apps only.

---

## Terraform notes

- **`database.tf`:** `lifecycle { ignore_changes = [cpu_core_count, …] }` — Always Free ADB rejects OCPU/storage updates; without this, `terraform apply` fails with 403.
- **`container.tf`:** env `CASHIER_PIN`, `ADMIN_PIN`, `ORDS_BASE_URL`, `PORT`.
- **Recreating container** changes `app_url` and `container_instance_ocid` outputs.
- Workload destroy: `./scripts/terraform-destroy-workloads.sh` (keeps compartment).

---

## Quick test checklist

1. `npm run dev:up` — `✅ ORDS is healthy`
2. `curl` cashier unlock → 200
3. Open `/admin/` — login, list products
4. Tablet: PIN **Done** → add product **1** → **Pay** → **Complete Sale**
5. `☰` → Admin opens in browser

---

## Known issues / follow-ups

- Admin + cashier use **shared PIN in env** — not production-grade on a public IP; add HTTPS and stronger auth later.
- Web POS has no cashier gate (intentional).
- Android `build/` artifacts can dirty `git status` — keep `.gitignore` tight.
- Optional: discard-queue button, cart snapshot in offline queue, receipt printing.

---

## Branch & repo

```bash
git branch --show-current   # expect dev
git log -1 --oneline
```

Remote: `origin` → `github.com/ltm893/cloud-store-893.git`
