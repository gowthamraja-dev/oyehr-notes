---
task: 306
title: Approve / reject ShiftChange requests + keep them out of the regularization views
status: done
depends_on: [304, 305]
---

# 306 — Approve / reject ShiftChange

## Scope
Make the existing `POST /attendance/requests/{id}/approve|reject` (and the manager inbox / workflow-engine path) handle `request_type = 'ShiftChange'`.
No new endpoints, no new gate (APPROVE ATTENDANCE and the manager-or-admin check stay as they are).

### Approve
- New `apply_shift_to_day(db, principal, employee, day, shift_master_id, *, action_path)` in `modules/shifts/service.py`, next to
  `apply_work_location_to_days` and built the same way: `_plan_and_apply_employee_days` with a `target_for` that keeps the day's location and holiday
  calendar and swaps only the shift. **Does not commit.** No second writer, no direct `EmployeeShiftDetail` writes.
- New `_approve_shift_change_request` branch in `approve_request`, beside `_approve_wfh_request` (and reached from the workflow-engine last stage too).
  One transaction: shift write + status flip (`Approved`, `status_master_id`, `actioned_at`, `approver_remarks`) + audit `ShiftChangeApproved`
  (old/new shift ids) + `in_app.approved` + commit. The `current_shift_master_id` snapshot is never rewritten.
- Re-validate at approval time (the day may have changed since submit); refuse with 422 and a clear reason, leaving the request Pending, when the day is:
  locked (attendance or payroll), a Public holiday, a week-off (of the current or the requested shift), approved leave, outside employment, or the requested
  shift is no longer live (archived / window ended) / the employee has no shift on the day. A single day, so any skip from the planner means refuse.
- Recalculate attendance for the day if it is today or earlier (same `recalculate` behaviour the planner offers) so a same-day change settles correctly.

### Reject / views
- `reject_request` works for ShiftChange (reason required, as today); audit `ShiftChangeRejected`; employee notified.
- `_request_out`, `_audit_action` (`ShiftChange…`) and `RequestOut` know the type (carry requested shift name) — a shift change must not render as a
  Regularization in the HR/manager inbox, and `GET /attendance/me/requests` keeps working. Check `list_requests_for_manager` /
  `get_request_detail_for_manager` and any `request_type != 'WFH'` assumption (grep `"WFH"` in `modules/attendance`).
- A Cancelled/Rejected/Approved request can't be approved again (existing 409).

## Files
`backend/app/modules/shifts/service.py`, `backend/app/modules/attendance/{service.py,schemas.py,in_app.py}`, `backend/app/tests/modules/test_my_shifts.py`.

## Acceptance criteria
- [x] Approving moves the employee's shift for that one day only (neighbouring days untouched; location and holiday calendar kept) and the calendar API shows it
- [x] Each refusal case above leaves the request Pending and writes nothing
- [ ] Reject and approve are tenant-scoped; a manager can only action their own reports' requests (existing rule)
- [ ] Multi-stage workflow: only the last stage applies the shift
- [x] ShiftChange shows as such in the inbox, not as a Regularization; existing Regularization/WFH tests still pass
- [ ] Employee gets an in-app notification on approve and reject

## Progress (2026-10-29)
Built in `workspace-2/hrms` on `feature/gowtham_shift_grid_bulk`, NOT committed. Tests: `backend/app/tests/modules/test_my_shifts.py` (47 pass against the local `hrms-test-pg`). API only — not exercised from the mobile app or a browser.
Unchecked above and why: the multi-stage workflow path (last stage applies the shift) is untested; tenant scoping of approve/reject is tested, but the existing 'a manager acts only on their own reports' rule was not re-tested for ShiftChange; in-app delivery to the employee is not asserted (the notifier never tells the actor and the fixture has one login), only the notification wording. Verified: approving moves only that day (neighbours, location and calendar untouched); locked / holiday / week-off / leave / archived shift / already-on-shift all refuse with the request left Pending; reject stores remarks; a cancelled request can't be approved; the inbox lists ShiftChange as such. Existing attendance, WFH and shifts suites still pass apart from 6 pre-existing failures (they fail identically on the untouched code).

Completed: 2026-10-29
