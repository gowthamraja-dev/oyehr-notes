---
task: 23
title: Leave Policy API — accrual/entitlement CRUD, resolution service, audit
status: done
depends_on: [21, 22]
---

## As-built deviations from the spec below

- **`404 NO_POLICY` body is `{"detail": {"code": "NO_POLICY", "leave_type": {...}}}`, not the
  flat `{"detail": "NO_POLICY", "leave_type": {...}}` this file originally sketched.** FastAPI's
  default `HTTPException` handler always wraps whatever is passed as `detail` under a top-level
  `"detail"` key (`fastapi/exception_handlers.py`) — there's no way to get a sibling key next to
  `detail` without a custom exception handler, which would be new app-wide machinery for one
  endpoint. Nesting `{"code": ..., "leave_type": ...}` under `detail` gets the same information
  across with zero new infrastructure. `frontend/src/lib/api.ts`'s `getLeaveTypePolicy`
  ([[25-leave-policy-api-client]]) should read `data.detail.code`/`data.detail.leave_type`.
  Confirmed JSON-serializable: `leave_type` is passed through `LeaveTypeOut.model_dump(mode="json")`
  first, since Starlette's `JSONResponse` does not run `exc.detail` through `jsonable_encoder` and
  would otherwise choke on raw `date` values.
- **Duplicate-code-style validation errors use `422` as specced** (unlike task 22's duplicate
  leave-type `code`, which uses `409` — that one's a DB unique-constraint violation; the overlap/
  carry-forward/encashment rules here are pure business-rule rejections with no DB constraint
  behind them, so `422` is the right code and matches what's written above).
- **Status-patch no-ops write no audit row.** If `PATCH .../status` sets `is_active` to the value
  it already has, nothing changed, so no `LeavePolicyAudit` row is written — the "every mutation
  writes exactly one audit row" criterion below is read as "every *state-changing* mutation."
- Everything else (endpoints, schemas, effective-dated split, overlap precedence,
  `resolve_leave_policy`, audit-in-transaction) matches this file's spec as written.

# 23 — Leave Policy API — accrual/entitlement CRUD, resolution service, audit

## Scope

Everything about `leave_policy_details`: CRUD endpoints, the `resolve_leave_policy` service
function, effective-dated update semantics, overlap validation, and audit-row writes. Extends
`backend/app/modules/leave/` from [[22-leave-type-api]] — same module, same three files, not a
new package.

**Explicitly not in scope** (prompt §40 / this plan's overall split): leave requests,
approvals, the balance ledger, or any employee-facing "my balance" screen. Those are a separate,
much larger effort already speced in `docs/leave-and-attendance/leave/ledger.md` and
`api-and-pages.md` §3.1–3.3 (endpoints like `/leave/requests`, `/leave/me/balances`) — this task
builds none of them. `resolve_leave_policy` is written now because the admin API itself needs it
(to answer "which policy governs this leave type today"); the future ledger/accrual service will
call the same function rather than reimplementing resolution.

## Files

- `backend/app/modules/leave/schemas.py` — add `LeavePolicyIn`, `LeavePolicyPatch`,
  `LeavePolicyOut`, `LeavePolicyStatusPatch`, `LeaveTypeWithPolicyOut`
- `backend/app/modules/leave/service.py` — add `get_leave_type_with_policy`,
  `list_policies_for_type`, `create_policy`, `update_policy`, `set_policy_status`,
  `resolve_leave_policy`, `_write_policy_audit` (private helper)
- `backend/app/modules/leave/router.py` — add the policy routes below

## Endpoints

Same auth/tenant-scoping rules as [[22-leave-type-api]] (admin-only, `principal.tenant_id`
filter on every query).

| Method | Path | Request | Response |
| --- | --- | --- | --- |
| GET | `/leave/types/{leave_type_id}/policy` | `?corp_master_id=` (optional) | `LeaveTypeWithPolicyOut` — the leave type plus its **resolved current policy** for that corp (or the all-corps policy if `corp_master_id` omitted/no corp-specific match). `404 NO_POLICY` shape (see below) if no policy row exists at all for this type yet |
| GET | `/leave/types/{leave_type_id}/policies` | — | `list[LeavePolicyOut]` — **all** policy rows (all corps, all effective periods, including archived) for the admin's "history" view — not just the resolved one |
| POST | `/leave/types/{leave_type_id}/policies` | `LeavePolicyIn` | `LeavePolicyOut`, `201` |
| PATCH | `/leave/policies/{policy_id}` | `LeavePolicyPatch` | `LeavePolicyOut` — see effective-dating rule below |
| PATCH | `/leave/policies/{policy_id}/status` | `LeavePolicyStatusPatch` (`{"is_active": bool}`) | `LeavePolicyOut` |

### `404 NO_POLICY` response shape

When `GET /leave/types/{id}/policy` finds no policy row at all:

```json
{ "detail": "NO_POLICY", "leave_type": { "...LeaveTypeOut fields..." } }
```

The frontend ([[26-leave-policy-frontend]]) uses this to render the empty state (prompt §30)
while still having the leave-type header to show.

### `LeavePolicyIn` (create)

Required: `accrual_frequency`, `accrual_quantity`, `effctv_dt`.

```
corp_master_id: int | None = None          # None = all corporations
employee_type_master_id: int | None = None # always None in v1 — accepted but unused (gaps.md #4)
accrual_frequency: Literal["Monthly", "Quarterly", "Yearly", "OnJoining"]
accrual_quantity: Decimal
max_balance: Decimal | None = None
carry_forward: bool = False
max_carry_forward: Decimal | None = None
encashable: bool = False
max_encashment: Decimal | None = None
prorate_on_joining: bool = True
reset_month: int | None = None             # 1-12
effctv_dt: date
trmntn_dt: date | None = None
```

### `LeavePolicyPatch`

Same fields, all optional, partial-update semantics — **except** `carry_forward` and
`encashable`: setting either to `false` in the same patch call also clears the corresponding max
field server-side (`max_carry_forward` / `max_encashment` forced to `NULL`), regardless of what
the client sent for it. Never trust the client to have zeroed it out itself (prompt §11 / §12 —
"backend must still validate this").

## Validation (rejected with `422`, plain message, never the raw Postgres error — prompt §29)

- `accrual_frequency` must be one of the four literal values
- `accrual_quantity`, `max_balance`, `max_carry_forward`, `max_encashment` — all `>= 0`
- `reset_month`, if set, must be `1..12`
- `trmntn_dt`, if set, must be `>= effctv_dt`
- `carry_forward = false` ⇒ `max_carry_forward` must be `None` in the stored row (silently
  cleared per the Patch rule above; on **create**, reject with `422` if the client passes a
  non-null `max_carry_forward` alongside `carry_forward=false` — creation has no ambiguity to
  paper over)
- `encashable = false` ⇒ same rule for `max_encashment`
- **Overlap check** on create and on any patch that changes `corp_master_id`, `effctv_dt`, or
  `trmntn_dt`: reject with `422` (`"Another policy already covers this effective period"` — the
  exact prompt §29 wording) if an existing **active, non-archived** policy row for the same
  `leave_type_master_id` has an overlapping `[effctv_dt, trmntn_dt or infinity)` window **and**
  matches on corp specificity. Since `employee_type_master_id` is always `NULL` in v1
  ([gaps.md #4](../../docs/leave-and-attendance/leave/gaps.md)), the precedence collapses to two
  tiers, not the prompt's four:
  1. `corp_master_id = X` overlaps only other rows with `corp_master_id = X`
  2. `corp_master_id IS NULL` (all corporations) overlaps only other rows that are also `NULL`

  A corp-specific policy and an all-corps policy are allowed to coexist over the same dates (the
  corp-specific one takes precedence at resolution time — see `resolve_leave_policy` below); they
  are not "overlapping" for this check.

## Effective-dated updates (prompt §20 — the "Preferred" behavior)

`PATCH /leave/policies/{id}` on a policy whose `effctv_dt <= today` (i.e. it is or has been
live) does **not** mutate the row in place. Instead:

1. Set the existing row's `trmntn_dt = today - 1 day` (close it), `updated_by_id`.
2. Insert a **new** `leave_policy_details` row with the patched field values, same
   `leave_type_master_id`/`corp_master_id`/`employee_type_master_id`, `effctv_dt = today`,
   `trmntn_dt = None` (or the patched value), `created_by_id`.
3. Return the **new** row as the response.
4. Both steps run in one DB transaction (CLAUDE.md-style: validate → mutate → audit → commit;
   roll back entirely on any failure).

A policy whose `effctv_dt > today` (not yet live — created for a future date and never
activated) **is** mutated in place — there is no history to preserve yet. This is the practical
reading of "already used": the schema has no ledger/accrual-job trace to check (that module
doesn't exist), so "used" is approximated as "its effective period has started."

`PATCH .../status` (activate/deactivate) always mutates `is_active` in place regardless of
effective date — it's a visibility toggle, not a configuration rewrite, and doesn't need the
close-and-recreate dance.

## `resolve_leave_policy`

```python
def resolve_leave_policy(
    db: Session, tenant_id: int, leave_type_master_id: int,
    corp_master_id: int | None, as_of: date,
) -> LeavePolicyDetail | None:
```

Query active (`is_active=true, archive=false`), tenant-scoped, `leave_type_master_id`-matching
rows where `effctv_dt <= as_of <= COALESCE(trmntn_dt, 'infinity')`. Prefer, in order:
1. `corp_master_id = corp_master_id` (only when `corp_master_id` is not `None`)
2. `corp_master_id IS NULL`

Return the single highest-precedence match, or `None`. (`employee_type_master_id` branch is
intentionally omitted — v1 never populates it, per `gaps.md` #4. Adding it back is a one-line
change to the precedence list once that master table exists — don't build dead branches for it
now.)

This is the function `GET /leave/types/{id}/policy` and the `policy_summary` computed field in
[[22-leave-type-api]] both call.

## Audit

Every successful `POST`, `PATCH` (including the close-and-recreate), and `PATCH .../status`
writes one `LeavePolicyAudit` row (model from [[21-leave-policy-models-migration]]) inside the
same transaction as the policy mutation — never write an audit row for a failed/rolled-back
mutation (prompt §26). `action` = `CREATED` / `UPDATED` / `ACTIVATED` / `DEACTIVATED`. `changes`
= a short plain-text diff of the fields that actually changed, e.g.
`"accrual_quantity: 1.50 -> 1.75; max_carry_forward: 5 -> 10"` (empty string for `CREATED`).

## Acceptance criteria

- [x] `GET /leave/types/{id}/policy` resolves the right row by corp precedence; returns the
      `404 NO_POLICY` shape when none exists (see deviation note above on exact body shape)
- [x] `POST` creates a policy, runs all validation rules above, writes an audit row
- [x] Creating a second policy with an overlapping window for the same corp-specificity tier is
      rejected `422`; a corp-specific and an all-corps policy over the same dates coexist fine
- [x] `PATCH` on a not-yet-effective policy mutates in place
- [x] `PATCH` on an already-effective policy closes the old row (`trmntn_dt` set) and creates a
      new one — old row still readable via `GET .../policies` (history preserved), never deleted
- [x] `carry_forward=false` clears `max_carry_forward` to `NULL` server-side even if the client
      sends a value for it; same for `encashable`/`max_encashment`
- [x] `PATCH .../status` toggles `is_active` without closing/recreating the row
- [x] Every state-changing mutation writes exactly one `leave_policy_audits` row; a rejected
      (422/403/404) request or a status no-op writes zero
- [x] Cross-tenant isolation and admin-only gating, same as [[22-leave-type-api]]
- [x] Encrypted round-trip test for the policy routes

25 new tests added to `test_leave.py` (41 total for the module). Full backend suite: 269 passed;
the same 2 pre-existing `test_engagement_email.py` failures as task 22 (confirmed unrelated via
`git stash` in that task), no regressions. Also fixed a bug caught by the tests:
`_default_policy_summary`'s `f"{max_balance:g}"` produced `"21.00 days"` instead of `"21 days"`
because `Decimal`'s own `:g` formatting preserves the `NUMERIC(6,2)` column's trailing zeros
unlike float's — fixed by formatting `float(max_balance)` instead.

Completed: 2026-08-17
