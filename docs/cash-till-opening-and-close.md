# Cash till — opening float, shift modes, and end-of-day balance

**Living doc** — update the [Journey log](#journey-log) and [Implementation checklist](#implementation-checklist) as work lands. Last updated: **2026-06-11** (initial design).

**Depends on:** [cashier-supervisor-approval.md](cashier-supervisor-approval.md) (Model B — IdP login + supervisor approval before `cashier_session`). This doc extends Model B with **opening till count** and **end-of-day (EOD) till balance**.

Related: [CONTENTS.md](../CONTENTS.md) (session handoff), [idp-setup.md](idp-setup.md), [testing.md](testing.md).

---

## Summary

| Store config | Cashier at open | Supervisor approves | During shift | At close |
|--------------|-----------------|---------------------|--------------|----------|
| `OPENING_CASH_FLOAT` **unset** | IdP login → wait (no till screen) | **Credit only** | Card / card-on-file only; **no cash pay** | N/A (no drawer) |
| `OPENING_CASH_FLOAT` **set** | IdP login → **till count** (denominations or **No cash today**) | **Cash + credit** or **credit only** | Cash + card per approval mode | **Balance till** → supervisor sign-off |

`OPENING_CASH_FLOAT` (e.g. `200.00`) is the **expected opening float** for the drawer — not an auto-filled balance. The cashier counts physical cash; the supervisor sees counted vs expected and any variance before approving the shift open.

---

## Journey log

| Date | Status | Notes |
|------|--------|-------|
| 2026-06-11 | **Designed** | Opening float, credit-only mode, till screen, EOD balance — API + schema sketched. |
| 2026-06-11 | **Phase A–B** | Server config, till submit, approval extension, checkout cash guard, tablet opening till UI, admin approval summary. EOD close not started. |

---

## Implementation checklist

| Step | Area | Status |
|------|------|--------|
| 1 | Env `OPENING_CASH_FLOAT` + server flags on `/api/cashier/session` | **Done** |
| 2 | Extend `login_approval_requests` (till fields) + ORDS | **Done** (`seed.sql`; apply via `reset-db.sh`) |
| 3 | `awaiting_till` → `pending` state machine; TTL starts at till submit | **Done** |
| 4 | Cashier APIs: submit till, poll includes till summary | **Done** |
| 5 | Server: reject `paymentMethod: cash` when session is credit-only | **Done** |
| 6 | Tablet — opening till screen (denominations + no-cash) | **Done** |
| 7 | Admin — approval card shows mode, denominations, variance | **Done** |
| 8 | `register_shifts` table + link sales to shift | **Partial** — table + open on approve; `sales.shift_id` not yet |
| 9 | EOD balance APIs + tablet close-till UI | Not started |
| 10 | EOD supervisor approval (admin or dedicated close panel) | Not started |
| 11 | Web POS — opening till + EOD (parity with tablet) | Not started |
| 12 | Tests + `.env.example` | Not started |

---

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENING_CASH_FLOAT` | *(unset)* | Expected opening drawer float in dollars (e.g. `200.00`). **Unset** = store runs **credit-only** (no cash pay, no till screens). |
| `CASHIER_SUPERVISOR_APPROVAL` | `false` | When `false`, skip supervisor gate; till rules below still apply where noted. See [Interaction with Model B](#interaction-with-model-b). |
| `CASHIER_APPROVAL_TTL_SEC` | `300` | Pending **supervisor** wait lifetime — clock starts when till is **submitted** (not at IdP callback). |
| `CASH_TILL_DENOMINATIONS` | *(see below)* | Optional JSON override for bill/coin rows on open and close screens. |

Default denomination set (USD):

```json
[
  { "id": "100", "label": "$100", "value": 100 },
  { "id": "50", "label": "$50", "value": 50 },
  { "id": "20", "label": "$20", "value": 20 },
  { "id": "10", "label": "$10", "value": 10 },
  { "id": "5", "label": "$5", "value": 5 },
  { "id": "1", "label": "$1", "value": 1 },
  { "id": "0.25", "label": "Quarters", "value": 0.25 },
  { "id": "0.10", "label": "Dimes", "value": 0.10 },
  { "id": "0.05", "label": "Nickels", "value": 0.05 },
  { "id": "0.01", "label": "Penny", "value": 0.01 }
]
```

Add to `.env.example` when implementing:

```bash
# Optional — expected opening cash drawer float. Unset = credit-only store (no cash pay).
# OPENING_CASH_FLOAT=200.00
```

---

## Interaction with Model B

| `CASHIER_SUPERVISOR_APPROVAL` | `OPENING_CASH_FLOAT` | Open shift | Close shift |
|-------------------------------|----------------------|------------|-------------|
| `true` | unset | IdP → supervisor (credit only) | No till close |
| `true` | set | IdP → till screen → supervisor | Balance till → supervisor |
| `false` | unset | IdP/PIN → session (credit only) | No till close |
| `false` | set | IdP/PIN → till screen → session (no supervisor) | Balance till (supervisor optional — see [EOD without Model B](#eod-without-model-b)) |

**Recommendation:** Require supervisor sign-off on EOD variance whenever `CASHIER_SUPERVISOR_APPROVAL=true`. When Model B is off, allow cashier to complete close with a recorded variance and optional admin review later.

---

## High-level flow — shift open

```text
  CASHIER                         NODE APP                    SUPERVISOR (admin)
      |                               |                                |
      |  OIDC sign-in                 |                                |
      |------------------------------>|                                |
      |                               |  If OPENING_CASH_FLOAT unset:  |
      |                               |    create approval (credit_only)|
      |                               |  If set:                       |
      |                               |    set awaiting_till cookie      |
      |                               |    (NO supervisor row yet)     |
      |<------------------------------|                                |
      |                               |                                |
      |  [OPENING_CASH_FLOAT set]     |                                |
      |  Till count UI                |                                |
      |  denominations OR "No cash"   |                                |
      |------------------------------>|                                |
      |  POST .../approval/till       |                                |
      |                               |  INSERT login_approval row     |
      |                               |  status=pending, cash_mode,    |
      |                               |  denominations, variance       |
      |                               |  START approval TTL            |
      |<------------------------------|                                |
      |  poll approval/status         |                                |
      |------------------------------>|                                |
      |                               |                                |
      |                               |  GET login-approvals           |
      |                               |<-------------------------------|
      |                               |  POST .../approve              |
      |                               |<-------------------------------|
      |<------------------------------|  cashier_session               |
      |  cashEnabled per cash_mode    |  + shift_id, opening snapshot  |
```

**Credit-only store** (`OPENING_CASH_FLOAT` unset): skip till screen; pending row is created at IdP callback with `cash_mode = credit_only`.

**No cash today** (float set but drawer empty): cashier selects **No cash today** → `cash_mode = credit_only` for this shift; supervisor still approves login but session has `cashEnabled: false`.

---

## High-level flow — end of day (EOD) till balance

EOD closes the **register shift** opened at login. One active shift per register session (or per `register_id` if multi-register is added later).

```text
  CASHIER                         NODE APP                    SUPERVISOR
      |                               |                                |
      |  Menu → Close / Balance till  |                                |
      |------------------------------>|                                |
      |                               |  Block if cart non-empty       |
      |                               |  Compute expected cash:        |
      |                               |    opening_counted             |
      |                               |  + sum(cash sale_payments)     |
      |                               |  - sum(change_given)           |
      |                               |  (see [Expected cash formula]) |
      |<------------------------------|  Show expected + sales summary|
      |                               |                                |
      |  Count denominations (close)  |                                |
      |------------------------------>|                                |
      |  POST .../shift/close/till    |                                |
      |                               |  INSERT register_shift_closes  |
      |                               |  status=pending_close          |
      |                               |                                |
      |                               |  Supervisor reviews variance   |
      |                               |<-------------------------------|
      |                               |  POST .../shift/close/approve  |
      |                               |                                |
      |<------------------------------|  shift closed; logout session  |
```

If counted close total matches expected within tolerance (e.g. ±$0.05), supervisor approval may be **auto-allowed** with one tap; non-zero variance requires explicit acknowledge (policy TBD in UI copy).

---

## Expected cash formula (EOD)

At close, the system computes **expected cash in drawer**:

```text
expected_close =
    opening_counted_float
  + net_cash_from_sales
  - cash_paid_out

net_cash_from_sales =
    SUM(sale_payments.amount WHERE payment_method = 'cash' AND shift_id = :shift)

cash_paid_out =
    SUM(sale_payments.change_given WHERE payment_method = 'cash' AND shift_id = :shift)
    -- money leaving drawer as change; NULL treated as 0
```

**Variance:**

```text
variance = counted_close_float - expected_close
```

Display to cashier and supervisor:

| Line | Source |
|------|--------|
| Opening (counted) | `register_shifts.opening_counted_float` |
| + Cash sales | Aggregated `sale_payments` for shift |
| − Change given | Aggregated `change_given` for shift |
| = **Expected in drawer** | Computed |
| Counted (EOD) | Cashier denomination entry |
| **Variance** | Counted − expected |

**Nickel rounding:** Cash sale amounts in `sale_payments.amount` should reflect **cash due** (nickel-rounded) once [cash rounding on server](../CONTENTS.md#cash-rounding-todo) is implemented. Until then, use the same amounts the tablet posts on checkout.

**Paid-ins / paid-outs** (optional later): add `register_cash_movements` (type `paid_in` | `paid_out`, amount, reason) and include in expected formula.

---

## Session and cookie states (extended)

```text
                    ┌─────────────────┐
                    │  Not signed in  │
                    └────────┬────────┘
                             │ OIDC OK
                             ▼
              ┌──────────────────────────────┐
              │ OPENING_CASH_FLOAT set?      │
              └──────┬───────────────┬───────┘
                     │ NO            │ YES
                     ▼               ▼
              ┌─────────────┐  ┌─────────────┐
              │   PENDING   │  │ AWAITING_   │
              │ (credit_only│  │ TILL        │
              │  approval)  │  │ till screen │
              └──────┬──────┘  └──────┬──────┘
                     │                │ POST till
                     │                ▼
                     │         ┌─────────────┐
                     └────────►│   PENDING   │
                               │ supervisor  │
                               └──────┬──────┘
                                      │ approve
                                      ▼
                               ┌─────────────┐
                               │  APPROVED   │
                               │ session +   │
                               │ shift_id    │
                               │ cashEnabled │
                               └──────┬──────┘
                                      │ EOD close approved
                                      ▼
                               ┌─────────────┐
                               │ Shift closed│
                               │ (logged out)│
                               └─────────────┘
```

**Session fields** (returned from `GET /api/cashier/session` when `ok: true`):

| Field | Type | Meaning |
|-------|------|---------|
| `cashTillEnabled` | boolean | Store has `OPENING_CASH_FLOAT` configured |
| `cashEnabled` | boolean | This shift may accept cash checkout |
| `shiftId` | string \| null | Active register shift |
| `openingCountedFloat` | number \| null | Counted opening total (audit) |
| `expectedOpeningFloat` | number \| null | From env at shift open |

Clients hide **Cash** in Pay UI when `cashEnabled === false`. Server rejects checkout with cash payments in that case.

---

## Database schema (planned)

### Extend `login_approval_requests`

Add columns (or JSON blob `till_payload` if migration simplicity is preferred):

| Column | Type | Purpose |
|--------|------|---------|
| `cash_mode` | `VARCHAR2(20)` | `cash_and_credit` \| `credit_only` |
| `expected_opening_float` | `NUMBER(10,2)` | Snapshot of `OPENING_CASH_FLOAT` at submit |
| `opening_counted_float` | `NUMBER(10,2)` | Sum of opening denominations |
| `opening_variance` | `NUMBER(10,2)` | `opening_counted - expected` (null if credit_only) |
| `opening_denominations` | `CLOB` | JSON map `{ "20": 10, "1": 0, ... }` |
| `till_submitted_at` | `TIMESTAMP` | When cashier finished till screen |

Optional status value **`awaiting_till`** on the approval row *or* separate `cashier_awaiting_till` cookie without DB row until submit — **recommended:** cookie-only until till submit, then insert row as `pending` (supervisor never sees half-finished opens).

### New `register_shifts`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | identity PK | Shift id |
| `register_id` | `VARCHAR2(64)` | Optional register label |
| `cashier_sub` | `VARCHAR2(256)` | IdP sub |
| `cashier_email` | `VARCHAR2(256)` | |
| `cash_mode` | `VARCHAR2(20)` | `cash_and_credit` \| `credit_only` |
| `expected_opening_float` | `NUMBER(10,2)` | |
| `opening_counted_float` | `NUMBER(10,2)` | |
| `opening_denominations` | `CLOB` | JSON |
| `opening_variance` | `NUMBER(10,2)` | |
| `approval_request_token` | `VARCHAR2(64)` | FK to login approval |
| `opened_at` | `TIMESTAMP` | Session start |
| `closed_at` | `TIMESTAMP` | null until EOD complete |
| `status` | `VARCHAR2(20)` | `open` \| `closing` \| `closed` |

### New `register_shift_closes`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | identity PK | |
| `shift_id` | FK → `register_shifts` | |
| `expected_close_float` | `NUMBER(10,2)` | Computed at close |
| `counted_close_float` | `NUMBER(10,2)` | Cashier count |
| `close_variance` | `NUMBER(10,2)` | |
| `close_denominations` | `CLOB` | JSON |
| `cash_sales_total` | `NUMBER(10,2)` | Snapshot for reports |
| `change_given_total` | `NUMBER(10,2)` | Snapshot |
| `status` | `VARCHAR2(20)` | `pending` \| `approved` \| `denied` |
| `resolved_by_sub` | `VARCHAR2(256)` | Supervisor |
| `resolved_at` | `TIMESTAMP` | |

### Extend `sales` (or `sale_payments`)

| Column | Type | Purpose |
|--------|------|---------|
| `shift_id` | `NUMBER` FK | Tie sale to register shift for EOD aggregation |

Populate `shift_id` on checkout from active session shift.

ORDS: enable REST on new tables; follow patterns in `scripts/seed.sql` and `lib/admin-tables.js`.

---

## API routes (planned)

### Cashier — opening

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/cashier/till/config` | public / pending | `{ cashTillEnabled, expectedOpeningFloat, denominations }` |
| POST | `/api/cashier/approval/till` | `cashier_awaiting_till` cookie or Bearer | Submit opening count or `credit_only`; creates `pending` approval |
| GET | `/api/cashier/approval/status` | pending cookie | *(existing)* Include `cashMode`, till summary when pending |
| GET | `/api/cashier/session` | public | *(existing)* Add `cashEnabled`, `shiftId`, till fields |

**`POST /api/cashier/approval/till` body:**

```json
{
  "cashMode": "cash_and_credit",
  "denominations": { "100": 0, "50": 0, "20": 10, "10": 0, "5": 0, "1": 0, "0.25": 0, "0.10": 0, "0.05": 0, "0.01": 0 },
  "countedTotal": 200.00
}
```

```json
{ "cashMode": "credit_only" }
```

Server validates `countedTotal` against denominations (and optional match to `OPENING_CASH_FLOAT`). Does **not** require exact match — variance is shown to supervisor.

When `OPENING_CASH_FLOAT` is unset, OIDC callback creates pending approval with `credit_only` directly (no till POST).

### Cashier — EOD

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/cashier/shift/close/preview` | `cashier_session` | Expected close, sales breakdown, blockers (open cart) |
| POST | `/api/cashier/shift/close/till` | `cashier_session` | Submit close count; `register_shift_closes` → `pending` |
| GET | `/api/cashier/shift/close/status` | `cashier_session` | Poll close approval |
| POST | `/api/cashier/shift/close/cancel` | `cashier_session` | Abort close-in-progress, return to selling |

**`POST /api/cashier/shift/close/till` body:** same shape as opening till (denominations + countedTotal).

On supervisor approve: set shift `closed`, clear `cashier_session`, client returns to login.

### Supervisor — opening (extend existing)

| Method | Path | Change |
|--------|------|--------|
| GET | `/api/admin/login-approvals` | Each item includes `cashMode`, `expectedOpeningFloat`, `openingCountedFloat`, `openingVariance`, `openingDenominations` |
| POST | `.../approve` | Creates `register_shifts` row; session payload includes `shiftId`, `cashEnabled` |

### Supervisor — EOD

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/admin/shift-closes?status=pending` | supervisor | List pending EOD balances |
| POST | `/api/admin/shift-closes/:id/approve` | supervisor | Close shift + force cashier logout |
| POST | `/api/admin/shift-closes/:id/deny` | supervisor | Cashier must re-count or continue shift |

Admin UI: extend **Login approvals** for open; add **Shift closes** tab or merge into one **Register** queue with type badge (`OPEN` | `CLOSE`).

### Checkout guard

`POST /api/checkout`: if session `cashEnabled === false` and any payment has `method === 'cash'`, respond `403` with `{ error: 'Cash payments are not enabled for this shift' }`.

---

## Client UX (tablet-first)

### Opening till screen

Shown after OIDC when `cashTillEnabled && awaitingTill`.

- Header: expected float `OPENING_CASH_FLOAT` (e.g. “Target: $200.00”)
- Denomination rows: count inputs + line subtotals
- Running **Counted total** and **Variance** (colored if ≠ 0)
- Primary: **Submit for approval**
- Secondary: **No cash today** → confirm → credit-only approval
- **Cancel** → sign out / clear awaiting cookie

### Pay panel

- Hide **Cash** when `!cashEnabled`
- Card and card-on-file unchanged

### EOD — Balance till

Entry: drawer menu or end-of-shift action (not on every sale).

1. Confirm cart empty (or prompt to clear suspend — out of scope v1: block only).
2. Show read-only summary: opening, cash sales, change, **expected**.
3. Denomination count (same widget as open).
4. **Submit for supervisor approval** (or **Complete shift** when Model B off and variance zero).
5. Waiting overlay (reuse approval poll pattern).
6. On approve: receipt/summary optional; return to login.

### Web POS

Same gates in `public/app.js` — lower priority than tablet (checklist step 11).

---

## EOD without Model B

When `CASHIER_SUPERVISOR_APPROVAL=false` but `OPENING_CASH_FLOAT` is set:

- Opening till screen still runs; session starts immediately after till submit (no supervisor).
- EOD: cashier submits close count; if `|variance| <= 0.05`, auto-close shift; else require supervisor PIN/IdP or flag for admin report (pick one at implement time — **default:** still show variance on admin **Shift history** read-only).

---

## Admin / reporting (later)

- **Shift history** table: open/close times, cashier, variances, totals.
- Export CSV for accounting.
- Link to `sales` for shift id drill-down.

Not required for v1 implementation but schema supports it.

---

## Suggested build order

1. **Phase A — Policy + enforcement:** `OPENING_CASH_FLOAT` env; `cashTillEnabled` / `cashEnabled` on session; checkout cash guard; hide Cash on tablet.
2. **Phase B — Open till:** Schema + till submit API; extend approval + admin card; tablet opening screen; TTL starts at till submit.
3. **Phase C — Shifts:** `register_shifts` + `shift_id` on sales; session carries `shiftId`.
4. **Phase D — EOD:** Close preview API, close till UI, supervisor close approval, logout on close.
5. **Phase E — Web parity + tests.**

---

## Files to touch (when implementing)

| File | Role |
|------|------|
| `scripts/seed.sql` | `register_shifts`, `register_shift_closes`, extend `login_approval_requests`, `sales.shift_id` |
| `lib/cash-till-config.js` | Parse `OPENING_CASH_FLOAT`, denominations |
| `lib/login-approval.js` | Till payload on create; extend `mapRow` |
| `lib/register-shifts.js` | Open/close shift store |
| `lib/cashier-auth.js` | `awaiting_till` cookie, session till fields |
| `lib/oidc-pos.js` | Branch: awaiting till vs immediate pending |
| `lib/supervisor-routes.js` | EOD approve/deny |
| `server.js` | Till + close routes; checkout cash guard |
| `public/admin/admin-approvals.js` | Till summary on approval cards |
| `public/admin/admin-shift-closes.js` | EOD panel (new) |
| `android-pos/.../OpeningTillScreen.kt` | Denomination UI (new) |
| `android-pos/.../CloseTillScreen.kt` | EOD UI (new) |
| `android-pos/.../PosViewModel.kt` | Gate: OIDC → till → approval → POS |
| `android-pos/.../CheckoutPaymentPanel.kt` | Respect `cashEnabled` |
| `.env.example` | `OPENING_CASH_FLOAT` |
| `docs/cashier-supervisor-approval.md` | Cross-link to this doc |
| `test/cash-till.test.js` | Config, variance math, checkout guard |

---

## Testing (planned)

| Test | Purpose |
|------|---------|
| Unit: expected close formula | Opening + sales − change |
| Unit: `cashEnabled` derivation | env unset, credit_only, cash_and_credit |
| Integration: till submit → pending row with variance | ORDS |
| Integration: checkout 403 when credit-only | HTTP |
| Integration: EOD preview matches seeded `sale_payments` | HTTP |
| Manual E2E | Open with variance → supervisor sees → sell cash sale → EOD variance |

See [cashier-supervisor-approval.md § Testing](cashier-supervisor-approval.md#testing-manual-today) for Model B server setup.

---

## Open questions (resolve during implementation)

1. **Multi-register:** one shift per `register_id` or per device session only? (v1: per session, optional `register_id` on shift row.)
2. **Suspend cart at EOD:** block close if cart has lines, or auto-clear? (v1: block.)
3. **Supervisor auto-approve EOD** when variance is zero — yes/no? (Recommend: yes, one-tap.)
4. **Paid-in / paid-out** — v1 omit; document extension point in `register_cash_movements`.

---

## Updating this doc

When implementation lands:

1. **Journey log** — date, status, one-line note.
2. **Implementation checklist** — mark steps done.
3. **Last updated** date at the top.
4. Adjust flows if OIDC callback or approval TTL behavior changes.
