---
task: 62
title: Leave assignment service + API — create, list, get, cancel; loosen ledger view to managers
status: done
depends_on: [61]
---

# 62 — Leave assignment service + API — create, list, get, cancel; loosen ledger view to managers

## Discussion

Builds on [[61]]'s tables. This is the backend half of design doc §17/§18/§23 — "assignment and
ledger credit created atomically, in one database transaction" — using the primitives already
proven in [[43]]/[[45]] (`ledger_service.write_ledger_entry`, the advisory lock, the
`_require_admin`/`_require_manager_or_admin_for` predicates already established in
`leave/service.py`).

### Permissions — stay role-based, do not invent a permission-string system

The design doc (§29) proposes granular permission strings (`leave.assignment.create`,
`leave.ledger.view`, etc.). **This codebase has no permission-string store anywhere** — confirmed
by grep across `backend/app`, `docs/`, `.plans/`: the only "permission" hits are the vendored
`nhforms` module's own docstrings noting *"HRMS has no permission store yet."* Authorization here
is JWT-claim role-based (`AuthPrincipal.is_admin`, plus the manager-of-direct-report predicate),
and every other endpoint in this module uses exactly that. Introducing a new permission-string
system is a separate, much larger initiative — do not start it here. Map the design doc's
permission *tiers* onto the existing two predicates instead:

| Design doc permission | This task's actual gate |
| --- | --- |
| `leave.assignment.create`, `leave.ledger.adjust` | `_require_admin` (HR/admin only — same tier as the existing `/ledger/adjust`) |
| `leave.assignment.view`, `leave.ledger.view` | `_require_manager_or_admin_for` (manager of the target's direct reports, or admin — same tier as `get_employee_balances`) |

This also means **loosening** `get_employee_ledger` (`service.py:1777-1796`), which is
`_require_admin`-only today per [[45]]'s explicit note *"no manager-facing mockup for this
(gaps.md #9); keep admin-only until a UI need for managers appears"* — that UI need now exists
([[65]]). Switch it to `_require_manager_or_admin_for`, identical to `get_employee_balances`.

### `ledger_service.write_ledger_entry` — one additive parameter

Add `assignment_id: int | None = None` to `write_ledger_entry`'s signature
(`backend/app/services/ledger_service.py:42-85`), setting it on the constructed
`EmployeeLeaveBalanceLedger` row's new `employee_leave_assignment_id` column. No existing caller
([[44]]'s apply-time gate, [[45]]'s approve/reject/cancel) passes it, so their behavior is
unchanged — this is purely additive.

### `create_leave_assignment` — the atomic sequence

1. `_require_admin(principal)`.
2. Resolve + validate the target employee (`_get_employee_in_tenant`) and leave type
   (`_get_leave_type` — must be `is_active`, `NOT archive`).
3. Validate `source_type ∈ {Policy, Manual, OpeningBalance, CarryForward}` — reject `CompOff`/
   anything else with `422`, message pointing at "comp-off has no earning mechanism yet" (gaps.md
   #1), so a caller understands *why*, not just that the value is invalid.
4. Validate `assigned_units`: `> 0` for `Policy`/`OpeningBalance`/`CarryForward`; `!= 0` (either
   sign) for `Manual`. `422` otherwise.
5. Validate `effective_from <= effective_to` when `effective_to` is given.
6. Require non-blank `reason` when `source_type == 'Manual'` (`422` otherwise) — same
   `min_length=1`-equivalent rule `LeaveLedgerAdjustIn.remarks` already enforces for the endpoint
   this supersedes.
7. Resolve `leave_year` from `effective_from` (reuse `resolve_leave_policy`/`resolve_leave_year`,
   same call shape as `_balances_for_employee`).
8. `ledger_service.lock_ledger(db, tenant_id, employee.id, leave_type.id, leave_year)` as the
   **first** statement of the transaction — same discipline as every other ledger writer.
9. Insert `EmployeeLeaveAssignment(status="Active", ...)`, `db.flush()` to get its id.
10. Map `source_type` → `txn_type` per [[61]]'s table (`Policy→Accrual`, `Manual→Adjustment`,
    `OpeningBalance→Opening`, `CarryForward→CarryForward`) and call
    `ledger_service.write_ledger_entry(db, tenant_id, employee.id, leave_type.id, leave_year,
    txn_type, assigned_units, effective_from, assignment_id=assignment.id, remarks=reason or
    f"Leave assignment #{assignment.id}", created_by_id=principal.user.id)`.
11. Catch `IntegrityError` from step 10's insert (the partial unique index on
    `employee_leave_assignments` from [[61]] fires *before* the ledger insert, on the
    `db.flush()` in step 9 — verify which flush actually triggers it and catch there) → rollback,
    `409` naming that an active `Policy`/`OpeningBalance`/`CarryForward` assignment already exists
    for this employee/type/year.
12. `assignment.employee_leave_balance_ledger_id = ledger_row.id`.
13. Write `LeaveAssignmentAudit(action="CREATED", changes=<one-line summary: source_type,
    assigned_units, effective_from>, performed_by_id=principal.user.id)`.
14. `db.commit()`.

If any step fails, nothing commits — matches design doc §17's "there must never be: assignment
exists, ledger credit missing" (or vice versa).

### `cancel_leave_assignment`

1. `_require_admin(principal)`.
2. Load the assignment (tenant-scoped, `status == 'Active'`; `404` if not found, `409` if already
   `Cancelled`).
3. Require non-blank `cancellation_reason` (`422` otherwise).
4. Take the same advisory lock for the assignment's `(employee, leave_type, leave_year)`.
5. Load the original ledger row (`assignment.employee_leave_balance_ledger_id`).
6. Write a `Reversal` ledger row: `write_ledger_entry(..., txn_type="Reversal",
   quantity=-original_row.quantity, effective_date=today, assignment_id=assignment.id,
   reversal_of_id=original_row.id, remarks=cancellation_reason,
   created_by_id=principal.user.id)`.
7. Set `status="Cancelled"`, `cancelled_by_id`, `cancelled_at=now()`, `cancellation_reason`.
8. Write `LeaveAssignmentAudit(action="CANCELLED", changes=cancellation_reason)`.
9. `db.commit()`.

**Deliberately does not gate on whether the credit has already been partly consumed by approved
leave** — reversing it can legitimately drive the balance negative when
`allow_negative_balance` isn't set on the leave type. This mirrors the existing precedent for LOP
going negative (`ledger.md` §4.1) rather than inventing a new gate the design doc doesn't specify.

### `list_leave_assignments` / `get_leave_assignment`

`_require_manager_or_admin_for` (view tier). List supports `?leave_type_master_id=&source_type=&
status=`, ordered `effective_from desc`.

### Schema additions — `backend/app/modules/leave/schemas.py`

- `LeaveAssignmentIn`: `leave_type_master_id: int`, `source_type: str`,
  `assigned_units: Decimal`, `effective_from: date`, `effective_to: date | None = None`,
  `reason: str | None = None`, `reference: str | None = None`.
- `LeaveAssignmentOut`: `id, employee_master_id, leave_type_master_id, leave_year, source_type,
  assigned_units, effective_from, effective_to, reason, reference, status,
  employee_leave_balance_ledger_id, created_by_id, created_at, cancelled_at,
  cancellation_reason`.
- `LeaveAssignmentCancelIn`: `cancellation_reason: str = Field(min_length=1)`.
- Extend `LeaveLedgerRowOut` (schemas.py:434-443) with `assignment_id: int | None` sourced from
  the new `employee_leave_assignment_id` column — this is what lets [[65]]'s ledger table link a
  row back to its assignment (design doc §24: "clicking a row should open the source record").

### Endpoints — `backend/app/modules/leave/router.py` (same `EncryptedRoute` router)

| Method | Path | Who | Notes |
| --- | --- | --- | --- |
| POST | `/employees/{id}/leave-assignments` | A | `create_leave_assignment` |
| GET | `/employees/{id}/leave-assignments` | M, A | `list_leave_assignments`, filters above |
| GET | `/employees/{id}/leave-assignments/{assignment_id}` | M, A | `get_leave_assignment` |
| POST | `/employees/{id}/leave-assignments/{assignment_id}/cancel` | A | `cancel_leave_assignment` |
| GET | `/employees/{id}/ledger` | M, A *(was A only)* | unchanged shape + new `assignment_id` field |

The existing `POST /employees/{id}/ledger/adjust` stays as-is (unchanged behavior) — it remains
the raw escape hatch; it is simply no longer the *only* way to write an `Opening`/`Adjustment`-
style row with a friendly source label attached.

## Files

- `backend/app/services/ledger_service.py` (add `assignment_id` param)
- `backend/app/modules/leave/router.py`, `schemas.py`, `service.py`

## Tests

- Create Policy/OpeningBalance/CarryForward assignment → assignment row + matching ledger row
  (`Accrual`/`Opening`/`CarryForward` respectively), `employee_leave_balance_ledger_id` set on
  the assignment, `employee_leave_assignment_id` set on the ledger row.
- Create Manual without `reason` → `422`; with `assigned_units == 0` → `422`.
- Create with `source_type="CompOff"` → `422`.
- Create with `assigned_units <= 0` for Policy/Opening/CarryForward → `422`.
- Duplicate Policy assignment, same employee/type/year → `409`, no second ledger row written.
- Two Manual assignments, same employee/type/year → both succeed.
- Non-admin (manager, employee) → `403` on create/cancel.
- `GET .../ledger` and `GET .../leave-assignments`: manager of a direct report → `200`; manager
  of a non-report → `403`; admin → `200` for anyone in the CDP.
- Cancel: writes exactly one `Reversal` row (`quantity = -original`), `status→Cancelled`; cancel
  again → `409`; cancel without `cancellation_reason` → `422`.
- Cross-tenant employee/leave-type id → `404`/`403` (existing scoping helpers reused).

## Acceptance criteria

- [x] Assignment and its ledger credit are created in one transaction — no code path can produce
      one without the other.
- [x] Duplicate system-sourced (Policy/Opening/CarryForward) assignment for the same
      employee/type/year is rejected with a clear `409`; Manual is never blocked this way.
- [x] `GET /employees/{id}/ledger` is reachable by a manager for their own direct reports (no
      longer admin-only), and still `403`s for a non-report.
- [x] Cancellation writes a `Reversal` row, never mutates the original ledger row.
- [x] Every new route passes the standard 401/403/cross-tenant/encrypted-round-trip sweep
      (finished in [[63]]).

Completed: 2026-08-19

Note: the plan's step ordering (insert assignment, then ledger row, then link) has a genuine
circular-FK problem — `employee_leave_assignments.employee_leave_balance_ledger_id` is NOT NULL,
but the ledger row can't carry the assignment's id until the assignment has one. Resolved during
implementation by writing the ledger row first (it needs no assignment id yet), then the
assignment row (already knows the ledger row's id), then stamping the ledger row with the
assignment id — all three inserts flush before any commit, so an `IntegrityError` at either
point (the partial unique index on `employee_leave_assignments`) rolls back both, preserving the
atomicity guarantee. One pre-existing test (`test_get_employee_ledger_manager_forbidden`) asserted
the old admin-only behavior this task deliberately changes — updated in place plus a new
non-report-403 test, rather than left red. Added 8 new tests + fixed 1 in the same change,
covering the "Tests" list above; `uv run pytest` on `test_leave.py`: 155 passed. Full suite: 503
passed, 30 pre-existing unrelated failures (same count/names as before this task — see [[61]]'s
completion note on the seed-data gap), 0 new failures.

