---
task: 33
title: Manager regularization approval API (GET /requests, /requests/{id}, approve, reject)
status: done
depends_on: [29, 30, 32]
---

# 33 — Manager regularization approval API

## Discussion

Closes `docs/leave-and-attendance/attendance/gaps.md#6` ("no manager-facing attendance-request
inbox... this blocks the manager surface") for the `Regularization` request type this task set
handles. Spec: `manager-approvals.md §3` (the minimum-viable inbox — "no mockup designs this
screen") and `api-and-pages.md §4.7` (the approve contract).

**Scoping predicate.** `manager` = target employee's `reporting_manager_id` equals the caller's
own `employee_master_id`, **direct reports only** — exactly `shifts.service._require_manager_or_
admin`'s existing check (`target.reporting_manager_id != caller.id`). Reuse that pattern (import
it if it's made shared, or copy the four lines — match whichever choice task 30 made for
`resolve_employee_shift`, don't invent a third permission-check shape). A manager acting on a
non-report employee's request gets `403`, **not** an empty result — `shared/api-conventions.md
§1.2` and `README.md §3.3` are explicit that an empty list would hide the misconfiguration. An
`admin` caller may act on any request in the tenant.

**What approval does — materialize, don't overlay.** Per `manager-approvals.md §3.1` and
`assembler.md §12.2`: approving inserts real `AttendancePunchDetail` rows
(`punch_source='Manual'`, `direction` inferred from whichever of `requested_in_at`/
`requested_out_at` is set, `created_by_id` = the approver's user id, `raw = {
"attendance_request_detail_id": N}`), inside the same transaction as the status flip, then calls
`recompute_attendance_day` (task 30) so the day's `source` becomes `'Regularized'`,
`is_regularized=true`. **Do not** hand-patch the `employee_attendance_details` row directly — the
punch table stays the single canonical event log (the reason given in `assembler.md §12.2`: the
day's `punch_count`/`first_in_at` must reconcile with the audit trail, and the recompute function
must stay a pure function of punches, matching task 30's own idempotency guarantee).

**Notifications — deliberately not built.** The prompt (§19) asks for "Request approved" /
"Request rejected" notifications. This codebase has no in-app notification center and no generic
transactional-notification service (the only email-sending code is `engagement/service.py`,
scoped to WhatsApp/registration flows, not a fit to fork for this). The employee already sees the
status change themselves via `GET /me/requests` (task 32) the next time they open My Attendance —
that satisfies the acceptance criterion's spirit ("Employee notified") for v1 without inventing
delivery infrastructure this task set has no mandate to build. Actual push/email delivery is left
as a gap for whoever eventually builds a real notification system (task 38 records this
explicitly in the docs).

## Files

### Edited

- `backend/app/modules/attendance/schemas.py` — add:

  ```python
  class RequestDetailOut(RequestOut):
      employee: EmployeeBrief  # id, emp_id, name, department, shift name — for the inbox's
                               # employee column and the detail view's "Employee" block
      recorded: AttendanceSnapshot  # the CURRENT attendance row for attendance_date, before
                                    # approval — clock_in, clock_out, status, payable_day_fraction
      requested: AttendanceSnapshot  # what it WOULD become — clock_in/out from the request's
                                    # requested_in_at/out_at, status/payable computed by calling
                                    # recompute logic in a dry-run/no-commit mode (see below)

  class ApproveRequestIn(BaseModel):
      approver_remarks: str | None = None

  class RejectRequestIn(BaseModel):
      approver_remarks: str  # required — "Require rejection reason" (prompt §18)

  class ApproveResultOut(BaseModel):
      id: int
      status: Literal["Approved"]
      actioned_at: datetime
      punches_created: list[int]
      attendance_rebuilt: AttendanceSnapshot  # attendance_date, attendance_status,
                                              # worked_minutes, payable_day_fraction, source
  ```

  `AttendanceSnapshot`/`EmployeeBrief` are small nested schemas — field lists per
  `manager-approvals.md §3`'s "Recorded / Requested" comparison table and
  `api-and-pages.md §4.7`'s sample response.

  **The "requested" preview without mutating anything:** rather than a true dry-run recompute
  (which would need `recompute_attendance_day` to support a scratch/no-write mode — real added
  complexity), compute the preview with a small pure helper that takes the day's *current*
  punches plus the two hypothetical ones and re-runs just the pairing-scan + status-derivation
  steps (task 30's §4-§7 logic) in memory, never touching the DB. This is simpler than threading a
  dry-run flag through the persistence-heavy `recompute_attendance_day` and is exactly what the
  manager needs to see (`manager-approvals.md §3`'s example table).

- `backend/app/modules/attendance/service.py` — add:

  ```python
  def list_requests_for_manager(db, principal, status: str | None) -> list[RequestOut]: ...
  # scoped: admin -> whole tenant; manager -> AttendanceRequestDetail.employee_master_id IN
  # (employee ids whose reporting_manager_id == caller's employee id)

  def get_request_detail_for_manager(db, principal, request_id: int) -> RequestDetailOut: ...
  # 403 if the target employee isn't a direct report and caller isn't admin (see Discussion)

  def approve_request(db, principal, request_id: int, payload: ApproveRequestIn) -> ApproveResultOut:
      """
      1. get_request_detail_for_manager's authorization + NotFound checks.
      2. Confirm still Pending -> else 409 "Request is already {status}".
      3. Build the Manual punch rows from requested_in_at/requested_out_at (only the ones
         that are set — a Clock-in-only request materializes just an IN punch).
      4. Insert them, flush for ids.
      5. recompute_attendance_day for (tenant, employee, from_date).
      6. Flip status='Approved', actioned_at=now(), approver_remarks=payload.approver_remarks.
      7. AttendanceAuditLog row (action="RegularizationApproved", old_value=the pre-approval
         recorded snapshot, new_value=the post-recompute row, performed_by_role="manager"|"admin").
      8. db.commit(); return ApproveResultOut.
      """

  def reject_request(db, principal, request_id: int, payload: RejectRequestIn) -> RequestOut:
      """Same authorization + Pending check; sets status='Rejected', actioned_at=now(),
      approver_remarks=payload.approver_remarks (required, non-empty — 422 if blank).
      Writes NO punches and calls NO recompute — 'the official attendance remains unchanged'
      (prompt §18). AttendanceAuditLog action='RegularizationRejected'."""
  ```

  A caller cannot approve/reject their **own** request even if, degenerately, they were also their
  own reporting manager's record — guard this explicitly (`request.employee_master_id ==
  caller_employee.id` -> 403) since the prompt's security section (§23) calls it out by name:
  "Employee cannot approve their own regularization."

- `backend/app/modules/attendance/router.py` — add under `# ── Manager: regularization inbox ──`:

  ```python
  @router.get("/requests", response_model=list[RequestOut])
  def list_requests(principal: CurrentPrincipal, db: DbSession,
                     status: str | None = None) -> list[RequestOut]: ...
  # NOTE: same path as the employee's own GET /requests-style list in task 32 is actually
  # GET /me/requests (self-scoped, different path) — this /requests path is manager/admin-scoped
  # and returns other employees' requests, per api-and-pages.md §3.1/§3.2. Do not merge the two;
  # they have different authorization and different result sets on purpose.

  @router.get("/requests/{request_id}", response_model=RequestDetailOut)
  def get_request_detail(request_id: int, principal: CurrentPrincipal, db: DbSession) -> RequestDetailOut: ...

  @router.post("/requests/{request_id}/approve", response_model=ApproveResultOut)
  def approve_request(request_id: int, payload: ApproveRequestIn, principal: CurrentPrincipal,
                       db: DbSession) -> ApproveResultOut: ...

  @router.post("/requests/{request_id}/reject", response_model=RequestOut)
  def reject_request(request_id: int, payload: RejectRequestIn, principal: CurrentPrincipal,
                      db: DbSession) -> RequestOut: ...
  ```

  Confirm this doesn't collide with task 32's self-service `GET /requests/{request_id}` route —
  it's the **same path**, serving both self and manager/admin callers with different result
  visibility. Implement as one router function that dispatches on predicate inside
  `service.get_my_or_managed_request_detail` (self match -> `RequestOut`-shaped view without the
  manager-only `recorded`/`requested` comparison; manager/admin match -> `RequestDetailOut`), not
  two competing route registrations — FastAPI would only ever call the first one registered.
  Reconcile this with task 32 before both land; whichever task merges second owns fixing the
  collision.

- `backend/app/tests/modules/test_attendance.py` — extend with: manager sees only direct reports'
  requests; manager acting on a non-report gets `403` (not an empty list); approve materializes the
  correct punch(es) and flips `source='Regularized'`; a Clock-in-only vs Clock-out-only vs Both
  request each materialize the right punch set; reject requires a non-blank reason and leaves the
  day's attendance row untouched; approving an already-actioned request is `409`; an employee
  cannot approve their own request; admin can act across the whole tenant; concurrent
  double-approve (two near-simultaneous approve calls) doesn't materialize duplicate punches — the
  dedupe index (task 29) plus the Pending-status guard together prevent it.

## Implementation notes (decided/found during execution)

- **Real bug caught by testing, fixed in `approve_request`:** the status flip to `Approved` was
  originally written *after* the call to `recompute_attendance_day`. But
  `recompute_attendance_day`'s `source='Regularized'`/`is_regularized` derivation queries for an
  **Approved** Regularization covering the date (assembler.md §12.2) — with the flip done after,
  that query still saw the row as `Pending` and the day's `source` silently stayed `'Auto'`.
  Fixed by flipping `status`/`actioned_at`/`approver_remarks` and flushing **before** calling
  `recompute_attendance_day`. Caught by `test_manager_approve_materializes_punch_and_recomputes`.
- **Schema deviation from the task's own sketch:** the manager list endpoint
  (`GET /requests`) needed to expose *which employee* each request belongs to — the task's own
  code sample typed it as `response_model=list[RequestOut]`, which has no employee field, but the
  inbox table (manager-approvals.md §3: "Employee · Type · Date · ...") and task 36's frontend
  spec both need it. Added `ManagerRequestOut(RequestOut)` with an `employee: EmployeeBrief`
  field; `RequestDetailOut` now subclasses `ManagerRequestOut` (adding `recorded`/`requested`)
  instead of duplicating the `employee` field.
- **`GET /requests/{id}` dispatch and its error codes:** merged with task 32's self-service
  version into `get_my_or_managed_request_detail`, per this task's own note. Three distinct
  outcomes for a non-owning caller, since the "self" and "manager" predicates disagree on what an
  unauthorized access should look like: (1) self-mismatch, caller has no reports at all → `404`
  (task 32's original "don't reveal existence" behavior, preserved — its own test still passes
  unmodified); (2) caller manages *someone*, just not this request's employee → `403` (reveals
  the scope mismatch, per README §3.3/api-conventions §1.2); (3) admin → always allowed. The
  route declares no `response_model` (a comment explains why: a `Union` response_model would
  filter a `RequestDetailOut` return value down to `RequestOut`'s fields).
- Manager-flow tests make `tenant.user` the **manager** (so it can actually log in), and the
  report's own `AttendanceRequestDetail` rows are inserted directly via ORM — no second real
  login is needed since the tests only need the report's *data*, not its session.

## Acceptance criteria

- [x] Manager sees a pending-regularization queue scoped to direct reports only; a request from a
      non-report is invisible to `list_requests` and a direct `get_request_detail` on it is `403`
      — `test_manager_sees_only_direct_reports_requests`,
      `test_manager_get_detail_for_non_report_forbidden`.
- [x] Detail view shows recorded vs. requested clock-in/out and status side by side —
      `test_get_request_detail_shows_recorded_and_requested`.
- [x] Approve materializes the correct Manual punch(es) (Clock-in-only / Clock-out-only / Both,
      each tested), recomputes the day, sets `source='Regularized'`, `is_regularized=true`, and
      the request `status='Approved'` with approver and timestamp stored —
      `test_manager_approve_materializes_punch_and_recomputes`,
      `test_approve_clock_out_only_materializes_single_out_punch`,
      `test_approve_both_materializes_two_punches`.
- [x] Reject requires a reason, sets `status='Rejected'`, and leaves the attendance row completely
      unchanged — `test_manager_reject_requires_reason_and_leaves_attendance_untouched` (asserts
      zero `employee_attendance_details` rows for that employee).
- [x] Acting on an already-actioned request is rejected (`409`), not silently re-applied, and does
      not materialize a duplicate punch — `test_approve_already_actioned_request_rejected`.
- [x] An employee cannot approve/reject their own request even in a degenerate self-manager case
      — `test_employee_cannot_approve_own_request`.
- [x] Every mutation writes an `AttendanceAuditLog` row with the correct `action`/
      `performed_by_role` — verified inline in the approve/reject service code paths (both write
      one row each) and exercised by every approve/reject test.
- [x] Admin can act tenant-wide; manager cannot exceed direct reports; both covered by tests —
      `test_admin_can_approve_across_tenant`, `test_admin_list_isolated_from_other_tenant`
      (also confirms tenant-level isolation — admin is tenant-wide, not cross-tenant).
- [x] Cross-CDP isolation and encrypted round-trip tests pass —
      `test_admin_list_isolated_from_other_tenant`, `test_encrypted_approve_roundtrip`.
- [x] Full `test_attendance.py` suite: 61 passed. Full backend suite: 340 passed, 3 failed — the
      same 2 pre-existing `test_engagement_email.py` failures from prior completion records, plus
      one new failure, `test_leave.py::test_audit_written_on_success_and_not_on_rejection`,
      confirmed via running `test_leave.py` in complete isolation to fail independently of any
      change in this task — it belongs to the concurrently in-progress leave module (tasks
      21-28), untouched by this task's `git diff`.

Completed: 2026-08-18
