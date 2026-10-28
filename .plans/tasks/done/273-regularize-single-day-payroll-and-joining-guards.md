---
task: 273
title: Single-day regularization — refuse closed payroll periods and out-of-employment dates
status: done
depends_on: [269]
---

# 273 — Single-day regularization — refuse closed payroll periods and out-of-employment dates

## Scope
Found while doing task 269: `attendance/service.py:_validate_regularization` — shared by the employee's own request (`submit_regularization`) and HR on-behalf
(`regularize_on_behalf`) — never checks that the date is (a) inside a payroll period that is already processed / approved / locked, (b) before the employee's
`joining_date`, or (c) after their `relieving_date`. The attendance bulk import refuses all three, and the range flow (270) will too; the single-day path should agree,
otherwise HR can change a day that payroll has already consumed by regularizing it one at a time.

- Use `closed_payroll_periods(db, tenant_id)` from `backend/app/services/attendance_day_helpers.py` (created in 269) and the employee's `joining_date` / `relieving_date`.
- Return 422 (or the status the codebase uses for "locked by payroll", check `_locked_day_error` and the import's message) with the same wording as the import: "falls in payroll period
  <name>, which is already processed — reopen payroll first"; joining/relieving messages in dd-MMM-yy.
- Decide, and document in the task before coding, whether HR with `override_reason` may pass a closed payroll period. The import says no ("reopen payroll first"); default to the same.
- Applies to the employee's own request too (an employee must not be able to queue a regularization for a closed period). Check what Pending requests already exist for closed periods
  so approving them is also refused with a clear message rather than silently changing a settled payroll.

Does NOT cover the range endpoints (270 builds these guards in from the start).

## Decisions (2026-10-27, before coding)
- **No override for a closed payroll period.** HR's `override_reason` unlocks a *locked day* only; a day inside a processed/approved/locked payroll period is refused for HR too
  ("reopen payroll first"), matching the import and the range flow. Joining/relieving bounds likewise have no override.
- **Status 422** with the import's wording (`falls in payroll period 'X', which is already processed — reopen payroll first`; joining/relieving in dd-MMM-yy). Not 423: that code means
  "locked day, override available" and the range flow maps it to `LOCKED`.
- **One helper**, `_assert_day_open_for_regularization(db, tenant_id, employee, day)`, called from `_validate_regularization` (employee request + HR on-behalf + each range day) and from
  `approve_request` for a still-Pending Regularization (before the multi-stage branch, so a stage approval is refused too). A non-Pending request keeps its 409.

## Files
`backend/app/modules/attendance/service.py`, `backend/app/tests/modules/test_attendance.py`.

## Acceptance criteria
- [x] Employee request and HR on-behalf regularization for a date inside a processed/approved/locked payroll period are refused with the import's wording
- [x] Dates before `joining_date` / after `relieving_date` are refused for both flows
- [x] Approving an already-Pending request whose date is now in a closed period is refused clearly
- [x] Existing regularization tests still pass; new tests cover each refusal and the unaffected happy path

## Progress (2026-10-27) — implemented and tested (workspace-2, uncommitted)
Code: `_assert_day_open_for_regularization` in `attendance/service.py`, called from `_validate_regularization` (employee request, HR on-behalf, each range day) and from `approve_request`
for a Pending Regularization (before the workflow branch). Tests: 12 new cases appended to `test_attendance.py` (each payroll flag, override does not pass, other tenant's period ignored,
joining/relieving refused + boundary dates allowed, employee request, approving a Pending request in a now-closed period stays Pending, decided request keeps 409).
Ran against a throwaway local `postgres:18` (schema from `Base.metadata.create_all`, audit-column NOT NULLs relaxed, attendance status masters seeded; container removed afterwards):
the regularization/approval/range subset 98 passed; `test_attendance.py` + `test_attendance_regularize_range.py` + `test_attendance_import.py` 380 passed, 3 failed — two holiday-calendar
seeding tests (reference data absent from that DB) and `test_employee_daily_pagination_matches_my_daily_shape` (an extra `remarks` key in the daily row; untouched by this task).
