---
task: 61
title: Leave assignment model, ledger traceability column, and assignment-audit table + migration
status: done
depends_on: [42]
---

# 61 — Leave assignment model, ledger traceability column, and assignment-audit table + migration

## Discussion

Source doc: `.design/prompts/employee_leave_assignment_and_ledger_flow.md`. Its core ask —
"assigning leave entitlement does not directly overwrite a balance; it creates an auditable
ledger transaction, atomically" — is **already built** for the ledger itself
([[42-leave-request-ledger-models-migration]]/[[43-leave-ledger-service]]): `employee_leave_balance_ledgers`
is append-only, `ledger_service.write_ledger_entry` takes an advisory lock and writes one signed
row per call. What is **not** built is the design doc's other half: a **Leave Assignment**
business record (§17, §20) distinct from a raw ledger write — the "why/how the entitlement was
granted" object, with its own source-type vocabulary (Policy / Manual / Opening balance / Carry
forward), effective period, reason, and status — plus any traceability from a ledger row back to
the assignment that created it. Today the only assignment-adjacent code path is
`POST /leave/employees/{id}/ledger/adjust` (`service.py:1799-1820`), which writes one generic
`Adjustment` row with no distinguishing source and no linked business record. This is exactly
`docs/leave-and-attendance/leave/gaps.md` gap #9's still-open state: *"there is still no
frontend for either [ledger GET or adjust]... this gap re-opens fully on the frontend half"* —
this task (and [[62]]-[[66]]) close it properly instead of just bolting a frontend onto the
generic adjust endpoint.

### Source-type vocabulary — a deliberate, narrower cut than the design doc

The design doc lists 8 assignment sources (`POLICY, MANUAL, OPENING_BALANCE, CARRY_FORWARD,
ACCRUAL, COMP_OFF, IMPORT, REVERSAL`). This task builds exactly **four**:
`Policy | Manual | OpeningBalance | CarryForward`. Reasons, so a later session doesn't reopen
this:

- **Comp-off excluded.** `gaps.md` #1: *"nothing in the schema credits a comp-off... recommend
  removing Comp-off from the apply dropdown until built."* Adding a Comp-off assignment source
  now would let HR manually grant comp-off despite the earning mechanism not existing — same
  gap, different door. Excluded until #1 lands.
- **Accrual excluded as a separate source.** It isn't a *manual* grant at all — it's the
  not-yet-built periodic job ([[42]]'s scope note: *"the accrual job... explicitly out of scope
  for this task and the whole leave-request arc"*). Do not add a UI path that lets a human
  trigger what should be a system job.
- **Import/Reversal excluded.** Import has no data-migration requirement yet; Reversal is not a
  *creation*-time source — it is what cancelling an assignment produces (§9 below), not something
  HR selects up front.

### Mapping source_type → the existing ledger `txn_type` (do not add new txn_type values)

`employee_leave_balance_ledgers.txn_type` is a plain `String(20)`, already migrated, already
covered by the partial unique index in [[42]], and documented end-to-end across `ledger.md`,
`vocabularies.md` and `gaps.md` #19/#21. Do **not** widen that vocabulary. Instead, the
assignment's own `source_type` is the richer, HR-facing concept; the service layer ([[62]]) maps
it down at write time:

| assignment `source_type` | ledger `txn_type` written |
| --- | --- |
| `Policy` | `Accrual` |
| `Manual` | `Adjustment` |
| `OpeningBalance` | `Opening` |
| `CarryForward` | `CarryForward` |

**Why Policy → Accrual, not Opening.** `ledger.md`'s own definition of `Opening` is "migrating/
importing an existing employee balance" — a one-time historical seed. A Policy-sourced
assignment (e.g. "Earned Leave, 18 days, FY 2026-27, Source: Policy" from the design doc's own
§3 example) is a routine per-period entitlement grant standing in for the not-yet-built accrual
job — semantically an accrual, and it inherits that txn_type's existing idempotency protection
(the partial unique index already covers `Accrual`) for free. Reusing `Opening` for this would
blur two genuinely different events and, worse, would make a real opening-balance import
indistinguishable from a routine annual grant in every report that groups by `txn_type`.

## Files

### New model — `backend/app/models/employee_leave_assignment.py`

`EmployeeLeaveAssignment` → `employee_leave_assignments`. Not append-only (status/cancellation
fields are mutated in place on cancel — the immutable audit trail lives in the ledger's
`Reversal` row plus `leave_assignment_audits`, not in this table's own immutability).

Columns:
- `id`: BigInteger PK.
- `care_delivery_program_master_id`: FK `care_delivery_program_masters.id`, indexed (tenant).
- `employee_master_id`: FK `employee_masters.id`, indexed.
- `leave_type_master_id`: FK `leave_type_masters.id`, indexed.
- `leave_year`: Integer — resolved the same way ledger rows are (`resolve_leave_policy`/
  `resolve_leave_year` against `effective_from`), so an assignment and the ledger row it creates
  always agree on `leave_year`.
- `source_type`: `String(20)` — `Policy|Manual|OpeningBalance|CarryForward`.
- `assigned_units`: `Numeric(6,2)` — signed. Positive-only for `Policy`/`OpeningBalance`/
  `CarryForward` (enforced in [[62]]'s service layer, not a DB CHECK); may be negative only for
  `Manual` (design doc §28's "Remove -1" case).
- `effective_from`: Date.
- `effective_to`: Date, nullable.
- `reason`: `String`, nullable — required by service validation when `source_type == 'Manual'`
  (mirrors `LeaveLedgerAdjustIn.remarks`'s existing `min_length=1` precedent for the generic
  adjust endpoint this replaces).
- `reference`: `String`, nullable — optional external reference number (design doc §15).
- `status`: `String(20)` — `Active|Cancelled`.
- `employee_leave_balance_ledger_id`: BigInteger, **not nullable** — FK to the one ledger row
  this assignment creates. Rule 12 (design doc §25): assignment and ledger credit are atomic, so
  every row here has exactly one ledger row from the moment it's committed.
- `created_by_id`: BigInteger.
- `cancelled_by_id`: BigInteger, nullable.
- `cancelled_at`: DateTime(timezone=True), nullable.
- `cancellation_reason`: `String`, nullable.
- `created_at`: DateTime(timezone=True), `server_default=func.now()`.
- `updated_at`: DateTime(timezone=True), `server_default=func.now()`, **with**
  `onupdate=func.now()` — unlike the ledger, this table legitimately gets touched again on
  cancel.

`__table_args__`:
1. `Index("ix_employee_leave_assignments_employee_type_year", "employee_master_id",
   "leave_type_master_id", "leave_year")` — listing/lookup.
2. Partial unique index preventing duplicate system-sourced grants — the actual mechanism that
   satisfies design doc §16/§20's "prevent accidental duplicate annual entitlement assignment":
   ```sql
   CREATE UNIQUE INDEX uq_leave_assignment_system_source
     ON employee_leave_assignments
        (care_delivery_program_master_id, employee_master_id, leave_type_master_id,
         leave_year, source_type)
     WHERE source_type IN ('Policy','OpeningBalance','CarryForward') AND status = 'Active';
   ```
   This is a layer above the ledger's own `uq_leave_ledger_system_txn` ([[42]]) — that index only
   catches a same-`effective_date` collision; this one catches a same-`leave_year` collision
   regardless of date, which is what "don't double-assign this year's entitlement" actually
   means. `Manual` stays unconstrained (multiple manual adjustments are always legitimate,
   matches the existing `/ledger/adjust` endpoint's behavior). The `status = 'Active'` clause lets
   a cancelled-then-reassigned year through.

### Ledger traceability — extend the existing table, additively

Add one nullable column to **the already-migrated** `employee_leave_balance_ledgers`
(`backend/app/models/employee_leave_balance_ledger.py`):
- `employee_leave_assignment_id: Mapped[int | None] = mapped_column(ForeignKey("employee_leave_assignments.id"))`

This is a plain additive nullable FK — it does not touch the append-only invariant (no existing
row is rewritten; new rows populate it going forward) and mirrors how `leave_request_detail_id`
already exists on this same table for the identical purpose (tracing a ledger row back to the
business event that created it). Without it, design doc §22's "ledger entries can be traced to
the originating assignment" (and §24's "clicking a row should open the source record") has no
column to join on.

### New audit model — `backend/app/models/leave_assignment_audit.py`

`LeaveAssignmentAudit` → `leave_assignment_audits`. Mirrors `leave_policy_audit.py` and
`leave_request_audit.py` exactly (append-only, no `updated_at`):
- `id`: BigInteger PK.
- `care_delivery_program_master_id`: FK, indexed (tenant).
- `employee_leave_assignment_id`: FK `employee_leave_assignments.id`, indexed.
- `action`: `String(20)` — `CREATED|CANCELLED`.
- `changes`: `String(2000)`, nullable.
- `performed_by_id`: BigInteger.
- `created_at`: DateTime(timezone=True), `server_default=func.now()`.

Register all three (`EmployeeLeaveAssignment`, `LeaveAssignmentAudit`, and the ledger model
already registered — no new import needed for the column addition) in
`backend/app/models/__init__.py`, one `# noqa: F401` line each for the two new files.

### Migration

```
uv run python scripts/migrate.py revision --autogenerate -m "leave assignments and ledger traceability"
```

Review before applying — hand-edit to confirm/add:
- The partial unique index above (autogenerate may emit it as a plain index; fix the `WHERE`
  clause by hand, same caution [[42]] used for the ledger's own partial index).
- The new nullable `employee_leave_assignment_id` column and its FK on
  `employee_leave_balance_ledgers`.

Apply with `uv run python scripts/migrate.py upgrade heads` — **not** bare `alembic upgrade head`
(CLAUDE.md's nhforms two-head rule).

## Acceptance criteria

- [x] `employee_leave_assignment.py` and `leave_assignment_audit.py` exist, one table per file,
      registered in `models/__init__.py`.
- [x] `employee_leave_balance_ledgers` has the new nullable `employee_leave_assignment_id`
      column and FK, verified with `\d employee_leave_balance_ledgers` in `psql`; no existing
      column, index, or row is altered.
- [x] Migration applies cleanly on top of the current head; `uq_leave_assignment_system_source`
      exists with the correct partial `WHERE` clause (verified with `\d
      employee_leave_assignments`).
- [x] A duplicate `Policy`/`OpeningBalance`/`CarryForward` insert for the same
      `(tenant, employee, leave_type, leave_year)` with `status='Active'` is rejected by the DB
      — spot-checked in a rolled-back transaction.
- [x] Two `Manual` assignments for the same `(employee, leave_type, leave_year)` insert without
      conflict.
- [x] No CompOff/Import/Reversal value is accepted anywhere in this task's schema-level
      constraints (enforcement of the *value set* itself is application-level in [[62]]; this
      task only needs the column to exist as `String(20)`).

Completed: 2026-08-19

Note: landing this required an unplanned detour — a from-scratch DB build hit a real,
pre-existing bug in the migration history around `shift_masters` (two branches, `c634b889524f`
and `b703598a21b3`, both created it with divergent shapes after the `85cb815` git merge, since
alembic's merge revision `ed0bc9593ce5` never reconciled the actual schema drift between them).
Fixed as part of landing this task — see the retroactive reconciliation note at the top of
`alembic/versions/b703598a21b3_recreate_shift_related_tables.py`. Verified the local dev DB and
test DB now build cleanly from empty and the resulting `shift_masters` shape matches
`app/models/shift_master.py` exactly.

Unrelated, pre-existing gap noticed in passing and deliberately left alone (out of this task's
scope): `test_admin_organizations.py`, `test_engagement*.py`, `test_hr_attributes.py`,
`test_organizations.py`, and `test_webhooks.py` fail against a truly from-scratch DB because some
fixtures expect `seed_dev.py`-style seed data (e.g. a pre-existing super-admin role/dashboard)
that a bare migration build never runs — `conftest.py`'s own comment notes "tests share the dev
DB." All `test_leave.py` tests (146) pass clean on the rebuilt DB.

