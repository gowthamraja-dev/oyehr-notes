---
task: 32
title: Employee daily log + regularization request API (GET /me/daily, /me/requests, POST /requests, cancel, attachment)
status: done
depends_on: [29, 30, 31]
---

# 32 — Employee daily log + regularization request API

## Discussion

Two surfaces from `docs/leave-and-attendance/attendance/employee-self-service.md`: the daily log
(§2.3, backing the Employee Portal's history table) and requesting/viewing a regularization
(§2.4-2.5). Contracts are `api-and-pages.md §4.3` (daily log sample) and `§4.6` (request POST
sample) — copy those shapes exactly.

**Scope cut carried from task 29: `request_type` is always `'Regularization'` in this task set.**
The mockup's reason dropdown collapsing into `request_type` (`vocabularies.md §4.1`) still applies
conceptually, but since `OnDuty`/`WFH` are out of scope, the reason dropdown this task builds only
needs the values that map to `Regularization`: **Forgot to punch**, **Wrong punch time**,
**Biometric error**, **Device issue**, **System issue**, **Other** (the prompt's own list, §11) —
all stored as literal `reason` text with `request_type='Regularization'`. Do not add "On-duty /
field work" or "Work from home" options to this dropdown; they'd create a request this task set's
approval flow (task 33) doesn't know how to apply.

**The punch selector is not a column.** Per `employee-self-service.md §2.5`, `Clock-in` /
`Clock-out` / `Both` is never stored — it's implied by which of `requested_in_at`/
`requested_out_at` is non-NULL (table in that section). Reading the list back inverts the same
rule to render "Clock-in"/"Clock-out"/"Both" in the history table.

**Approver resolution.** `reporting_manager_id` on the caller's `EmployeeMaster`, resolved live
(not cached) at both submit-time (for the response's `approver` block) and again at approve-time
(task 33) in case it changed in between. If it doesn't resolve (no manager, or the manager row
itself has no linked user), reject the submission with `422` — do not silently create an
unapprovable request. `regularization_approver` per-shift knob is read but, per
`config-knobs.md §4`, v1 honours Reporting Manager only regardless of its value — do not add HR
routing.

## Files

### Edited

- `backend/app/modules/attendance/schemas.py` — add (grouped under a new banner):

  ```python
  REGULARIZATION_REASONS = {
      "Forgot to punch", "Wrong punch time", "Biometric error",
      "Device issue", "System issue", "Other",
  }

  class DailyLogRow(BaseModel):
      id: int
      attendance_date: date
      day_label: str  # weekday name, e.g. "Tuesday" — computed, not stored
      day_type: str
      attendance_status: str | None
      first_in_at: datetime | None
      last_out_at: datetime | None
      worked_minutes: int
      late_by_minutes: int
      early_exit_minutes: int
      is_late: bool  # day_type='Working' AND late_by_minutes > 0 — vocabularies.md §1.1
      is_regularized: bool
      payable_day_fraction: float
      overtime_minutes: int
      shift_name: str | None
      source: str
      is_locked: bool
      remarks: str | None

  class DailyLogOut(BaseModel):
      items: list[DailyLogRow]
      total: int
      limit: int
      offset: int

  class PunchSelector(str, Enum):
      clock_in = "Clock-in"
      clock_out = "Clock-out"
      both = "Both"

  class RegularizationRequestIn(BaseModel):
      attendance_date: date  # from_date == to_date always in this task set
      punch: PunchSelector
      requested_in_at: datetime | None = None
      requested_out_at: datetime | None = None
      reason_code: str  # one of REGULARIZATION_REASONS
      note: str | None = None

      @field_validator("reason_code")
      ...  # must be in REGULARIZATION_REASONS

  class ApproverBrief(BaseModel):
      employee_master_id: int
      name: str
      designation: str | None

  class RequestOut(BaseModel):
      id: int
      request_type: Literal["Regularization"]
      status: Literal["Pending", "Approved", "Rejected", "Cancelled"]
      attendance_date: date
      punch: PunchSelector  # derived on read, see Discussion
      requested_in_at: datetime | None
      requested_out_at: datetime | None
      reason: str
      applied_at: datetime
      approver: ApproverBrief | None
      actioned_at: datetime | None
      approver_remarks: str | None
      attachment_required: bool  # always False — no policy surface makes this true in v1
  ```

- `backend/app/modules/attendance/service.py` — add:

  ```python
  def get_my_daily(db, principal, from_dt: date | None, to_dt: date | None,
                    limit: int, offset: int) -> DailyLogOut: ...
  def list_my_requests(db, principal, status: str | None) -> list[RequestOut]: ...
  def get_my_request(db, principal, request_id: int) -> RequestOut: ...
  def submit_regularization(db, principal, payload: RegularizationRequestIn) -> RequestOut: ...
  def cancel_my_request(db, principal, request_id: int) -> RequestOut: ...
  ```

  **`get_my_daily`:** reads `employee_attendance_details` for the caller's employee id in
  `[from_dt, to_dt]` (default: current month, matching `employee-self-service.md §2.2`'s "over
  the current month"), paginated per `shared/api-conventions.md §1.1`'s envelope convention
  (`limit` default 50 capped 200, using the existing `Pagination` dependency in `app.api.deps` —
  this is one of its first real consumers). Does **not** call `recompute_attendance_day` — reads
  whatever the last clock action/approval already computed; a date nobody has touched simply has
  no row and is omitted from `items` (not synthesized as a placeholder row).

  **`submit_regularization`:**
  1. `_require_caller_employee`.
  2. Map `payload.punch` -> `(requested_in_at, requested_out_at)` per the table in this task's
     Discussion — `Clock-in` sets only `requested_in_at`, `Clock-out` only `requested_out_at`,
     `Both` sets both; enforce the corresponding one is actually non-NULL in the payload (422 if
     the client sent `punch=Clock-in` with no `requested_in_at`).
  3. Resolve the effective shift for `attendance_date` (`calendar_resolver_service`) to read its
     `regularization_window_days` (default 7) and `max_regularization_requests_per_month` (default
     3) — per-shift columns, `config-knobs.md §0`. If no shift resolved, use the same hardcoded
     defaults (7, 3) — there's no tenant-wide fallback surface.
  4. Validate, in order, each raising `422` with the prompt's own wording where it gives one
     (`.design/prompts/…§12`, `employee-self-service.md §2.5`'s table):
     - `attendance_date <= today` (not future).
     - `today - attendance_date <= regularization_window_days` — `"Outside the {N}-day
       regularization window"`.
     - Count of this caller's `Regularization` requests with `applied_at` in the current calendar
       month, `status IN ('Pending','Approved')` `< max_regularization_requests_per_month` —
       `"Monthly regularization limit of {N} reached"`.
     - No existing `Pending` or `Approved` Regularization request for the same
       `employee_master_id` + `attendance_date` — `"A regularization request already exists for
       this date"`.
     - The target date's `employee_attendance_details` row, if any, is not `is_locked`.
     - Same-day `requested_out_at > requested_in_at` when both are set and the shift is not a
       night shift (`shift.policy_config.is_night_shift`) — for a night shift, `requested_out_at`
       naturally falls the next calendar day and this check is skipped (matches the prompt's own
       §8/§12 overnight-shift carve-out).
  5. Resolve the approver: caller's `EmployeeMaster.reporting_manager_id` ->
     `EmployeeMaster` -> its `user_id`. No resolvable manager -> `422 "No approver is configured
     for your profile — contact HR"` (mirrors `employee-self-service.md §2.5`'s "the modal must
     say so and disable submit" — the API-level equivalent).
  6. Insert `AttendanceRequestDetail(request_type="Regularization", from_date=to_date=
     attendance_date, reason=f"{payload.reason_code}: {payload.note}" if payload.note else
     payload.reason_code, approver_user_id=..., approver_employee_master_id=...,
     created_by_id=principal.user.id)`.
  7. Write an `AttendanceAuditLog` row (`action="RegularizationSubmitted"`).
  8. `db.commit()`; return `RequestOut`.

  **`cancel_my_request`:** only the caller's own request, only while `status='Pending'` ->
  `status='Cancelled'`, `actioned_at=now()`; else `422`/`409`. Audit row
  `action="RegularizationCancelled"`.

- `backend/app/modules/attendance/router.py` — add under `# ── Employee self-service: daily log &
  regularization ──`:

  ```python
  @router.get("/me/daily", response_model=DailyLogOut)
  def get_my_daily(principal: CurrentPrincipal, db: DbSession,
                    from_: date | None = Query(None, alias="from"), to: date | None = None,
                    limit: int = 50, offset: int = 0) -> DailyLogOut: ...

  @router.get("/me/requests", response_model=list[RequestOut])
  def list_my_requests(principal: CurrentPrincipal, db: DbSession,
                        status: str | None = None) -> list[RequestOut]: ...

  @router.get("/requests/{request_id}", response_model=RequestOut)
  def get_request(request_id: int, principal: CurrentPrincipal, db: DbSession) -> RequestOut: ...
  # self predicate enforced inside service.get_my_request — 404, not 403, if it isn't the
  # caller's own request (avoids revealing another employee's request even exists)

  @router.post("/requests", response_model=RequestOut, status_code=201)
  def submit_regularization(payload: RegularizationRequestIn, principal: CurrentPrincipal,
                             db: DbSession) -> RequestOut: ...

  @router.post("/requests/{request_id}/cancel", response_model=RequestOut)
  def cancel_request(request_id: int, principal: CurrentPrincipal, db: DbSession) -> RequestOut: ...
  ```

  Attachment upload (`POST /requests/{id}/attachment`) goes on the **plain** `_upload_router`
  (multipart, `EncryptedRoute` can't do it — same as the holiday CSV import above it in this
  file), using `image_service.upload_image(imageable_type="AttendanceRequestDetail",
  imageable_id=request_id, img_type="attachment")`. Add `"AttendanceRequestDetail":
  "attendance_request"` to `_FOLDER` in `backend/app/services/image_service.py` per CLAUDE.md's
  file-upload convention. Validate the request belongs to the caller and is still `Pending` before
  accepting an upload.

- `backend/app/tests/modules/test_attendance.py` — extend with: submit within/outside the window,
  monthly-cap rejection, duplicate-date rejection, cancel own pending request, cannot cancel
  another employee's request (404), `GET /me/daily` pagination and date-range filtering, "Both"
  punch selector round-trips correctly on read.

## Implementation notes (decided during execution)

- `GET /requests/{request_id}` (this task) is currently **self-only** — 404 if the request isn't
  the caller's own. Task 33's own file already anticipated this collision ("the same path...
  reconcile this before both land") — task 33 must turn `service.get_my_request` into a dispatch
  that also serves manager/admin callers with a richer `RequestDetailOut`, not add a second
  competing route registration.
- Attachment-upload tests mock `boto3` (`@patch("app.utils.s3.boto3")`), matching
  `test_organizations.py`'s established pattern — this dev environment has no real AWS
  credentials, so an unmocked call correctly 503s rather than silently skipping the test.
- `PaginationParams` (`app.api.deps`) is used for `/me/daily` as specified — this is one of its
  first two real consumers alongside whatever else has landed concurrently.

## Acceptance criteria

- [x] Employee can submit a Regularization request; it starts `Pending` —
      `test_submit_regularization_success`.
- [x] Date, punch selector and reason are required; `422` on missing/invalid values —
      `test_submit_regularization_invalid_reason_rejected`,
      `test_submit_regularization_missing_time_for_punch_rejected`.
- [x] Window and monthly-cap validation match the resolved shift's per-shift columns (or the
      hardcoded 7/3 defaults when no shift resolves) —
      `test_submit_regularization_outside_window_rejected` (asserts the "7-day" wording),
      `test_submit_regularization_monthly_cap_rejected` (asserts "limit of 3").
- [x] Future dates are rejected for Regularization —
      `test_submit_regularization_future_date_rejected`.
- [x] Duplicate active (Pending/Approved) requests for the same employee+date are blocked —
      `test_submit_regularization_duplicate_date_rejected`.
- [x] Employee sees their own request list and can cancel a Pending one; cannot act on another
      employee's request (404) — `test_cancel_own_pending_request`,
      `test_cannot_cancel_another_employees_request` (a real second employee's real request,
      not a bogus id, to prove the self-scoping actually holds).
- [x] `GET /me/daily` returns the paginated envelope shape, correct `is_late`/`is_regularized`
      derived fields, and never renders a NULL `attendance_status` as `"Absent"` —
      `test_my_daily_pagination_and_date_range`.
- [x] Attachment upload works via the plain multipart router and rejects uploads to a non-Pending
      or non-own request — `test_attachment_upload_success_and_guards`.
- [x] Cross-CDP isolation, 401, and encrypted round-trip tests pass for every `EncryptedRoute`
      endpoint added here — `test_regularization_endpoints_require_authentication` (401),
      `test_encrypted_submit_regularization_roundtrip`. Full backend suite: 326 passed, 2 failed
      — the same 2 pre-existing, unrelated `test_engagement_email.py` failures noted in tasks
      29-31's completion records.

Completed: 2026-08-18
