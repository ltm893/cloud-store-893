# Cloud Store 893 — session handoff

Last updated: 2026-06-11

Use this file to resume work in a new session. Canonical setup details live in [README.md](README.md).

---

## Current state (what works)

| Area | Status |
|------|--------|
| **Web POS** (`/`) | Product grid, cart, checkout |
| **Admin** (`/admin/`) | CRUD on DB tables; PIN login (`ADMIN_PIN`) |
| **Tablet POS** | Numpad login; unified Pay panel; split tender cash/card; auto-finalize at zero balance |
| **Local dev** | `npm run dev:up` + `.env` |
| **OCI app URL** | **`https://oci.cloudstore893.com/`** (no `:3000`) — LB :443 → container :3000 |
| **HTTPS / TLS** | **Let's Encrypt** (public CA) via **OCI Certificates** → LB listener by cert OCID (see below) |
| **DNS** | `oci.cloudstore893.com` **delegated to OCI DNS** (Route 53 NS → OCI nameservers); A → LB IP |
| **Git** | Feature work on branch `dev` |

**PINs (defaults):** `CASHIER_PIN=8930`, `ADMIN_PIN=8930` (or admin defaults to cashier). Set in `.env` locally; on OCI via `terraform/container.tf` (`cashier_pin`, `admin_pin` variables).

---

## HTTPS / TLS (OCI)

Full guide: [docs/oci-load-balancer-https.md](docs/oci-load-balancer-https.md) (Let's Encrypt, certbot, OCI Certificates, diagrams).

### Done (production path)

| Step | Detail |
|------|--------|
| OCI Load Balancer | HTTPS :443 → backend HTTP :3000 |
| DNS delegation | Route 53 `oci` NS → OCI DNS zone `oci.cloudstore893.com` |
| Let's Encrypt cert | Issued via **certbot + dns-oci** (DNS-01); expires **2026-09-05** |
| OCI Certificates | Imported as **`oci-cloudstore893-com`** (ACTIVE) |
| LB listener | **`https`** listener uses **Certificates service OCID** (`lb_certificate_ocid` in Terraform) |
| Tablet | Debug APK: `https://oci.cloudstore893.com/`; `PocSelfSignedTls` only for legacy self-signed |

**Live resources (us-ashburn-1 / compartment `cloud-store`):**

| Resource | Value |
|----------|--------|
| Public URL | `https://oci.cloudstore893.com/` |
| LB public IP | `129.158.38.166` (`terraform output load_balancer_public_ip`) |
| LB OCID | `ocid1.loadbalancer.oc1.iad.aaaaaaaaprg2umooac3xuxvy375zkjbjb2pacf3kwerjqhcnuao3zkmb7b5q` |
| Certificate name | `oci-cloudstore893-com` |
| Certificate OCID | `ocid1.certificate.oc1.iad.amaaaaaa36usv6qaoaudedygsdmpusa3qdmhopypbgeiyny62k6dmw7xtx4q` |
| Certbot files (local, gitignored) | `certs/certbot/config/live/oci.cloudstore893.com/` |

**Verify (no `-k` needed):**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://oci.cloudstore893.com/api/build-info   # 200
./scripts/oci/verify-certbot-dns-oci.sh   # DNS + plugin pre-checks
```

---

## Cert-renew OCI Function — status (2026-06-10)

Automated renewal: **Resource Scheduler → OCI Function → certbot DNS-01 → deploy hook → OCI Certificates → LB picks up new version**.

### Deployed in OCI (Terraform `enable_cert_renew_function = true`)

| Resource | Value |
|----------|--------|
| Function OCID | `ocid1.fnfunc.oc1.iad.amaaaaaa36usv6qahg6ivfpb7znrd2mafn7tqe6yfv7vqfyx3n2ackgus7dq` |
| Application | `cert-renew-cloud-store` |
| Image | `iad.ocir.io/ideccm0ly8vq/cloud-store:cert-renew` |
| State bucket | `cloud-store-certbot-state` / object `certbot-state.tar.gz` |
| Function timeout | **300 s max** (OCI limit) |
| Memory | 512 MB |
| Resource Scheduler | `cert-renew-weekly` — cron `0 3 * * 0` (Sundays 03:00 UTC) |
| Schedule OCID | `ocid1.resourceschedule.oc1.iad.amaaaaaa36usv6qaqvnn663dcq5ig4gx7jegw2pllz6v33j5mx6fnhgsyxra` |
| Next run | `terraform output cert_renew_schedule_next_run` (e.g. 2026-06-14 03:00 UTC) |

**Validate (fast — recommended):**

```bash
./scripts/oci/invoke-cert-renew-function.sh --smoke-test   # ✅ green 2026-06-10
```

Smoke test restores state from Object Storage, rewrites Mac paths → `/tmp/certbot`, runs `certbot certificates`, confirms `dns-oci` plugin loads.

**Full staging simulation (slow, rate-limited):**

```bash
./scripts/oci/invoke-cert-renew-function.sh --dry-run
```

Certbot 5 **`renew --dry-run` always simulates a full DNS-01 challenge** (even when prod cert has 87 days left). Expect **~5–9 min** (120 s DNS propagation + ACME). After many test runs, staging may return `rateLimited: Service busy; retry later` — that still proves DNS/OCI IAM works; wait before retrying.

**Production renew** (no flags) is a no-op until ~30 days before expiry (~**Aug 2026**).

**Repo layout:**

| Path | Purpose |
|------|---------|
| `functions/cert-renew/` | Docker image: `func.py`, `renew.sh`, `deploy-oci-cert.sh`, `oci_rp.py`, `vendor/dns_oci.py` |
| `terraform/cert_renew_function.tf` | Function, bucket, dynamic group, IAM policies |
| `scripts/oci/deploy-cert-renew-function.sh` | Build (linux/amd64), push OCIR, `oci fn function update --force` |
| `scripts/oci/seed-certbot-state.sh` | Upload Mac `certs/certbot/` tarball to Object Storage |
| `scripts/oci/invoke-cert-renew-function.sh` | `--smoke-test`, `--dry-run`, `--force-renew` |

### Fixes applied 2026-06-09/10

| Issue | Fix |
|-------|-----|
| certbot/acme import errors | Pin `certbot==5.4.0` + `acme==5.4.0`; vendored `dns-oci` plugin |
| `oci` CLI in Functions | `oci_rp.py` (Python SDK + resource principal) |
| No `gzip` / `tar` in image | Python `tarfile`; skip `._*` / `.DS_Store` |
| Mac paths in renewal conf | `fix_renewal_paths()` after state restore |
| `renew` + `-d` invalid in certbot 5 | Separate `renew --cert-name` vs `certonly -d` |
| Deploy hooks on dry-run | Omit `--deploy-hook` when `DRY_RUN=1` |
| Staging pollution in bucket | Re-seed: `./scripts/oci/seed-certbot-state.sh` |

### Pick up next

1. **Commit** scheduler Terraform (if not yet pushed).
2. Optional: `--force-renew` after staging rate limit cools off (POC only).
3. **IdP** — confirm redirect URIs use `https://oci.cloudstore893.com/...`.

### Cert flow (summary)

```text
Resource Scheduler ──► OCI Function (cert-renew)   [weekly schedule live]
                           │
         restore/save ◄──► Object Storage (certbot-state.tar.gz)
                           │
Certbot ◄── DNS-01 TXT ──► OCI DNS (oci.cloudstore893.com)
     │
     ▼ deploy hook (deploy-oci-cert.sh → oci_rp.py cert-import)
OCI Certificates (oci-cloudstore893-com)
     │
     ▼ listener certificate_ids (cert OCID)
OCI Load Balancer :443
     │
     ▼ HTTP :3000 (VCN)
Node container
```

### Docker image notes (for maintainers)

- Base: `fnproject/python:3.11`; deps via `pip install --target /python/`.
- Entrypoint: `/python/bin/fdk /function/func.py handler`.
- **Do not** add `oci-cli` or unpinned `certbot`/`certbot-dns-oci` to `requirements.txt`.
- Rebuild always `--platform linux/amd64`.

### Not done yet (broader HTTPS)

1. **IdP** — confirm POS app redirect URIs are all `https://oci.cloudstore893.com/...`.

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

**Public URL:** `https://oci.cloudstore893.com/` — `./scripts/oci/confirm-public-url.sh` should print `https://…/`.

**Deploy guide (canonical):** [docs/oci-deploy.md](docs/oci-deploy.md) — code, env, DB schema, IdP, tablet APK, decision table, troubleshooting.

**Typical code push:**

```bash
./scripts/oci/redeploy-app-code.sh
./scripts/oci/redeploy-app-code.sh my-change-id   # optional BUILD_ID
```

**Network recovery after container replace:** [docs/oci-network-recovery.md](docs/oci-network-recovery.md).

---

## API surface (Node → ORDS)

| Route | Purpose |
|-------|---------|
| `GET /api/products` | Product list (POS) |
| `GET/POST /api/cart`, `POST /api/cart/barcode`, `DELETE /api/cart/:id` | Cart |
| `POST /api/checkout` | Sale, including split-tender payloads (requires `created_at` on ORDS inserts) |
| `GET /api/sales/recent` | Recent sales |
| `POST /api/cashier/unlock` | Cashier login (`{ pin }`) → session cookie |
| `GET /api/cashier/session`, `POST /api/cashier/logout` | Session check / sign-out |
| `GET /oauth/login`, `GET /oauth/callback` | POS IdP (when `IDP_POS_*` set) |
| `GET /oauth/admin/login`, `GET /oauth/admin/callback` | Admin IdP (when `IDP_ADMIN_*` set) |
| Cart, checkout, customers, sales | Require cashier session (products list is public) |
| `GET /api/admin/meta`, `GET/POST/PUT/DELETE /api/admin/:table` | Admin CRUD |
| `POST /api/admin/login`, `GET /api/admin/session` | Admin session cookie |

**Tables:** `products`, `customers`, `cart_items`, `sales`, `sale_items`, `sale_payments`, view `cart_view` — see `scripts/seed.sql`.

---

## Tablet POS (`android-pos/`)

- **Login:** Numpad + **Done** when PIN is allowed; **Sign in with Oracle** (WebView) when IdP / Model B is on; **Waiting for supervisor** screen polls until approved. Server PIN check (not in APK).
- **Menu (☰):** Show/hide status, find customer / keypad, unlink (when linked), sync/discard queue (when queued), Admin (browser), Lock.
- **Add item:** Numpad digit(s) + **Add**, or **Scan** (camera), or full barcode string.
- **Cash pay:** Split tender on **Pay** → amount numpad + **Cash** / **Card** / **CardOnFile** (when linked customer has card); auto-finalize at $0 balance.
- **`API_BASE_URL`:** Gradle configure time — see build log; override with `LAN_IP=…`.
- **Theme:** Lister palette in `ui/theme/` — see [AGENTS.md](AGENTS.md).

### Tablet POS UI layout (ASCII)

Colors (see `ui/theme/Color.kt`): page/drawer **cream** `#FAF3DF`; top bar **burgundy** `#872434`; content cards **teal tint** `#A8D5D1` @ 25%; numpad panel **cream**; numpad keys **light teal**; primary actions **dark teal** buttons with white label.

**Login** (full screen, cream page):

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                         Cashier Sign In                                    │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  PIN: ••••                                                           │  │
│  │  ┌────┬────┬────┐                                                    │  │
│  │  │ 1  │ 2  │ 3  │   (numpad keys: light teal, black digits)          │  │
│  │  ├────┼────┼────┤                                                    │  │
│  │  │ 4  │ 5  │ 6  │                                                    │  │
│  │  ├────┼────┼────┤                                                    │  │
│  │  │ 7  │ 8  │ 9  │                                                    │  │
│  │  ├────┼────┼────┤                                                    │  │
│  │  │ C  │ 0  │ ⌫  │                                                    │  │
│  │  └────┴────┴────┘                                                    │  │
│  │  [ Done ]  (teal)                                                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│  status line (Invalid PIN / server error)                                  │
└────────────────────────────────────────────────────────────────────────────┘
```

**Sale screen — default** (after unlock; right column = item numpad):

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ ☰ │        Cloud Store 893 POS                              │ v1.x       │  ← burgundy bar, cream text
├───┴──────────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ ┌────────────────────────────────┐ │
│ │ Scan / Add Id  [________________]   │ │ (optional) Status card         │ │
│ │ [ Scan ]  [ Add ]                   │ │  API status, offline queue     │ │
│ │─────────────────────────────────────│ │  Sync queued / Discard         │ │
│ │ Current Sale                        │ ├────────────────────────────────┤ │
│ │ Linked: Name              [Unlink]  │ │ ┌────┬────┬────┐               │ │
│ │ ┌─────────────────────────────────┐ │ │ │ 1  │ 2  │ 3  │  cream panel  │ │
│ │ │ cart lines (scroll)             │ │ │ ├────┼────┼────┤  teal keys    │ │
│ │ │  Name · qty · prices            │ │ │ │ 4  │ 5  │ 6  │               │ │
│ │ └─────────────────────────────────┘ │ │ ├────┼────┼────┤               │ │
│ │ Payments received (when checkout)   │ │ │ 7  │ 8  │ 9  │               │ │
│ └─────────────────────────────────────┘ │ │ ├────┼────┼────┤               │ │
│ │ teal-tint card                      │ │ │ C  │ 0  │ ⌫  │               │ │
│ ┌─────────────────────────────────────┐ └────────────────────────────────┘ │
│ │ Subtotal / tax / fees / TOTAL       │                                      │
│ │                          [ Pay ]    │                                      │
│ └─────────────────────────────────────┘                                      │
└────────────────────────────────────────────────────────────────────────────┘
     ↑ left ~flex                          ↑ right fixed width (PosNumpadWidth)
```

**Hamburger drawer** (slides over left; cream background):

```text
┌──────────────────────────┐
│ Menu                     │  ← burgundy title
│ ┌──────────────────────┐ │
│ │ Show status          │ │  black text, burgundy outline, no fill
│ ├──────────────────────┤ │
│ │ Find customer        │ │
│ ├──────────────────────┤ │
│ │ Unlink customer      │ │  (only when customer linked)
│ ├──────────────────────┤ │
│ │ Sync queued (n)      │ │  (only when queue > 0)
│ ├──────────────────────┤ │
│ │ Discard queue (n)    │ │
│ ├──────────────────────┤ │
│ │ Admin                │ │
│ ├──────────────────────┤ │
│ │ Lock                 │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```

**Right column — Find customer** (replaces numpad; menu → Find customer):

```text
┌────────────────────────────────┐
│ Find customer        [Keypad]  │
│ Linked: …            [Unlink]  │
│ Id or Name [_______________] │
│ ┌────────────────────────────┐ │
│ │ Customer Name              │ │  tap row → link immediately
│ │ email · phone              │ │  burgundy outline, transparent bg
│ ├────────────────────────────┤ │
│ │ …                          │ │
│ └────────────────────────────┘ │
└────────────────────────────────┘
```

**Right column — Payment** (after **Pay**; split tender):

```text
┌────────────────────────────────┐
│ [Back]              Payment    │
│ Sale total              $X.XX  │
│ Balance due             $X.XX  │
│ Amount entered            —    │
│ Give change / Still need       │
│                                │
│ [$due] [$5] [$10] [$20]        │  burgundy-outline quick amounts
│ ┌────┬────┬────┐               │
│ │ 1  │ 2  │ 3  │  compact numpad (. 0 ⌫ — no C)
│ ├────┼────┼────┤               │
│ │ 4  │ 5  │ 6  │               │
│ ├────┼────┼────┤               │
│ │ 7  │ 8  │ 9  │               │
│ ├────┼────┼────┤               │
│ │ .  │ 0  │ ⌫  │               │
│ └────┴────┴────┘               │
│ [ Cash ] [ Card ] [CardOnFile] │  teal buttons; CardOnFile if linked + on file
└────────────────────────────────┘
```

**Overlays:** camera **Scan** dialog; **CardOnFile** confirm (last 4); card charge **Processing** dialog (5s progress).

### Payment flow notes (2026-05-28)

- Payment flow is now unified under **Pay** in the right panel (no separate split tab).
- Cash and card can be applied in multiple partial payments until balance reaches zero.
- **Card** uses a 5-second progress dialog with `Sending $X.XX to Credit Terminal`; card payments are non-removable.
- **Cash** supports entered/tendered amounts, live change display, and auto-finalize when remaining balance reaches zero.
- The sale auto-completes once remaining balance is effectively zero; no extra **Finish sale** action is required.
- Active tendering locks cart item edits/scanning; back is disabled after any committed card payment.

### Android build note

- On macOS, use **JDK 21** for Android builds in this repo. JDK 26 still causes Gradle / Android toolchain failures.
- Example:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
export PATH="$JAVA_HOME/bin:$PATH"
./android-pos/gradlew -p android-pos :app:installDebug
```

### Offline queue caveat

- Queue stores **payment method + customer only**, not cart contents.
- **Sync queued** replays `POST /api/checkout` against the **current** server cart.
- Stale queue entries (from failed syncs while offline) — **clear app data** or reinstall; do not sync 16+ junk entries with items in cart.
- `flushOfflineQueue` runs on unlock and via **Sync queued**.

---

## Security / IdP roadmap

- **Phase 1 (in repo):** Cashier session cookies + optional ingress CIDR lockdown — see [docs/idp-setup.md](docs/idp-setup.md).
- **Phase 2 (OCI Console):** Separate Identity Domain + OIDC clients for POS and admin.
- **Phase 3 (feature branch `feature/cashier-supervisor-approval`):** IdP cashier login + **supervisor approval** before session — **steps 1–8 implemented** (server, web POS, admin panel, Android tablet). Living doc: [docs/cashier-supervisor-approval.md](docs/cashier-supervisor-approval.md). **Remaining:** OCI IdM group claims in console (step 9). Automated tests + CI: [docs/testing.md](docs/testing.md) (step 10).
- **Start over (Level 1):** [docs/idp-level1-reset.md](docs/idp-level1-reset.md) — delete/recreate integrated apps only.

---

## Terraform notes

- **`database.tf`:** `lifecycle { ignore_changes = [cpu_core_count, …] }` — Always Free ADB rejects OCPU/storage updates; without this, `terraform apply` fails with 403.
- **`container.tf`:** env `CASHIER_PIN`, `ADMIN_PIN`, `ORDS_BASE_URL`, `PORT`.
- **Recreating container** changes `app_url` and `container_instance_ocid` outputs; reserved IP must be **reattached** — `./scripts/oci/reattach-reserved-ip.sh` ([docs/oci-network-recovery.md](docs/oci-network-recovery.md)).
- Workload destroy: `./scripts/oci/terraform-destroy-workloads.sh` (keeps compartment).

---

## Quick test checklist

**Automated (repo root):**

```bash
npm test                              # unit only (fast, no ORDS)
npm run test:all                      # unit + auth + read-only API (needs ORDS in .env)
```

Covers cart validation (`POST /api/cart` unknown product → 404), session guards, and cashier identity helpers. Full matrix: [docs/testing.md](docs/testing.md).

**Manual smoke:**

1. `npm run dev:up` — `✅ ORDS is healthy`
2. `curl` cashier unlock → 200
3. Open `/admin/` — login, list products
4. Tablet: PIN **Done** → add product **1** → **Pay** → **Complete Sale** (rebuild APK with `USE_LOCAL=1` for local server)
5. `☰` → Admin opens in browser
6. OCI after code change: `./scripts/oci/redeploy-app-code.sh` then `curl -s "$(./scripts/oci/confirm-public-url.sh)/api/build-info"`

**Model B (supervisor approval, feature branch):** optional manual checks — not part of `dev:up`. See [docs/cashier-supervisor-approval.md](docs/cashier-supervisor-approval.md#testing-manual-today) and [End-to-end (web + admin + tablet)](docs/cashier-supervisor-approval.md#end-to-end-manual-web--admin--tablet). Automated suite: [docs/testing.md](docs/testing.md).

Quick Model B smoke (two terminals):

```bash
# Terminal 1 — server (flags must be on the Node process)
CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run dev:up

# Terminal 2 — automated HTTP checks
CASHIER_SUPERVISOR_APPROVAL=true npm run test:cashier-approval-session
CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run test:supervisor-routes
CASHIER_SUPERVISOR_APPROVAL=true CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR=true npm run test:cashier-approval-poll
```

Then manually: cashier signs in (web `/` or tablet **Sign in with Oracle**) → admin **Login approvals** → **Approve** → register loads.

---

## Git state (2026-06-10)

Branch **`dev`**. Cert-renew function committed; smoke-test verified green in OCI.

---

## Known issues / follow-ups

- Admin + cashier use **shared PIN in env** — HTTPS is live on OCI; stronger auth still TBD.
- **Cert-renew function** — deployed; **`--smoke-test` green**; full `--dry-run` works but is slow and may hit LE staging rate limits after repeated tests.
- Web POS has cashier gate + Model B waiting screen when supervisor approval is enabled.
- Android `build/` artifacts can dirty `git status` — keep `.gitignore` tight.
- Optional: discard-queue button, cart snapshot in offline queue, receipt printing.

### DB reset blocker (2026-05-26)

- Added `scripts/reset-db.sh` to run the destructive schema reset via SQLcl + ADB wallet instead of trying to execute `scripts/seed.sql` in bash.
- Last attempt failed waiting for ORDS: `ORDS not ready after 60 seconds`.
- We stopped here and should revisit later.
- Next time, start by checking ADB / ORDS health, then rerun:

```bash
scripts/reset-db.sh
```

- If ORDS is still slow to come up, inspect `terraform output -raw ords_base_url`, ADB status in OCI, and whether the ORDS endpoint is reachable before debugging the split-tender flow further.

### Cash rounding (TODO)

**Done (tablet UI):** Cash due, **Exact**, and change round **down** to **$0.05** (`roundToNickel` / `computeCashAmountDue` in `android-pos/.../CartTotals.kt`). Sale bar still shows the full register total; cash panel shows **Register total** vs **Cash due (no pennies)** when they differ.

**Not done — pick up later:**

- [ ] **`POST /api/checkout`** — when `paymentMethod === 'cash'`, compute tax-inclusive total (same formula as tablet), apply nickel rounding, persist on `sales` (e.g. `total`, `cash_due`, optional `cash_tendered` / `cash_change` / `register_total`).
- [ ] **ORDS / `sales` table** — columns or documented fields for cash-rounded amount vs pre-tax subtotal (today checkout stores **pre-tax** `subtotalPayable` only).
- [ ] **Web POS** — if cash tender UI is added, reuse same rounding; web cart today has no tax line like the tablet.
- [ ] **Admin / reports** — show cash-rounded total for cash sales; align with drawer/accounting.
- [ ] **Receipts / exports** — amount collected = nickel-rounded cash due, not raw register total.
- [ ] **Offline queue (tablet)** — optional: store tendered/rounded due if server will validate on sync.

Ref: `android-pos/README.md` (Cash — no pennies).

### Card terminal / payment pad (TODO)

**Today:** Tablet **Card** shows “Use Card Paid” then `POST /api/checkout` with `paymentMethod: "card"` only — **no** pin pad, auth code, or processor tie-in. Cash flow is integrated on the tablet; card is **manual / unintegrated**.

**There is no single global “POS → card pad” message format.** Under the hood: **EMV** (chip/tap), **ISO 8583** (auth on the processor network). At the register you usually integrate via a **terminal vendor SDK** or **gateway** (Stripe Terminal, Square, Adyen, Fiserv, etc.) or regional specs like **Nexo** / **OPI** where supported.

**Typical integrated flow (target architecture):**

```text
POS (tablet/Node) → SDK or local API → payment terminal → acquirer → card network
```

POS sends (conceptually): amount, currency, sale reference (`orderNumber`), optional tip — **not** raw track/chip data. Terminal returns: approved/declined, auth code, transaction id, masked PAN, card brand.

**Integration styles:**

| Style | Notes |
|-------|--------|
| **Fully / semi-integrated** | POS sends amount; customer pays on pad; result via API — preferred for PCI and reconciliation |
| **Unintegrated (current)** | Cashier runs amount on external pad; POS records card sale after the fact |

**Not done — pick up later:**

- [ ] **Choose stack** — processor + terminal (or cloud: Stripe Terminal / Square / Adyen) vs existing merchant hardware.
- [ ] **Node + tablet** — after approval, call checkout with `paymentMethod: "card"` plus stored `auth_code`, `transaction_id`, terminal ref (needs `sales` / API fields).
- [ ] **Replace “Use Card Paid”** — drive real amount to terminal; block Complete until approved/declined; handle voids/refunds policy.
- [ ] **Receipts / admin** — show auth code and masked card on sale history.
- [ ] **HTTPS** — required for many cloud terminal SDKs (see Next Steps in README).

### Split tender (implemented)

**Approved v1 behavior:**

- Allow multiple tenders in a single sale.
- Tender order does **not** matter.
- If an entered amount is less than the amount still due, allow another payment entry using either **cash** or **card**.
- After any partial payment, show:
  - amount due
  - amount received
  - balance remaining
- Persist a **real payment breakdown**, not just one summary `paymentMethod`.
- Mixed tender math should use the full register total. Example: total `$5.29`, cash `$2.00`, remaining card balance `$3.29`.
- Accepted tenders should stay locked once added unless there is an explicit remove/edit step.

**Implementation status in repo:**

- Android UI/state changes are implemented in:
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/PosScreen.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/PosViewModel.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/CheckoutUiState.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/CheckoutPaymentPanel.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/CheckoutPaymentLogic.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/CashInput.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/ui/PosNumberPad.kt`
- Shared checkout payload / offline queue changes are implemented in:
  - `android-pos/app/src/main/java/com/cloudstore/pos/data/PosApi.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/data/PosModels.kt`
  - `android-pos/app/src/main/java/com/cloudstore/pos/data/OfflineQueueStore.kt`
- Backend checkout changes are implemented in `server.js`.
- Schema/admin support for `sale_payments` is in:
  - `scripts/seed.sql`
  - `lib/admin-tables.js`
- Kotlin compile check is passing after the checkout refactor (`:app:compileDebugKotlin`).

**Likely files for split-tender work:**

- `android-pos/app/src/main/java/com/cloudstore/pos/ui/PosScreen.kt`
- `android-pos/app/src/main/java/com/cloudstore/pos/ui/PosViewModel.kt`
- `android-pos/app/src/main/java/com/cloudstore/pos/data/PosApi.kt`
- `android-pos/app/src/main/java/com/cloudstore/pos/data/PosModels.kt`
- `android-pos/app/src/main/java/com/cloudstore/pos/data/OfflineQueueStore.kt`
- `server.js`
- `scripts/reset-db.sh`
- `scripts/seed.sql`
- likely `lib/admin-tables.js` if payment rows need admin visibility

**Next resume steps:**

1. Run end-to-end tests against local/OCI with real DB state (`sale_payments` inserts + admin visibility).
2. Decide whether to move remaining checkout orchestration entirely behind ViewModel intents.
3. Add unit tests for payment logic helpers (`CheckoutPaymentLogic.kt`, cash input parsing).
4. Keep card terminal integration as a separate follow-up (current card flow remains simulated/manual).

---

## Branch & repo

```bash
git branch --show-current   # feature/cashier-supervisor-approval (Model B) or dev
git log -1 --oneline
```

Remote: `origin` → `github.com/ltm893/cloud-store-893.git`
