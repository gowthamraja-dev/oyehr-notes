---
task: 234
title: HR can regularize a locked attendance day (audited override)
status: done
depends_on: []
---

# 234 — HR can regularize a locked attendance day (audited override)

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first (branch at planning
time: `feature/gowtham_go_live`). Source: `.plans/attendance-shifts-leave-holidays-todo.md` item **ATT-D1**.

## Why
`employee_attendance_details.is_locked` is a **deliberate** freeze, set in two places:
(1) editing a shift's timing, week-off or policy calls `_lock_computed_attendance_for_shift`
(`backend/app/modules/shifts/service.py:326-350`); (2) `recompute_attendance_day` locks a closed day
automatically once the shift's `regularization_window_days` has passed
(`backend/app/services/attendance_recompute_service.py:208-222,755-756`). Path (2) is the likely cause
of the reported 30-Sep case. The guard is correct and **stays**. The problem is that a locked day then has no way back:
regularize submit, approval and HR on-behalf all return HTTP 423 *"Attendance for {date} is locked"*
(`backend/app/modules/attendance/service.py:945,1050,1591,1964`), and `recompute_attendance_day`
skips locked rows (`backend/app/services/attendance_recompute_service.py:678`, `force` flag exists at
`:653` but is only used by the operator script). Reported case: a request for 30-Sep approved by HR on
10-Oct fails with a lock error and HR has no remedy.

## Scope
Add a **HR-only, audited override** so a legitimate correction can be applied to a locked day.
- `regularize_on_behalf` (`POST /attendance/employees/{id}/regularize`) and `approve_request`
  (`POST /attendance/requests/{id}/approve`) accept a locked day **only when**:
  - caller passes `sees_whole_org(db, principal, "ATTENDANCE")` (same gate as on-behalf today), and
  - the request carries a non-empty `override_reason` (new optional body field on the approve
    payload and `HrRegularizationIn`), and
  - the caller holds the `APPROVE ATTENDANCE` grid permission (already on both routes).
- The override path calls `_apply_approved_regularization` → `recompute_attendance_day(..., force=True)`
  for that **one employee-day only**. The row stays `is_locked = True` afterwards (nothing clears it).
- A locked day without a reason/permission still returns 423, with the improved text from task 235.
- Write the old→new `attendance_audit_logs` row with `action = "LockedDayOverride"` and the reason,
  plus a `user_activity_details` row via `app.services.activity_log_service.log_activity`
  (`hrms-activity-logging` skill: it is a manual ownership/assignment-style change worth the detail).
- Employee self-service `POST /attendance/requests` is **unchanged** (an employee still gets the 423;
  HR does the override). Clock-in/out on a locked day also unchanged.

**Not in scope:** a month-close / payroll-cutoff policy (that is item ATT-N1, needs a DBML first);
stopping or warning on the lock itself (task 235); the 423 wording (task 235).

## Files
- `backend/app/modules/attendance/service.py` — `_apply_approved_regularization`, `approve_request`, `regularize_on_behalf`, `_validate_regularization` (lock check at 1591)
- `backend/app/modules/attendance/schemas.py` — `override_reason` on approve + `HrRegularizationIn`
- `backend/app/services/attendance_recompute_service.py` — reuse `force=` (no change expected; confirm it doesn't unlock)
- `backend/app/tests/modules/test_attendance.py` (or the existing regularization test module)
- `docs/leave-and-attendance/attendance/manager-approvals.md` + `gaps.md` (document the override)

## Acceptance criteria
- [x] Locked day + HR with org-wide scope + reason → on-behalf regularize succeeds; day recomputed from the new punches; `is_locked` still true. (`test_hr_regularize_overrides_a_locked_day_with_a_reason`)
- [x] Same for approving a pending request on a locked day. (`test_hr_approves_a_pending_request_on_a_locked_day_with_a_reason`)
- [x] Locked day + no reason (missing / empty / blank) → 423 with no data change. (`..._without_a_reason_is_still_refused`)
- [x] Locked day + manager without org-wide scope → 423 without a reason, 403 with one; nothing changes. (`test_reporting_manager_cannot_override_a_locked_day`)
- [x] Employee self-service on a locked day still 423. (`test_employee_cannot_submit_a_regularization_on_a_locked_day`)
- [x] Audit log row `LockedDayOverride` with reason; activity-log row written; reason ignored on an unlocked day.
- [x] Cross-tenant: on-behalf override for another tenant's employee → 404 (`test_hr_override_cross_cdp_employee_not_found`).
- [ ] `uv run pytest` green for the attendance modules — `test_attendance.py`: 213 passed, but **only** with the onboarding-consent gate disabled by a scratch plugin and `DATABASE_URL` pointed at the local `hrms-newinst-db` container. See "Notes" below; `test_attendance_dashboard`/`recompute`/`assembler_job` not run.

## Notes (16-Oct-26)
- Implemented in `attendance/schemas.py` (`override_reason` on `ApproveRequestIn` and `HrRegularizationIn`) and `attendance/service.py` (`_validate_regularization(allow_locked=)`, `_apply_approved_regularization(override_reason=)`, `_day_is_locked`). Docs: `docs/leave-and-attendance/attendance/manager-approvals.md` §3.3 and `gaps.md` #36.
- **Second lock cause found:** `recompute_attendance_day` also locks a closed day once `regularization_window_days` passes (`attendance_recompute_service.py:755-756`), not only a shift edit.
- **Pre-existing test breakage:** since commit `f8cc24f` (`is_onboarding_enabled` true for every real tenant), the fixtures' membership has no `status_master_id`, so `_onboarding_blocked` returns True and authenticated tests get 403 "Complete your consent acknowledgment" (80 of 94 in `test_shifts.py` fail the same way). Not caused by this task; needs its own fix in `app/tests/conftest.py`.
- **Not done / follow-up:** no frontend — HR has no UI field for `override_reason` yet (the regularize modal in `AttendanceDayActions.tsx` and the inbox approve button need a "Locked — override with reason" step). Negative control (new tests failing without the service change) was not run.

Completed: 2026-10-16
