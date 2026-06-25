# Dev IdP bootstrap — automated OCI Identity Domain for the dev stack.

Creates a **new** domain named `cloud-store-app-N` (auto-increment), one dev user,
`cloud-store-pos` + `cloud-store-admin` OIDC apps, and writes `.env.dev`.

## Quick start

```bash
cp .env.dev.example .env.dev   # optional; defaults include ltm893@icloud.com
./scripts/oci/idp/bootstrap-dev.sh --apply
```

`--apply` runs `sync-container-env-to-terraform-dev.sh` + `terraform-apply-container-dev.sh`.

Password is **generated and printed once** (not committed).

## Prerequisites

- Dev stack deployed (`./scripts/oci/deploy-dev.sh`, `terraform.dev.tfstate`)
- `oci` CLI + `jq`
- IAM permission to create identity domains in the dev compartment

## Options

| Flag | Effect |
|------|--------|
| `--dry-run` | Print next `cloud-store-app-N` name only |
| `--resume` | Continue on latest existing `cloud-store-app-N` (after a partial run) |
| `--apply` | Push IdP env to dev container after bootstrap |

## Layout

```text
scripts/oci/idp/
  bootstrap-dev.sh       # orchestrator
  lib/
    idp-env.sh           # .env.dev + terraform dev compartment
    idp-domain.sh        # create domain, wait ACTIVE
    idp-groups-user.sh   # groups + user + password
    idp-apps.sh          # OIDC apps + group grants
    idp-write-env.sh     # .env.dev + container_env.dev.tfvars
  state/                 # gitignored local metadata (no password)
```

Wrapper: `scripts/oci/idp-bootstrap-dev.sh`

## After bootstrap

1. Sign in: `https://dev.oci.cloudstore893.com/oauth/login`
2. If `groups` claim missing: OCI Console → domain → token issuance settings
3. Verify: `curl -s "$(CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh)/api/cashier/session"`

See [docs/oci-dev-environment.md](../../../docs/oci-dev-environment.md) and [docs/idp-setup.md](../../../docs/idp-setup.md).

## Troubleshooting

- **Stuck after `Created user:`** — older script versions omitted `--force` on the admin password reset; the OCI CLI waits for `y/N` on stdin. Use the current `idp-groups-user.sh` (prints `Setting password...` then `Password set`).
- **`domain create failed` with only `opc-work-request-id`** — create is async; domain may already exist. Re-run with `--resume`.
- **`App.basedOnTemplate ... CustomBrowserMobileApplication`** — use `CustomWebAppTemplateId` for confidential OIDC clients (default in `idp-apps.sh`).
- **500 on `create_app` (MapValue cannot be cast to StringValue)** — `allowedGrants` must be a string array (`["authorization_code","refresh_token"]`), not `{value,type}` objects.
- **400 redirect URI required** — authorization-code apps need at least one `redirectUris` entry at create time (bootstrap now seeds dev + localhost URLs).
- **Hang after `App id:` on redirect URIs** — `app get` on full App objects can hang; bootstrap now skips redirect update (URIs set at create). Standalone script uses `apps list` with `redirectUris` only.
