---
task: 203
title: Backend — HR regularizes an employee's attendance on their behalf (auto-approved)
status: done
depends_on: []
---

# 203 — HR regularization on behalf (API)

Build this in the **top-level `hrms/`** clone (same as 201/202). Paths are relative to `hrms/`.

## Why
Today regularization is **self-service only.** `submit_regularization`
(`backend/app/modules/attendance/service.py`, `POST /attendance/requests`) resolves the employee
with `_require_caller_employee`. HR can only approve what an employee submitted
(`approve_request`). HR wants to fix an **Absent**, **Missing clock-out** or **Late** day
directly from the HR Manager attendance screen, without waiting for the employee to apply.

## Scope
### `POST /api/v1/attendance/employees/{employee_id}/regularize`
- Put it on the existing encrypted attendance `router` (`route_class=EncryptedRoute`).
- **Gate:** `_APPROVE` (`RequirePermission("APPROVE", "ATTENDANCE")`), plus whole-org
  scope via `sees_whole_org(db, principal, "ATTENDANCE")`. HR only: a reporting manager gets
  403 and keeps using the approval inbox.
  **Open decision:** should reporting managers also regularize for their direct reports? If
  so, swap the whole-org check for `_require_manager_or_admin_for_employee`.
- Tenancy: `_require_employee_in_tenant`, so a cross-CDP id returns 404.
- **Body:** reuse `RegularizationRequestIn`
  (`attendance_date, punch: Clock-in|Clock-out|Both, requested_in_at?, requested_out_at?,
  reason_code, note?`). `note` is **required** here (audit trail for an HR override).
- **Service** `regularize_on_behalf(db, principal, employee_id, payload)`:
  1. Refactor so the self path and this path share one validator. Do not copy it. Pull the
     punch/time checks, the future-date check, the resolved-shift check, the duplicate check,
     the `is_locked` (423) check and the out-after-in check out of `submit_regularization`
     into a helper.
  2. **Skip** for HR: the `regularization_window_days` window and the
     `max_regularization_requests_per_month` cap. Those are employee self-service limits.
  3. Insert an `AttendanceRequestDetail` (`request_type="Regularization"`) already
     `status="Approved"`, with `approver_user_id = principal.user.id`, `actioned_at = now`
     and `created_by` = HR. Then run the **same** approve path `approve_request` uses:
     write the `Manual` punches, flush, `recompute_attendance_day`, and the audit
     old/new value. Factor that body into a helper both callers share, so a regularized
     day recomputes the same way whoever started it.
  4. If a **Pending** employee request already exists for that date, refuse with 409
     ("Approve the employee's pending request instead") rather than creating a second one.
  5. Log INFO on success and WARNING at each guard, following the module's existing pattern.
- **Activity log:** this changes another person's record, so call
  `activity_log_service.log_activity` (per the `hrms-activity-logging` skill).
- **Response:** `ApproveResultOut` (same shape as approve), so the UI can refresh the row.

**Not in scope:** the UI (204), recording leave (already built by task 197:
`POST /leave/employees/{id}/requests/record`), and the headcount fix (202).

## Files
- `backend/app/modules/attendance/router.py`: new route
- `backend/app/modules/attendance/service.py`: shared validator, shared approve-apply
  helper, `regularize_on_behalf`
- `backend/app/tests/modules/test_attendance*.py`: new tests
- `backend/app/tests/modules/test_authz.py`: gate coverage
- `docs/`: add a short "HR regularization on behalf" section to the existing attendance doc

## Acceptance criteria
- [ ] HR regularizes an Absent day (Both): the row recomputes to Present with Manual
      punches, and the request is stored Approved with HR as approver.
- [ ] HR fixes a missing clock-out (Clock-out only): `last_out_at`/`worked_minutes` are set.
- [ ] HR corrects a Late arrival (Clock-in earlier): `late_by_minutes` recomputes to 0.
- [ ] The window and monthly cap are ignored for HR but still enforced on the self path
      (regression test).
- [ ] Locked day → 423. Future date → 422. No shift → 400. Existing pending request → 409.
      Missing note → 422.
- [ ] Reporting manager / Employee role → 403. Cross-CDP employee → 404. No token → 401.
- [ ] Encrypted round-trip test for the new route.
- [ ] `uv run pytest` green.

Completed: 2026-10-08
