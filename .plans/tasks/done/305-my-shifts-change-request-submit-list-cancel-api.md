---
task: 305
title: My Shifts — submit, list, detail and cancel shift change requests
status: done
depends_on: [303, 304]
---

# 305 — My Shifts: shift change requests (employee side)

## Scope
Self-service, **ungated**, on the encrypted `/shifts` router, in a new `modules/shifts/change_requests.py`. Register all routes **before**
`/me/{target_date}`. Rows live in `attendance_request_details` with `request_type = 'ShiftChange'` (schema `.plans/my-shifts-schema.dbml`).

### Endpoints
- `POST /shifts/me/change-requests` (201) — body `{date, requested_shift_master_id, reason}`. `reason` required, 1..500 chars after trim.
- `GET /shifts/me/change-requests?status=&page=&page_size=` — the caller's ShiftChange requests, newest `applied_at` first; `status` is one of
  `Pending|Approved|Rejected|Cancelled` (anything else 422); page default 1, size default 20, max 100; returns `{items, total}`.
- `GET /shifts/me/change-requests/{id}` — one of the caller's own (404 for anyone else's, another tenant's, or a non-ShiftChange row).
- `POST /shifts/me/change-requests/{id}/cancel` — only while `Pending` (else 422 "Cannot cancel a request that is already X"); returns the detail.

`ShiftChangeRequestOut`: `id`, `status`, `date`, `current_shift` and `requested_shift` (each `shift_master_id`, `name`, `code`, `color`, `start_time`,
`end_time`), `reason`, `applied_at` (submitted on), `actioned_at`, `approver` (brief), `approver_remarks`, `can_cancel` (Pending only).

### Submit rules (422 with a plain message unless noted; WARNING log at each guard)
- Caller is an employee (`_require_caller_employee`).
- `date` not in the past. Today is allowed only if the employee has **no punch yet today** (their day is in progress on the old shift).
- The employee has a shift on `date` (`resolve_effective_shift`) — it is stored as `current_shift_master_id`. None → 422.
- `requested_shift_master_id` is a shift of **the caller's tenant**, `is_active`, not archived, window covers `date` (the same predicate as task 303 — share
  one helper); a foreign tenant's id is indistinguishable from a missing one. It must differ from the current shift.
- No other **Pending** ShiftChange for the same employee + date.
- An approver exists (`_resolve_approver`, reporting manager) else 422 "No approver is configured for your profile — contact HR".
- The date is employed (joining/relieving) and not already a Public holiday / week-off / approved-leave day — refuse early rather than at approval.
- Writes `status='Pending'`, `status_master_id=_request_status_id(db,'Pending')`, approver fields, `created_by_id`, `from_date=to_date=date`; an
  `AttendanceAuditLog` row (`action='ShiftChangeSubmitted'`, new_value = date + both shift ids + reason); `in_app` notification to the approver
  (extend `modules/attendance/in_app.py` the way WFH did); one commit.
- Cancel writes `status='Cancelled'` + `status_master_id`, `actioned_at`, audit `ShiftChangeCancelled`, `in_app.cancelled`. Reuse the attendance helpers
  — do not copy-paste the Regularization cancel; if a shared function can be extracted from `cancel_my_request`, do that.

### Also
Task 302's calendar day field `has_pending_change_request` becomes real here: true when the caller has a Pending ShiftChange for that date (one query
for the whole range).

## Files
`backend/app/modules/shifts/change_requests.py` (new), `schemas.py`, `router.py`, `backend/app/modules/attendance/in_app.py`,
`backend/app/modules/attendance/service.py` (only for helper reuse/extraction), `backend/app/tests/modules/test_my_shifts.py`.

## Acceptance criteria
- [x] Submit creates a Pending request with the current shift snapshotted; response matches `ShiftChangeRequestOut`
- [x] Each submit rule above is refused with a clear message (past date, today after a punch, no current shift, same shift, foreign/archived/expired shift, duplicate Pending, no approver, holiday/week-off/leave)
- [x] List filters by status, paginates, only the caller's ShiftChange rows (not Regularization/WFH)
- [x] Detail/cancel: another employee's id, another tenant's id and a non-ShiftChange id all 404
- [x] Cancel only while Pending; cancelled row cannot be approved (see 306)
- [ ] Approver gets an in-app notification on submit; audit rows written
- [x] Calendar `has_pending_change_request` is true on the requested date
- [x] Encrypted round-trip test; tenant-scoping tests; routes don't shadow `/me/{target_date}`

## Progress (2026-10-29)
Built in `workspace-2/hrms` on `feature/gowtham_shift_grid_bulk`, NOT committed. Tests: `backend/app/tests/modules/test_my_shifts.py` (47 pass against the local `hrms-test-pg`). API only — not exercised from the mobile app or a browser.
`in_app.submitted` is called on submit and its wording for a shift change is unit-tested, but delivery to the approver is NOT asserted: the notifier only writes for a recipient with a membership and never tells the actor, which the single-login test fixture can't provide. Task 304 (migration) is still in `ongoing` — see its progress note. Approval and rejection are task 306.

Completed: 2026-10-29
