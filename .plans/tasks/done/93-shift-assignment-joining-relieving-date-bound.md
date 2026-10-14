---
task: 93
title: Shift assignment has no bound against employee joining_date/relieving_date
status: done
depends_on: []
---

# 93 — Shift assignment has no bound against employee joining_date/relieving_date

## Scope

`EmployeeMaster` has `joining_date` and `relieving_date` (both `Date | None`,
`backend/app/models/employee_master.py:29-30`), but none of the four shift-assignment write
paths in `backend/app/modules/shifts/service.py` — `assign_employee_shift` (line 457),
`bulk_assign_employee_shift` (line 493), `set_employee_shift_for_day` /
`_set_employee_shift_for_day` (lines 653-770, used by the Weekly roster grid's per-day
override), `auto_assign_shifts` (line 872) — validate `effctv_dt`/`target_date` against either
field. Confirmed by grep: `joining_date`/`relieving_date` do not appear anywhere in
`shifts/service.py` or `shifts/schemas.py`. This is the reported "even before joining shifts can
be assigned" bug: a manager can pick any date via the Weekly roster's week navigator (no lower
bound, `ShiftScheduling.tsx:73,162`) or the bulk modal's raw date input (no `min`,
`BulkAssignShiftModal.tsx:187-193`) and the assignment succeeds regardless of whether the
employee had even joined yet, or has already left.

Two symmetric rules to add:
- `effctv_dt`/`target_date` must be `>= employee.joining_date` (when `joining_date` is set —
  it's nullable, so `None` means no lower bound, matching how the rest of the codebase treats
  nullable config as "unrestricted," e.g. task 84's regularization fields).
- `effctv_dt`/`target_date` must be `<= employee.relieving_date` (when set) — a relieved
  employee shouldn't get shift assignments dated after their last working day.

**Out of scope**: this task does not touch [[92-shift-day-assignment-no-past-lock-guard]]'s
`is_locked` check — the two guards are independent (a date can fail one, both, or neither) and
should both run, in either order, inside the same write paths. Also out of scope: retroactively
validating/cleaning up assignment rows that already violate this (a one-off data-audit script,
if needed, is separate work).

## Changes

**1. `backend/app/modules/shifts/service.py`** — add a small shared validator near
`_require_employee` (~line 94):
```python
def _require_date_within_employment(emp: EmployeeMaster, target: date, *, field: str = "date") -> None:
    if emp.joining_date is not None and target < emp.joining_date:
        raise HTTPException(422, detail=f"{field} {target.isoformat()} is before {_display_name(emp)}'s joining date")
    if emp.relieving_date is not None and target > emp.relieving_date:
        raise HTTPException(422, detail=f"{field} {target.isoformat()} is after {_display_name(emp)}'s relieving date")
```
(`_display_name` is defined below this at line 586 — move it above `_require_employee`, or
inline a simpler message without the name; either is fine.)

Call it in:
- `assign_employee_shift` (after `emp = _require_employee(...)`, line 458) on `payload.effctv_dt`.
- `set_employee_shift_for_day` (after `emp = _require_employee(...)`, line 753) on
  `payload.target_date`.
- `bulk_assign_employee_shift` (in the per-employee loop, line 514-517, right after
  `emp = _require_employee(...)`) — same per-employee-skip treatment as the existing "already has
  a shift" case (line 528-533) and as task 92's locked-day skip: violating employees go to
  `skipped`, not a whole-batch 422, since one bad employee in a bulk selection shouldn't block
  the rest.
- `auto_assign_shifts`'s per-day loop (line 897-930) — a day outside `[joining_date,
  relieving_date]` should behave like `no_standing_shift_count` (skip and count), not raise,
  since auto-assign already treats "nothing applicable for this employee/day" as a soft outcome
  rather than an error. Add a `no_standing_shift_count`-style counter (e.g.
  `outside_employment_count`) to `AutoAssignShiftsOut`.

**2. `backend/app/modules/shifts/schemas.py`** — extend `AutoAssignShiftsOut` with the new
counter field (alongside whatever `locked_skipped_count` task 92 adds, if that task lands
first — otherwise add both in whichever task lands second, don't duplicate the field).

**3. Frontend, `BulkAssignShiftModal.tsx`** — while touching this file's date input, also fix
the separate convention violation: it uses a bare `<input type="date">`
(lines 187-193) instead of the shared `DateField` component
(`frontend/src/components/ui/DateField.tsx`), which every other date field in the app uses for
the dd-MMM-yy display format (see CLAUDE.md "Frontend styling" / the `hrms-date-format` skill).
Swap it for `<DateField value={effctvDt} onChange={setEffctvDt} />`. A `min` bound isn't
practical here since one date applies to potentially many employees with different
`joining_date`s — leave bounding to the backend's per-employee skip from change #1, and surface
the new skip reason through the existing `skipped` UI (lines ~108-115, already renders
`reason` strings from the API — no frontend change needed there beyond confirming the new
reason text displays correctly).

**4. Frontend, `ShiftScheduling.tsx`** — no date *input* to swap (the day is picked by clicking
a week-grid cell, not typed), so no `DateField` change needed here. Leave the 422's message
surfacing through the existing `saveError` banner in `AssignShiftModal` (same as task 92).

## Files
- `backend/app/modules/shifts/service.py`
- `backend/app/modules/shifts/schemas.py`
- `frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`
- `backend/app/tests/modules/test_shifts.py`

## Tests
`backend/app/tests/modules/test_shifts.py`:
- Employee with `joining_date = 2026-06-01`: `POST /shifts/employee-shifts` with
  `effctv_dt` before that date → 422; on/after → succeeds.
- Employee with `relieving_date` set: `PUT /shifts/employee-shifts/day` for a `target_date`
  after it → 422; on/before → succeeds.
- Employee with `joining_date = None` (never set) → no lower bound applies, any past date
  succeeds (matches the nullable-config convention).
- `POST /shifts/employee-shifts/bulk` with one of several employees whose `joining_date` is
  after the chosen `effctv_dt` → that employee lands in `skipped` with a clear reason, others
  still `assigned`.
- `POST /shifts/employee-shifts/auto-assign` over a range that starts before an employee's
  `joining_date` → days before it are excluded and counted, days on/after it are assigned
  normally.

## Acceptance criteria
- [x] All four write paths reject (or, for bulk/auto-assign, skip-and-report) a date outside
      `[joining_date, relieving_date]`, treating an unset bound as "no restriction" on that side.
      Implemented via two shared helpers — `_require_date_within_employment` (raises, for the
      single-employee paths) and `_within_employment` (boolean, for the per-item skip loops in
      bulk/auto-assign) — rather than four separate copies of the two-condition check.
- [x] `BulkAssignShiftModal.tsx` uses `DateField`, not a bare `<input type="date">`. (Its
      `disabled={saving}` behavior was dropped in the swap — `DateField` doesn't expose a
      `disabled` prop, matching every other `DateField` usage in the codebase; the Assign button
      itself still guards against double-submission.)
- [x] `uv run pytest app/tests/modules/test_shifts.py -q` passes (79 total, including the 6 new
      cases above). Also ran `test_attendance.py` together — only the 2 pre-existing, unrelated
      pagination failures (confirmed earlier this session, reproduce identically with this
      task's changes stashed).
- [x] Frontend typecheck (`npx tsc --noEmit`) clean, no errors from the `BulkAssignShiftModal.tsx`
      change.
- [ ] Manual verification via the actual Weekly roster grid (browser) not performed this
      session — covered instead by the equivalent backend test
      (`test_set_employee_shift_for_day_rejects_after_relieving_date`), which exercises the same
      `PUT /shifts/employee-shifts/day` endpoint the grid calls.

Completed: 2026-09-02
