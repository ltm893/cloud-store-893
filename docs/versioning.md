# Versioning and PR workflow

Cloud Store uses **`dev` as the integration branch** (there is no `main` yet). All PRs target `dev`.

Three identifiers work together:

| Field | Source | Purpose |
|-------|--------|---------|
| **`appVersion`** | `package.json` `version` | Product / release number (semver). Bump on milestones. |
| **`buildId`** | `YYYYMMDDHHmmss` at deploy | Unique deploy timestamp; sortable. |
| **`label`** | Required arg to `redeploy-app-code.sh` | Human “what changed” (usually matches PR or CHANGELOG). |
| **`gitSha`** | Short commit at deploy | Tie a running container to exact git revision. |

Platform tab and `GET /api/build-info` show:

```text
v1.0.0 · platform ui cards : 20260619143022 (a1b2c3d)
```

---

## Every PR (feature / fix)

1. Branch from **`dev`**, open PR **→ `dev`**.
2. CI runs unit tests on push and on the PR.
3. Add a line under **`## [Unreleased]`** in [CHANGELOG.md](../CHANGELOG.md) if the change is user-facing, operational, or worth remembering at deploy time.
4. **No `package.json` bump** for routine work.

Use the PR template checklist; nothing else is required for versioning.

---

## Release PR (milestone / demo / tagged cut)

When you want a named version (e.g. `1.1.0`):

1. On your branch (or a dedicated `release/1.1.0` branch):
   - Bump **`package.json`** `version` (semver).
   - Move CHANGELOG **`[Unreleased]`** items into **`## [1.1.0] - YYYY-MM-DD`**.
   - Leave **`[Unreleased]`** empty (or with new placeholder sections).
2. Open PR → **`dev`**, merge when green.
3. After merge, tag on **`dev`** (optional but recommended):

   ```bash
   git checkout dev && git pull
   git tag -a v1.1.0 -m "Release 1.1.0"
   git push origin v1.1.0
   ```

Release PRs can include feature work or be a thin “version bump only” PR after other PRs already merged.

---

## Deploy after merge (OCI)

Deploy from **`dev`** at the commit you intend to run:

```bash
git checkout dev && git pull
./scripts/oci/redeploy-app-code.sh "short description of this deploy"
```

- **`BUILD_ID`** — set automatically (timestamp).
- **`BUILD_LABEL`** — your quoted string; reuse PR title or CHANGELOG bullet.
- **`GIT_SHA`** — set automatically from `git rev-parse --short HEAD`.
- **`appVersion`** — baked from `package.json` in the image.

Verify:

```bash
APP=$(./scripts/oci/confirm-public-url.sh)
curl -s "$APP/api/build-info" | jq .
```

---

## Local dev

Optional in `.env` (see `.env.example`):

```bash
BUILD_ID=dev
BUILD_LABEL=local dev
GIT_SHA=local
```

Without these, build info shows `unknown` for deploy fields; **`appVersion`** still comes from `package.json`.

---

## What not to merge

- Do **not** tie Android/iOS `versionName` to server semver unless you ship them together; they release on different cadences.
- Do **not** use OCIR `:latest` tag as the source of truth — use **`buildId` + `gitSha`** on Platform.

---

## Adding `main` later

If you introduce **`main`** for production:

- Keep **`dev`** for integration; PRs still land on `dev`.
- Promote **`dev` → `main`** (or release tags) for production deploys only.
- Point CI `pull_request.branches` at both; deploy script unchanged.

Until then, **`dev` is production** for OCI.
