---
task: 247
title: WFH requests — raise, list, cancel, approve (switches to the remote site), reject (backend)
status: done
depends_on: [248]
---

# 247 — WFH requests — raise, list, cancel, approve (switches to the remote site), reject (backend)

Part of `.plans/shift-wfh-plan.md` (backend half; employee UI = 250, inbox UI = 251).

## Why
Task 246 added a read-only roster marker for **approved** WFH requests, but nobody can create one: the attendance
request API only writes `request_type = 'Regularization'` (`submit_regularization`, `RequestOut.request_type:
Literal["Regularization"]`), and `attendance/gaps.md` gap 6 records WFH as having "no surface at all". The table
(`attendance_request_details`) and the rules (`attendance/employee-self-service.md` §2.5) already cover WFH —
**no schema change in this task** (the only schema change is task 248's `is_remote`).

## Decisions (24-Oct-26, user)
- WFH has **no attendance or payroll effect**. Approval only **switches the work location to the tenant's remote
  site** for the days in the request. No `employee_attendance_details` row is written; the shift and holiday
  calendar are untouched.
- **No undo**: only a Pending request can be cancelled; Approved / Rejected cannot.
- The remote site is `work_location_masters.is_remote` (task 248). No live remote site → raise is refused with a
  clear message, and approve is refused (409/422) before anything changes.
- Remote site's punch policy follows the location (`get_punch_policy`) — it is `NoCheck` by task 248's rule.

## Scope
**In:** `POST /attendance/requests/wfh`; own list incl. WFH; cancel own Pending; manager/admin list, approve, reject.
**Out:** employee and inbox UI (250, 251); anything touching attendance status or payroll; OnDuty / ShortLeave.

## Rules (from `employee-self-service.md` §2.5, WFH column)
| Rule | WFH |
|---|---|
| Dates | `from_date..to_date` is a **range**, `to >= from`, ≤ **31 days**; times NULL |
| Reason | Required, non-blank, stored in `reason` |
| Past / future | Future-dated allowed; past only within `regularization_window_days` |
| Duplicate | No Pending or Approved WFH of the caller overlapping **any** date in the range |
| Leave clash | Refuse a range overlapping the caller's Pending/Approved leave (mirror of the existing leave gate that refuses leave over an approved WFH) |
| Locked | Refuse if any date in the range has a locked attendance row |
| Employment | Dates inside joining..relieving |
| Approver | Caller needs a resolvable reporting manager (`leave/employee-self-service.md` §5), else 422 |
| Remote site | The tenant must have a live remote site (`get_remote_work_location`, task 248), else 422 |
| Status | `Pending → Approved | Rejected | Cancelled`; dual-write `status` and `status_master_id` exactly as Regularization |

## Approval (one transaction)
1. Existing manager/admin scoping (`_require_manager_or_admin_for`) and the "already actioned → 409" check.
2. Resolve the remote site; none → refuse before any change.
3. Location-only write for the requester over `from_date..to_date` via `_plan_and_apply_employee_days`
   (the helper range assign and copy-week share): `target_for` keeps each day's shift and calendar and sets the
   remote location; `skip_week_offs=True`, `overwrite_manual=True` (the approver's explicit decision replaces an
   earlier manual location). Skips: outside employment, locked, no standing shift, week-off, unchanged.
4. Flip status to Approved (approver, `actioned_at`, remarks), `log_activity`, commit once.
5. Response: the request plus the range result (`assigned_count`, per-day skips) so the UI can show what
   did not change. Approving with *every* day skipped still approves — it just reports it.
Reject (reason required) changes only the request. Cancel (own, Pending only) changes only the request.

## Files
- `backend/app/modules/attendance/schemas.py` — `WfhRequestIn {from_date, to_date, reason}` (validators);
  `RequestOut` / `ManagerRequestOut`: `request_type` becomes `Literal["Regularization","WFH"]` and rows carry
  `from_date` / `to_date` (keep `attendance_date` / `punch` for Regularization, optional for WFH — decide one shape
  and keep both list endpoints returning it); `ApproveResultOut` gains the optional range result.
- `backend/app/modules/attendance/service.py` — `submit_wfh_request`; share approver-resolution + status
  dual-write with `submit_regularization`; `approve_request` / `reject_request` branch on `request_type`
  (today they assume Regularization); `list_my_requests` / `list_requests_for_manager` accept `?request_type=`;
  confirm `cancel_my_request` is type-agnostic and Pending-only; `get_request` detail handles WFH.
- `backend/app/modules/attendance/router.py` — `POST /attendance/requests/wfh` (self-service, ungated, like
  `submit_regularization`); `?request_type=` on the list routes. Router is already `EncryptedRoute`.
- Notification to the approver: follow whatever Regularization does today; don't invent a channel.
- Docs: `docs/leave-and-attendance/attendance/` — `employee-self-service.md` §2.5 (WFH built: range, leave clash,
  remote-site effect), `manager-approvals.md`, `api-and-pages.md` rows, `gaps.md` gap 6 (WFH resolved; OnDuty /
  ShortLeave still open), `vocabularies.md`; add the endpoint to the `hrms-mobile-api-integration` skill's `/me/*`
  catalogue.

## Tests (`app/tests/modules/test_attendance_requests*.py`, follow the Regularization ones)
Raise happy path (+ appears in `GET /me/requests`); range validation (`to < from`, > 31 days, blank reason);
duplicate / overlapping Pending and Approved; leave clash; locked day; outside employment; past beyond the
window; no approver → 422; **no remote site → 422**; cancel own Pending ok / Approved refused / someone else's
refused; manager approve + reject scoped to direct reports; admin whole tenant; **cross-tenant** request id → 404;
401 / 403 on gated routes; second action on an actioned request → 409.
Approval effects: every eligible day's `work_location_master_id` becomes the remote site while shift + calendar
are unchanged; bounded rows carved correctly around standing rows; skips (week-off, locked, outside
employment, no standing shift, unchanged) are reported; approve with no remote site changes nothing (status
stays Pending); **atomic** (a failing location write leaves the request Pending); reject / cancel change no
shift row; **no `employee_attendance_details` row is written by raise / approve / reject / cancel**; an approved
request shows `wfh_request` + the remote location on the roster (246 overlay); encrypted round-trip.

## Acceptance criteria
- [x] An employee can raise a WFH range through the API; it lists under their own requests
- [x] Cancel works only on the caller's own Pending request
- [x] Manager (direct reports) / admin (tenant) approve or reject; reject needs a reason; double action → 409
- [x] Approval switches each eligible day's location to the remote site, shift + calendar untouched, atomically
      with the status change; skipped days returned; no remote site → refused with nothing changed
- [x] Leave apply and WFH raise refuse each other's overlaps; locked / outside-employment / duplicate → clear 422
- [x] Every query scoped by `principal.tenant_id`; cross-tenant tests included
- [x] No attendance or payroll row written (asserted)
- [x] Docs + skill catalogue updated; backend tests pass

## Implementation notes (24-Oct-26)
- **Schemas** (`attendance/schemas.py`): `WfhRequestIn` (range order, ≤ `WFH_MAX_DAYS` = 31, reason stripped / required),
  `WfhApproveResultOut` (`work_location_master_id`, `work_location_name`, `assigned_days`, `skipped`); `RequestOut` now
  `request_type: Regularization | WFH`, gains `to_date`, and `punch` is nullable (None for WFH). The approve route's
  `response_model` is `ApproveResultOut | WfhApproveResultOut`.
- **Shifts** (`shifts/service.py`): new public `apply_work_location_to_days(db, principal, emp, from, to, location_id, *, action_path)`
  — the location-only range write over `_plan_and_apply_employee_days`, `skip_week_offs=True`, `overwrite_manual=True`,
  **does not commit** so the approval can make it atomic with the status flip.
- **Attendance service**: `submit_wfh_request` / `_validate_wfh_request` (employment dates, past window from the shift on the first
  day, remote site required, overlap with a Pending/Approved WFH, Pending/Approved leave with `day_fraction > 0`, locked
  day → 423, approver); `_approve_wfh_request` (remote site resolved first — none → 422 before any change; location write; status
  flip; audit; one commit); `approve_request` branches on `request_type`; `reject_request` / `cancel_my_request` are
  type-agnostic and use `_audit_action(req, verb)` → `WfhSubmitted | WfhCancelled | WfhApproved | WfhRejected`;
  `list_my_requests` / `list_requests_for_manager` take `request_type`; a WFH detail comes back as the plain manager shape.
- **Router**: `POST /attendance/requests/wfh` (ungated self-service, like `POST /requests`); `?request_type=` on both list routes
  (a bad value is a 422).
- **Audit**: followed what Regularization does — `attendance_audit_logs` rows, not `log_activity` (the plan's wording). The location
  write itself still logs through `log_activity` (inside `_plan_and_apply_employee_days`).
- **Tests**: `app/tests/modules/test_attendance_wfh.py`, 36 passing — raise (+ list, filter, detail, audit, no attendance/punch row),
  validation (range, 31-day cap, blank reason), no approver, no remote site (and an archived / other-tenant one), overlap rules,
  leave clash (Approved / Pending block, Rejected doesn't), locked day, employment dates, past window + no shift, encrypted
  round-trip, cancel (own Pending / Approved+Rejected refused / someone else's / cross-tenant), inbox scoping + filter, manager
  detail shape, approve (location moved, shift + calendar kept, one bounded row, status + audit, no attendance side effects),
  skip reporting (locked / unchanged / outside employment / week-off / no standing shift), manual location replaced, no remote
  site → nothing changes, failed write leaves it Pending, double action 409, manager scope 403, admin + roster shows
  `wfh_request` and the remote location, reject needs a reason, cross-tenant 404s.
  Regression: attendance + shifts + carve + leave + encryption + authz = 681 passed; 2 `test_leave` failures are date-dependent
  ("Backdated leave applications are not allowed" — hard-coded dates now in the past), unrelated.
- **Atomicity** is covered at app level (a failing location write leaves the request Pending, nothing committed). The shared test
  session can't show a real rollback, so that is a reading of the single `db.commit()` after both writes, not a separate test.
- **Docs**: `attendance/api-and-pages.md` (inbox, approve, raise, cancel, my-requests rows), `manager-approvals.md` (WFH approval
  replaces the old overlay idea), `gaps.md` gap 6, `employee-self-service.md` §2.5 mapping row; the
  `hrms-mobile-api-integration` skill's `/me/*` catalogue (list filter, raise, cancel).
- **Left for 250 / 251**: the employee form + list + cancel UI, the inbox rows + skipped-days summary. Not done here: any employee
  or manager UI, and the optional notification to the approver (Regularization has none either).
