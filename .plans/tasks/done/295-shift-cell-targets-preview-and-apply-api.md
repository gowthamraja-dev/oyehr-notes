---
task: 295
title: Shift scheduling — apply one shift to arbitrary selected cells (preview + apply API)
status: done
depends_on: []
---

# 295 — Shift scheduling: apply a shift to arbitrary selected cells (preview + apply API)

## Scope
`PUT /shifts/employee-shifts/range` only takes a contiguous window (`from_date`..`to_date`, optional `weekdays`) for a list of employees, so it cannot express a drag-selected,
ragged set of cells. Add the counterpart of regularization's `targets: [{employee_id, dates[]}]`:

- `POST /shifts/employee-shifts/cells/preview` — body `{targets: [{employee_master_id, dates[]}], shift_master_id | change_location_only, work_location_master_id,
  holiday_calendar_master_id, skip_week_offs, overwrite_manual}`; classifies every (employee, date) as `will_change` / `unchanged` / `week_off` / `locked` /
  `outside_employment` / `manual_protected` / `no_standing_shift` (same reasons as `RangeSkipOut`). Writes nothing.
- `PUT /shifts/employee-shifts/cells` — same body; re-classifies at apply time (never trusts the preview) and writes through the SAME single-day writer
  (`_set_employee_shift_for_day` / `_plan_and_apply_employee_days`) — **no second writer**. One savepoint per employee, so one employee failing does not undo the rest
  (partial success is HTTP 200, result is `SetEmployeeShiftForRangeOut`).

Validation: ≤ 500 employees, ≤ 92 distinct dates per employee, ≤ 5,000 cells in total; a foreign (other-tenant / not-in-scope) employee id 404s the whole call (as the regularize
bulk does); `shift_master_id` / `change_location_only` rules reuse `_check_location_only`. Gate: `UPDATE SHIFT` like the range route; scoping identical to `list_shift_roster`
(whole org for `sees_whole_org(..., "ATTENDANCE")`, otherwise direct reports). Plain `EncryptedRoute` router already in use for `/shifts` — keep it.

NOT in this task: any frontend (297/298), roster filter changes (296), docs (299).

## Files
- `backend/app/modules/shifts/schemas.py` (`CellTargetIn`, `SetEmployeeShiftForCellsIn`, preview out)
- `backend/app/modules/shifts/service.py` (`preview_employee_shift_cells`, `set_employee_shift_for_cells`; group each employee's dates into runs only if that reuses the range planner,
  otherwise loop single days)
- `backend/app/modules/shifts/router.py`
- `backend/app/tests/modules/test_shifts.py` (or the existing shifts test module)

## Acceptance criteria
- [x] Preview classifies locked / week-off / outside-employment / manual-protected / unchanged days and writes nothing
- [x] Apply re-classifies, writes via the existing day writer, one savepoint per employee; partial success returns 200 with per-employee skips
- [x] A locked day is never written; a week-off day is skipped when `skip_week_offs`
- [x] Out-of-scope / other-tenant employee id → 404 for the whole call; a manager only reaches direct reports (403 otherwise)
- [x] Missing `UPDATE SHIFT` → 403; unauthenticated → 401; size limits → 422
- [x] Encrypted round-trip test; tenant-scoping test
- [x] `uv run pytest` for the touched test module passes

## Built (2026-10-28)
- Routes `POST /shifts/employee-shifts/cells/preview` and `PUT /shifts/employee-shifts/cells` (`router.py`), both `UPDATE ATTENDANCE`, on the existing encrypted `/shifts` router.
- `service.py`: `_plan_and_apply_employee_days` gained `dry_run` (classifies and counts, writes nothing) — preview and apply run the same planner, so there is no second classifier or
  writer. `_prepare_cell_selection` (validation + scope), `_run_cell_selection` (shared body), `preview_employee_shift_cells`, `set_employee_shift_for_cells`. Apply wraps each
  employee in `db.begin_nested()` with its own totals dict (merged only on success); a `SQLAlchemyError` rolls that employee back alone and lands in `failed`.
- `schemas.py`: `CellTargetIn`, `SetEmployeeShiftForCellsIn` (caps `MAX_CELL_EMPLOYEES=500`, `MAX_CELL_DATES_PER_EMPLOYEE=92`, `MAX_CELLS=5000`; dates de-duplicated and sorted),
  `CellsEmployeeResultOut` (= range result + `assigned_dates`), `CellsFailedOut`, `SetEmployeeShiftForCellsOut` (= `SetEmployeeShiftForRangeOut` + `failed`).
  Contract note for 298: the preview returns the SAME shape as apply; `assigned_dates` are the days that would be / were written.
- Selected dates need not be contiguous: runs only join consecutive days, so a gap in the selection stays a gap (tested: Mon + Wed/Thu → two rows).
- Tests: 12 in `test_shifts.py` (`test_shift_cells_*`, `test_encrypted_shift_cells_roundtrip`). `test_shifts.py` + `test_shift_range_carve.py`: 195 passed; `-k wfh`: 51 passed
  (the approved-WFH path shares the planner).

Completed: 2026-10-28
