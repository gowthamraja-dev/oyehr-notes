---
task: 269
title: Regularize on behalf — extract a no-commit per-day core and shared helpers
status: done
depends_on: []
---

# 269 — Regularize on behalf — extract a no-commit per-day core and shared helpers

## Scope
Pure refactor, **no behaviour change**, so the range endpoints (270) can regularize many days in one transaction. Today
`attendance/service.py:regularize_on_behalf` validates, writes the request + punches, recomputes, writes `log_activity`, fires `in_app.by_hr` and
**commits**, all in one function — it cannot be called in a loop with per-day savepoints.

1. Split `regularize_on_behalf` into:
   - `_regularize_one(db, principal, employee, payload: HrRegularizationIn, *, notify: bool) -> tuple[AttendanceRequestDetail, EmployeeAttendanceDetail, list[int]]`
     — everything from `_validate_regularization` through `_apply_approved_regularization`, the per-day `log_activity`, and `in_app.by_hr` only when `notify=True`.
     **Does not commit.**
   - `regularize_on_behalf` keeps its org-wide-scope check (`sees_whole_org(db, principal, "ATTENDANCE")` → `PermissionDenied`), calls
     `_regularize_one(..., notify=True)`, then `db.commit()` / `db.refresh(...)`, the `logger.info`, and `_approve_result_out(...)`. Same response, same status codes.
2. Hoist the helpers the attendance import owns into a shared service module `backend/app/services/attendance_day_helpers.py` and have the import handler use it
   (the attendance service will in 270) — do not import across modules. **As built:** `_shift_instants` already lived in `attendance_recompute_service.py` (the handler imported
   it from there), so it stays there as the single copy; the new module holds `closed_payroll_periods(db, tenant_id)` (was the handler's `_closed_periods`) and
   `present_for_shift_times(day, resolved_shift) -> (in_at, out_at)` (a thin wrapper over `_shift_instants` + `resolve_timezone`: IN = shift start, OUT = shift end).
   `attendance_import` behaviour and its tests are unchanged.
3. Let `_apply_approved_regularization` / the punch writer accept an optional `raw_extra: dict` merged into the punch's `raw` (e.g. `{"synthesized": True}`),
   default `None` → identical output to today.

Does NOT cover: the new endpoints (270) or the UI (271). Do not add the payroll-closed / joining / relieving checks to the single-day path here — note whether
`_validate_regularization` lacks them (it appeared not to check payroll periods) and, if so, raise that as a follow-up rather than changing single-day behaviour silently.

## Files
`backend/app/modules/attendance/service.py`, `backend/app/services/attendance_day_helpers.py` (new), `backend/app/modules/attendance_import/handler.py`,
tests untouched except import paths.

## Acceptance criteria
- [x] `regularize_on_behalf` response, status codes, audit rows (`RegularizationByHR` / `LockedDayOverride`), activity log and notification are identical to before
- [x] `_regularize_one` never commits (unit test patches `db.commit` to raise, calls `_regularize_one`, and checks `raw_extra` on the punches; a second test covers `notify`)
- [x] `attendance_import` imports the shared helpers; no duplicated copy of `_shift_instants` / `_closed_periods` remains
- [x] `uv run pytest app/tests/modules/test_attendance.py app/tests/modules/test_attendance_import.py app/tests/modules/test_attendance_recompute.py`: 430 passed, 1 failed — `test_employee_daily_pagination_matches_my_daily_shape` (extra `remarks` key), which fails identically on a clean `origin/main` and is unrelated. Only additions to the test file (2 new tests)
- [x] If the single-day path lacks payroll-closed / joining / relieving checks, a follow-up task is noted in 270's "Findings" section

Follow-up filed: 273 (single-day path lacks payroll-closed / joining / relieving checks; also recorded in 270's Findings).

Completed: 2026-10-27
