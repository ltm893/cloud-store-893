# Scripts — cloud-store-893

Operational scripts for local dev, database, tests, iOS builds, TLS, and OCI deploy.

**Layout (phased reorg):** scripts are grouped by purpose. Old paths at `scripts/<name>` remain as **compatibility wrappers** (shell) or **symlinks** (SQL) that forward to the new location. Prefer the paths in the tables below; wrappers may be removed in a future release.

```
scripts/
├── README.md           # this file
├── lib/                # shared helpers (http-test-lib, test-report)
├── dev/                # local Mac workflow
├── db/                 # ADB schema, seed, migrations, backfills
├── test/               # unit/integration smoke runners
├── ios/                # iOS local config + TestFlight + XCTest
├── tls/                # self-signed certs (local + LB POC)
├── tools/              # one-off utilities
├── oci/                # OCI deploy, container, network, certs (see docs/oci-deploy.md)
│   └── idp/            # Dev IdP bootstrap — scripts/oci/idp/README.md
└── docker-entrypoint.sh
```

OCI scripts are documented in [docs/oci-deploy.md](../docs/oci-deploy.md) and [docs/oci-dev-environment.md](../docs/oci-dev-environment.md). Test layers: [docs/testing.md](../docs/testing.md).

---

## Dev (`scripts/dev/`)

| Script | One line |
|--------|----------|
| `up.sh` | Preflight ORDS, print tablet URL, start `node --watch server.js` (`npm run dev:up`) |
| `sync-env.sh` | Rewrite `.env` `ORDS_BASE_URL` from prod Terraform output (`npm run sync-env`) |
| `sync-env-dev.sh` | Same for `.env.dev` from dev Terraform state |
| `update-idp-redirects.sh` | Register local LAN/localhost OAuth redirect URIs in Oracle IDCS |
| `adb-wifi.sh` | Helper for Android tablet ADB over Wi‑Fi |

---

## Database (`scripts/db/`)

| Script | One line |
|--------|----------|
| `seed.sql` | Full ADB schema, ORDS endpoints, sample products (canonical bootstrap) |
| `reset-db.sh` | Run `seed.sql` against live ADB via SQLcl (destructive) |
| `truncate-shift-auth-tables.sh` | Clear till/session approval test data (keeps products/sales) |
| `truncate-shift-auth-tables.sql` | SQL used by truncate script |

### Migrations (`scripts/db/migrate/`)

| Script | One line |
|--------|----------|
| `migrate-login-approval-till.sh` | Apply till columns migration + refresh ORDS (`npm run migrate-db:till`) |
| `migrate-login-approval-till.sql` | SQL for till columns on `login_approval_requests` |
| `migrate-pos-sessions-tills.sql` | Migrate legacy register_shifts schema to pos_sessions + tills |
| `migrate-sales-cash-rounding.sql` | Add nickel cash rounding columns to `sales` |
| `enable-inventory-ords.sql` | Expose inventory tables/views to ORDS after partial seed |

### Backfills (`scripts/db/backfill/`)

| Script | One line |
|--------|----------|
| `seed-inventory-backfill.sql` | Backfill `product_inventory` on existing ADB |
| `seed-tax-exempt-backfill.sql` | Add `tax_exempt` column + refresh `cart_view` |
| `seed-bulk-inventory-migrate.sql` | Kitchen bulk + drink consumption on existing DB |

---

## Tests (`scripts/test/`)

| Script | One line |
|--------|----------|
| `run-tests.sh` | Unit tests + optional integration + summary report (`npm test`) |
| `run-integration-tests.sh` | Ephemeral server + auth/API/inventory smoke tests |
| `test-api-curl.sh` | curl smoke tests for all `/api` routes |
| `test-auth-protection.sh` | Verify cashier/admin routes require sessions |
| `test-inventory-api.sh` | Inventory fields, stock 409s, checkout depletion |
| `test-model-b-session.sh` | Model B session flags + PIN blocked when approval required |
| `test-supervisor-routes.sh` | Admin login-approval list/approve/deny routes |
| `test-cashier-approval-session.sh` | Pending cookie + `/api/cashier/session` (Model B) |
| `test-cashier-approval-poll.sh` | Poll → approve → session cookie E2E (Model B) |
| `test-login-approval-lib.js` | Smoke-test `lib/login-approval.js` against live ORDS |
| `create-test-pending-approval.js` | Insert pending approval row for supervisor route tests |

---

## iOS (`scripts/ios/`)

| Script | One line |
|--------|----------|
| `testflight-upload.sh` | Archive and upload ios-admin/ios-pos to TestFlight |
| `sync-local-config.sh` | Point ios-admin at local dev server URL (`npm run ios:local-config`) |
| `sync-pos-local-config.sh` | Point ios-pos at local dev server URL (`npm run ios-pos:local-config`) |
| `sync-portrait-resources.js` | Sync portrait layout scripts into ios-admin |
| `run-admin-tests.sh` | Portrait sync + Node checks + ios-admin XCTest (`npm run test:ios-admin`) |
| `run-pos-tests.sh` | ios-pos XCTest (`npm run test:ios-pos`) |

---

## TLS (`scripts/tls/`)

| Script | One line |
|--------|----------|
| `generate-dev-tls.sh` | Self-signed cert for local HTTPS dev |
| `generate-lb-tls.sh` | Self-signed cert for OCI load balancer HTTPS (POC) |

---

## Tools (`scripts/tools/`)

| Script | One line |
|--------|----------|
| `install-sqlcl.sh` | Download/install SQLcl + Java 21 on macOS |
| `generate-product-barcodes-pdf.py` | PDF of product barcodes from `db/seed.sql` |

---

## Docker

| Script | One line |
|--------|----------|
| `docker-entrypoint.sh` | Container entrypoint: Node + optional Cloudflare tunnel (referenced by `Dockerfile`) |

---

## OCI (`scripts/oci/`)

See [docs/oci-deploy.md](../docs/oci-deploy.md) for the full decision table. Quick reference:

| Script | One line |
|--------|----------|
| `deploy.sh` | Full greenfield prod deploy: Terraform + image push + DB seed |
| `deploy-dev.sh` | Full greenfield dev stack deploy |
| `redeploy-app-code.sh` | Build, push tagged image, terraform apply (prod app code) |
| `redeploy-app-code-dev.sh` | Same for dev (`CLOUD_STORE_ENV=dev`) |
| `deploy-app-oci.sh` | Legacy alias: tagged image deploy |
| `deploy-app-oci-dev.sh` | Dev wrapper for `deploy-app-oci.sh` |
| `container.sh` | Start/stop/status container instance |
| `restart-container-instance.sh` | Restart instance (same cached image — no code update) |
| `terraform-apply-container.sh` | Terraform apply with IP-change warning |
| `terraform-apply-container-dev.sh` | Dev wrapper |
| `sync-container-env-to-terraform.sh` | Copy `.env` keys → terraform container env tfvars |
| `sync-container-env-to-terraform-dev.sh` | Dev wrapper (reads `.env.dev`) |
| `confirm-public-url.sh` | Resolve and print live public app URL |
| `reattach-reserved-ip.sh` | Reattach reserved IP after container instance replace |
| `dev-dns-a-record.sh` | Update dev hostname A record to LB IP |
| `wait-for-app-health.sh` | Poll until `GET /api/build-info` returns 200 |
| `idp-update-redirect-uris.sh` | Add OAuth redirect URIs for prod hostname |
| `idp-update-redirect-uris-dev.sh` | Add dev hostname URIs (keeps prod intact) |
| `idp/bootstrap-dev.sh` | Automated dev Identity Domain + OIDC apps + `.env.dev` |
| `idp-bootstrap-dev.sh` | Wrapper for `idp/bootstrap-dev.sh` |
| `terraform-destroy-workloads-dev.sh` | Destroy dev workloads; keep compartment (+ IdP domain) |
| `list-resources-dev.sh` | List resources in `cloud-store-dev` compartment |
| `deploy-cert-renew-function.sh` | Build/push cert-renew OCI Function image |
| `seed-certbot-state.sh` | Upload local certbot state to Object Storage |
| `invoke-cert-renew-function.sh` | Invoke cert renew (smoke/dry-run/force) |
| `verify-certbot-dns-oci.sh` | Verify DNS-01 + certbot-dns-oci on Mac |
| `terraform-destroy-workloads.sh` | Destroy workloads; keep compartment |
| `terraform-recover-workload-state.sh` | Remove stuck workload addresses from TF state |
| `oci-costs.sh` | OCI spend by service/compartment/date range |
| `list-resources.sh` | List resources in project compartment (prompts prod/dev) |
| `prune-ocir-images.sh` | Delete stale OCIR images (dry-run by default) |
| `sync-systems-manifest.sh` | Write `data/systems-oci-resources.json` for Systems tab |
| `bootstrap-dev-tfvars.sh` | Copy OCI auth from prod tfvars into dev tfvars |

---

## Compatibility wrappers (deprecated paths)

These forward to the new location. Update call sites when convenient.

| Old path | New path |
|----------|----------|
| `scripts/dev-up.sh` | `scripts/dev/up.sh` |
| `scripts/run-tests.sh` | `scripts/test/run-tests.sh` |
| `scripts/seed.sql` | `scripts/db/seed.sql` (symlink) |
| `scripts/reset-db.sh` | `scripts/db/reset-db.sh` |
| `scripts/install-sqlcl.sh` | `scripts/tools/install-sqlcl.sh` |
| `scripts/sync-ios-*.sh` | `scripts/ios/sync-*.sh` |
| … | See `scripts/*.sh` wrappers at repo root of `scripts/` |

---

## Planned next phase

- Sub-group `scripts/oci/` into `deploy/`, `container/`, `network/`, `idp/`, `certs/`, `terraform/`, `ops/` with wrappers at current paths.
