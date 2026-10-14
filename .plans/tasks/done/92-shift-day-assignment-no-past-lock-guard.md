---
task: 92
title: Shift day-assignment paths can silently rewrite already-settled/locked history
status: done
depends_on: []
---

# 92 — Shift day-assignment paths can silently rewrite already-settled/locked history

## Scope

The Phase 1+2 "shift-edit safety" work (see git history, `e7382ac1f934` and the `update_shift`/
`replace_week_offs` lock calls at `backend/app/modules/shifts/service.py:364,420`) made changing
a **shift master's** timing/week-offs lock any `EmployeeAttendanceDetail` row already computed
under it (`_lock_computed_attendance_for_shift`, `service.py:207-230`). That protection has a
sibling gap: the **per-employee-per-day override** path used by the Weekly roster grid —
`set_employee_shift_for_day` → `PUT /shifts/employee-shifts/day` — never checks whether the
target day's attendance is already locked (or even already computed) before rewriting which
shift governs that day. Same gap in `assign_employee_shift`, `bulk_assign_employee_shift`, and
`auto_assign_shifts` — none of the four write paths in `backend/app/modules/shifts/service.py`
reference `EmployeeAttendanceDetail` at all (confirmed: no import/usage of it outside
`_lock_computed_attendance_for_shift`).

**Reproduction, matches the reported symptom ("showing the current shift change for previous
months"):** `ShiftScheduling.tsx`'s week navigator (`weekStart` state, `addDays(w, -7)`, lines
73, 162) has no lower bound — a manager can page back to any week, click any past day's cell,
and `AssignShiftModal` → `handlePick` → `setEmployeeShiftForDay` (lines 131-149, 322-344) always
succeeds, silently splitting/rewriting the `EmployeeShiftDetail` timeline for a day that may
already have `is_locked=True` attendance. If that day is later recomputed for any other reason
(a regularization approval, a manual admin trigger), it re-derives Present/Absent/late-minutes
under a shift the employee was never actually scheduled on. `is_locked` exists specifically to
prevent post-hoc rewrites of settled days (`attendance_recompute_service.py:391,481-482`) — this
is the one place that guarantee is currently unenforced.

**Explicitly out of scope**: relaxing or changing the lock itself, or the regularization-window
logic that sets `is_locked` — that's already built and tested (task 84's sibling work, and the
existing `test_recompute_auto_locks_once_regularization_window_elapses` /
`test_recompute_does_not_lock_when_regularization_unconfigured` in `test_attendance.py`). This
task only adds a *read* of that flag at the shift-assignment write paths.

## Changes

**1. `backend/app/modules/shifts/service.py`, `_set_employee_shift_for_day`
(lines 653-744)** — before mutating anything, check for a locked attendance row on
`target_date`:
```python
locked = db.scalar(
    select(EmployeeAttendanceDetail.id).where(
        EmployeeAttendanceDetail.care_delivery_program_master_id == principal.tenant_id,
        EmployeeAttendanceDetail.employee_master_id == employee_id,
        EmployeeAttendanceDetail.attendance_date == target_date,
        EmployeeAttendanceDetail.is_locked.is_(True),
    )
)
if locked is not None:
    raise HTTPException(422, detail=f"{target_date.isoformat()} is locked and can no longer be reassigned")
```
This needs `principal` threaded into `_set_employee_shift_for_day` (currently has it) — add the
check right after resolving `covering` (or before, doesn't matter — it must run before any
`db.add`/mutation). Applies to both callers: `set_employee_shift_for_day` (manual override,
raise straight through) and `auto_assign_shifts` (per-day loop) — for auto-assign, treat a
locked day the same as `manual_skipped`: skip it and count it separately (add a
`locked_skipped_count` to `AutoAssignShiftsOut`) rather than aborting the whole range, since
auto-assign is explicitly designed to be non-destructive/best-effort across many days.

**2. `assign_employee_shift` (line 457) and `bulk_assign_employee_shift` (line 493)** — these
set a *standing* `effctv_dt` going forward, not a single day, but nothing stops picking a past
`effctv_dt`. Add the same locked-day check for `effctv_dt` itself (the day the new assignment
would first apply from): if `EmployeeAttendanceDetail` for `(employee, effctv_dt)` is locked,
reject with the same message. `assign_employee_shift` raises (single employee, matches the
existing "must start after current assignment" 422 pattern at line 474). In
`bulk_assign_employee_shift`, treat it as a per-employee skip (`BulkEmployeeShiftSkip`, same
shape as the existing "already has a shift effective from ..." skip at line 528-533) so one
locked employee doesn't reject the whole batch.

**3. Frontend, `ShiftScheduling.tsx`** — the roster grid has no signal that a past cell is
locked/uneditable until the save call round-trips and fails. At minimum, surface the 422's
`detail` message in the existing `saveError` slot (`AssignShiftModal`'s error banner, already
wired — verify the message renders as-is, no change likely needed there). Optional
UX polish (not required for acceptance): grey out / disable cells whose date is locked, once the
roster response can carry that flag — out of scope for this task unless it's cheap; the
correctness fix is the backend guard, not the frontend affordance.

## Files
- `backend/app/modules/shifts/service.py`
- `backend/app/modules/shifts/schemas.py` (`AutoAssignShiftsOut` — add `locked_skipped_count`)
- `backend/app/tests/modules/test_shifts.py`

## Tests
`backend/app/tests/modules/test_shifts.py`:
- Seed an `EmployeeAttendanceDetail` row with `is_locked=True` for a past date; assert
  `PUT /shifts/employee-shifts/day` targeting that date returns 422 and the underlying
  `EmployeeShiftDetail` row is unchanged.
- Same for `POST /shifts/employee-shifts` (`assign_employee_shift`) with `effctv_dt` on a locked
  date.
- `POST /shifts/employee-shifts/bulk` with one of several employees locked on the target date →
  that employee comes back in `skipped`, the rest are `assigned`.
- `POST /shifts/employee-shifts/auto-assign` spanning a range that includes a locked day → that
  day is excluded from `assignments`, counted in the new `locked_skipped_count`, and the
  employee's `EmployeeShiftDetail`/`EmployeeAttendanceDetail` rows for that day are untouched.
- An *unlocked* past date (e.g. yesterday, still within the regularization window) is still
  freely reassignable — confirms the guard is specifically `is_locked`, not "any past date."

## Acceptance criteria
- [x] All four write paths (`set_employee_shift_for_day`, `assign_employee_shift`,
      `bulk_assign_employee_shift`, `auto_assign_shifts`) refuse to touch a day whose
      `EmployeeAttendanceDetail.is_locked` is true, without needing a second, separate lock
      mechanism for `EmployeeShiftDetail`. Implemented via one shared `_attendance_locked()`
      helper, not four separate copies of the query.
- [x] Bulk/auto-assign treat a locked day as a per-item skip, not a whole-batch failure.
- [x] `uv run pytest app/tests/modules/test_shifts.py app/tests/modules/test_attendance.py -q`
      passes (73 + 154 total, including the 5 new cases above; the 2 pre-existing
      `test_my_daily_pagination_and_date_range` / `test_employee_daily_pagination_matches_my_daily_shape`
      failures are unrelated — reproduce identically with this task's changes stashed).
- [x] Frontend: confirmed `setEmployeeShiftForDay`'s `_detailMessage(data, ...)` (already in
      `frontend/src/lib/api.ts`) surfaces the 422's `detail` text as `err.message`, and
      `ShiftScheduling.tsx`'s `handlePick` already routes that into `AssignShiftModal`'s
      `saveError` banner — no frontend change was needed for the rejection message to appear.
      The optional cell-greying UX polish was left out of scope, as the task allowed.

Completed: 2026-09-02
