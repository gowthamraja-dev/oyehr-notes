---
task: 235
title: Say why a day is locked, and warn before a shift edit locks history
status: done
depends_on: [234]
---

# 235 — Say why a day is locked, and warn before a shift edit locks history

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Source:
`.plans/attendance-shifts-leave-holidays-todo.md` item **ATT-D1** / ATT-S2.

## Why
Today the only signal is a bare 423 *"Attendance for 2026-09-30 is locked"*. HR can't tell that the
lock came from a shift edit, who can lift it, or that saving a shift form locks every past computed
day of every assigned employee. A cosmetic edit (name/colour/code) doesn't lock; **timing** and
**policy** edits (grace, OT, regularization, late-mark) and **week-off** edits do
(`_change_severity` in `backend/app/modules/shifts/service.py` ~310-322).

**Two lock causes** (found while starting 234): a shift edit (above) **and** the automatic lock once the
shift's `regularization_window_days` has passed (`attendance_recompute_service.py:755-756`). The 423 text
must not claim a shift edit was the cause — keep it cause-neutral, e.g. *"…is locked (days are frozen
after a shift configuration change or once the regularization window closes)"*.

## Scope
1. **Clear 423 text** at all four sites (`attendance/service.py:945,1050,1591,1964`), via one helper:
   *"Attendance for 30-Sep-26 is locked (days are frozen after a shift configuration change or once the
   regularization window closes). HR can correct it with a reason — see Regularize › Override."* (dd-MMM-yy per `hrms-date-format`).
   Employee-facing wording: *"This day is locked. Ask HR to correct it."*
2. **Impact preview before a shift edit saves.** New read-only endpoint
   `GET /shifts/{id}/lock-impact?kind=timing|policy|week_off` (or a `dry_run=true` flag on PATCH)
   → `{kind, employees_affected, days_to_lock}` using the same filters as
   `_lock_computed_attendance_for_shift` (`attendance_date < today`, `attendance_status IS NOT NULL`,
   `is_locked = false`). Scoped by `principal.tenant_id`; gated like the shift update route.
3. **Confirm dialog in the shift editor** (`useConfirm()` hook, never `window.confirm`): if the edit is
   `timing`/`policy`/`week_off` and `days_to_lock > 0`, ask *"This will freeze N past days for M
   employees. Continue?"*; cosmetic edits skip it.
4. Fix the stale comment at `backend/app/models/employee_attendance_detail.py:70` ("never set true").
5. Log the lock count at INFO in `_lock_computed_attendance_for_shift` (shift id, rowcount).

**Not in scope:** removing the lock (deliberate); the override itself (task 234); month-close (ATT-N1).

## Files
- `backend/app/modules/attendance/service.py` — message helper
- `backend/app/modules/shifts/service.py`, `router.py`, `schemas.py` — lock-impact endpoint
- `backend/app/models/employee_attendance_detail.py` — comment
- `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/ShiftDefaults.tsx` — confirm before save; `frontend/src/lib/api.ts` — client call
- `backend/app/tests/modules/test_shifts.py`, `test_attendance.py`

## Acceptance criteria
- [ ] All four 423 sites return the new text through one helper; employee vs HR wording differs.
- [ ] `lock-impact` returns correct counts for timing/policy/week_off, 0 for cosmetic; cross-tenant isolated; 401/403 covered.
- [ ] Editing a shift's timing with past computed days shows the confirm; cancel leaves the shift unchanged; cosmetic edit shows none.
- [ ] Stale model comment corrected.
- [ ] `uv run pytest` green; manual check in the browser on the General shift.

Completed: 2026-10-23
Note: closed with backend tests green (the 235 lock-impact/423 tests, the 4 new 236 analytics tests) and `tsc` clean; the full suite had 88 pre-existing failures identical with and without this change. Browser checks were not done at close.
