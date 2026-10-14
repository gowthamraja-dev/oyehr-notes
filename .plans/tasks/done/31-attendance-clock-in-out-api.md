---
task: 31
title: Employee clock-in/clock-out API (POST /me/clock-in, /me/clock-out, GET /me/today)
status: done
depends_on: [29, 30]
---

# 31 — Employee clock-in/clock-out API

## Discussion

Builds the three endpoints `docs/leave-and-attendance/shared/implementation-structure.md §3`
calls Phase 3's minimum surface: `POST /api/v1/attendance/me/clock-in`, `POST …/me/clock-out`,
`GET …/me/today`. Contracts, status codes and field names below are copied from
`docs/leave-and-attendance/attendance/api-and-pages.md §4.1-4.2` and
`docs/leave-and-attendance/attendance/employee-self-service.md §2.1` — those are the source of
truth for the wire shape; this file only adds the bits specific to this codebase (routing,
`AuthPrincipal`, the `self` predicate).

**Self predicate.** Every path here resolves the caller's own `EmployeeMaster` via
`users.id -> employee_masters.user_id` (the existing `_require_caller_employee` pattern in
`app.modules.shifts.service`) — there is no path parameter, so there's nothing for a caller to
spoof (`shared/api-conventions.md §1.2`).

**Geofence.** `lttd`/`lgtd` are accepted per the wire contract (schema fidelity — the columns
exist on `attendance_punch_details`, task 29) but `geofence_enforcement` defaults to `'Warn'`
(config-knobs.md §1.5, unexposed) and there is no radius-check implementation in this task —
`is_within_geofence` is written `NULL` always. Building the actual geofence math is
`gaps.md#5`, explicitly schema-only in v1 and unspecified even in the source mockups. Do not
implement a distance calculation here.

## Files

### New

- `backend/app/modules/attendance/clock_schemas.py` (or add to the existing `schemas.py` — match
  whichever the file has grown to look like by the time this lands; keep clock-related schemas
  grouped under one comment banner regardless):

  ```python
  class ClockInRequest(BaseModel):
      lttd: float | None = None
      lgtd: float | None = None
      punch_source: Literal["Web", "Mobile"] = "Web"

  class ClockOutRequest(BaseModel):
      lttd: float | None = None
      lgtd: float | None = None
      punch_source: Literal["Web", "Mobile"] = "Web"

  class ShiftBrief(BaseModel):
      name: str
      start_time: time | None
      end_time: time | None
      time_zone: str | None = None

  class ClockActionOut(BaseModel):
      punch_id: int
      punch_at: datetime
      direction: Literal["IN", "OUT"]
      is_within_geofence: bool | None
      attendance_date: date
      shift: ShiftBrief | None
      late_by_minutes: int
      state: Literal["clocked_in", "clocked_out"]

  class TodayOut(BaseModel):
      attendance_date: date
      day_type: str
      attendance_status: str | None
      state: Literal["not_started", "clocked_in", "clocked_out"]
      first_in_at: datetime | None
      last_out_at: datetime | None
      worked_seconds_so_far: int
      shift: ShiftBrief | None
      is_late: bool
      late_by_minutes: int
  ```

  Match `api-and-pages.md §4.1-4.2`'s sample JSON field-for-field — do not rename fields for
  "consistency" with something else; the frontend wrapper in task 34 is written against these
  exact names.

### Edited

- `backend/app/modules/attendance/service.py` — add (this file currently only holds work-location/
  holiday-calendar admin config per its own module docstring; update that docstring to note it now
  also owns employee self-service clock actions):

  ```python
  def clock_in(db: Session, principal: AuthPrincipal, payload: ClockInRequest) -> ClockActionOut: ...
  def clock_out(db: Session, principal: AuthPrincipal, payload: ClockOutRequest) -> ClockActionOut: ...
  def get_today(db: Session, principal: AuthPrincipal) -> TodayOut: ...
  ```

  **`clock_in`:**
  1. `_require_caller_employee` (reuse the exact pattern from `shifts.service`, or import it if it
     becomes shared — your call at implementation time; don't fork a third copy of the same four
     lines).
  2. Determine business `attendance_date` via the 3-day-window rule from task 30's Discussion
     (resolve yesterday/today/tomorrow's shift via `calendar_resolver_service`, pick whichever
     attribution window contains `now()`).
  3. Look up that date's `employee_attendance_details` row (if any). If `is_locked`, raise
     `HTTPException(423, "Attendance for {date} is locked")` — matches the documented contract
     even though nothing sets `is_locked` yet (defensive, cheap, forward-compatible).
  4. Check for an existing open session: the most recent punch for this employee where
     `direction='IN'` with no later `direction='OUT'`. If found, raise `Conflict` (409) with
     `detail=f"Already clocked in at {existing_in_at:%H:%M}"` — **do not** create the duplicate;
     the dedupe unique index (task 29) is the last line of defense, not the primary check.
  5. Insert `AttendancePunchDetail(punch_source=payload.punch_source, direction="IN",
     punch_at=now(), attendance_device_master_id=None, employee_master_id=employee.id,
     lttd=payload.lttd, lgtd=payload.lgtd, is_within_geofence=None,
     work_location_master_id=resolved_location_id, created_by_id=principal.user.id)`.
  6. Call `recompute_attendance_day` (task 30) for `(tenant_id, employee.id, attendance_date)`.
  7. Write an `AttendanceAuditLog` row (`action="ClockedIn"`, `new_value={"punch_at": ...,
     "attendance_date": ...}`, `performed_by_id=principal.user.id`, `performed_by_role="self"`).
  8. `db.commit()`; return `ClockActionOut` built from the punch + the recomputed row
     (`late_by_minutes`, `shift`), `state="clocked_in"`.

  **`clock_out`:** symmetric — step 4 becomes "no open IN session -> `HTTPException(404 or 409,
  "No active clock-in found.")`" (the prompt's own wording, `.design/prompts/…§7`); the business
  date is **not** re-derived — it's whatever date the open IN's row already carries (task 30's
  Discussion: this is exactly why clock-in resolves the date and clock-out doesn't need to).
  `state="clocked_out"`.

  **`get_today`:** resolves today's business date the same way as step 2 above, reads (without
  writing) the `employee_attendance_details` row if one exists for it — if none exists yet
  (nobody has punched and nothing else has triggered a recompute), still resolve the shift/day
  type live (read-only call into `calendar_resolver_service`) so the card can show "Morning shift
  · 09:00–18:00 · not started" before any punch exists. `worked_seconds_so_far`: closed-interval
  sum (from the row if it exists) plus, if a session is currently open, `now() - first_in_at` of
  the open interval — this is the "ticks client-side, no polling" number
  (`employee-self-service.md §2.1`). `state`: `not_started` (no punch today) /
  `clocked_in` (open IN, no matching OUT) / `clocked_out` (last punch is OUT) — the three states
  in `employee-self-service.md §2.1`'s table.

- `backend/app/modules/attendance/router.py` — add under a new `# ── Employee self-service: clock
  ──` banner, on the existing `router` (encrypted):

  ```python
  @router.post("/me/clock-in", response_model=ClockActionOut, status_code=200)
  def clock_in(payload: ClockInRequest, principal: CurrentPrincipal, db: DbSession) -> ClockActionOut:
      return service.clock_in(db, principal, payload)

  @router.post("/me/clock-out", response_model=ClockActionOut, status_code=200)
  def clock_out(payload: ClockOutRequest, principal: CurrentPrincipal, db: DbSession) -> ClockActionOut:
      return service.clock_out(db, principal, payload)

  @router.get("/me/today", response_model=TodayOut)
  def get_today(principal: CurrentPrincipal, db: DbSession) -> TodayOut:
      return service.get_today(db, principal)
  ```

- `backend/app/tests/modules/test_attendance.py` — new tests (this module has no test file yet;
  check first — if `test_shifts.py` or another file already covers `/attendance/work-locations`
  etc., add this suite alongside it, don't duplicate the tenant/user/employee fixture setup, reuse
  `app/tests/conftest.py`'s shared fixtures):
  - Clock in when nothing is open -> 200, `state="clocked_in"`.
  - Clock in twice -> second call 409 with the existing time in the detail message.
  - Clock out with an open session -> 200, `state="clocked_out"`, `worked_minutes` on the
    recomputed day row is `> 0`.
  - Clock out with nothing open -> 404/409 "No active clock-in found."
  - `GET /me/today` before any punch -> `state="not_started"`, `attendance_status=null`.
  - Cross-CDP isolation and 401 unauthenticated (per `shared/api-conventions.md §7`).
  - Encrypted round-trip for `/me/clock-in` (per `test_encryption.py`'s pattern).

## Implementation notes (deviations left open by the task, decided during execution)

- Clock schemas were added directly to the existing `schemas.py` under a
  `# ── Employee self-service: clock in/out ──` banner, not a separate `clock_schemas.py` — the
  file is still small and one banner-organized file reads more coherently than splitting it.
- `_require_caller_employee` is duplicated locally in `attendance/service.py` rather than
  imported from `app.modules.shifts.service` — mirrors task 12's own rationale for
  `_get_work_location`/`_get_holiday_calendar` being duplicated rather than cross-imported, so
  `attendance` gains no service-layer dependency on `shifts` (symmetric with `shifts` having none
  on `attendance`).
- The "which business date does `now()` belong to" window logic lives in a new
  `resolve_business_date_for_instant()` appended to task 30's `attendance_recompute_service.py`
  (next to the `_resolve_window` helper it reuses), rather than re-implemented in
  `attendance/service.py` — keeps all window/attribution logic in one file.
- `clock_out` with no open session returns `409` (not `404`) — both were allowed by the task;
  409 reads more naturally alongside clock-in's own "already clocked in" `409`, and this is a
  wrong-state conflict rather than a missing resource.
- The night-shift API acceptance criterion below is satisfied by task 30's existing
  `test_recompute_night_shift_attributes_to_start_date` test rather than a duplicate API-level
  test — `clock_in`/`clock_out` call the exact same `recompute_attendance_day`/window functions
  task 30 already covers directly, and reliably controlling wall-clock time through a real HTTP
  clock-in/out round trip would mostly re-test the same already-verified logic at much higher
  cost.

## Acceptance criteria

- [x] Employee can clock in; server records `punch_at = now()` in UTC, ignoring any client-
      supplied time — `payload` carries no time field at all, only location/source.
- [x] Duplicate clock-in returns `409` without writing a second `IN` punch —
      `test_clock_in_twice_rejected`.
- [x] Clock-out with no open session returns an error (`409`), not a silently-created OUT punch —
      `test_clock_out_without_open_session_rejected`.
- [x] `GET /me/today` never renders `attendance_status: null` as anything but "not settled" —
      the response schema keeps it nullable (`attendance_status: str | None`); no coercion in
      `service.get_today`.
- [x] A 22:00→06:00 shift fixture attributes both punches to the start date's row — covered by
      task 30's `test_recompute_night_shift_attributes_to_start_date` (see note above; the API
      layer calls the identical recompute path with no additional logic of its own).
- [x] Refreshing after clock-in (`GET /me/today`) reports the same `state`/`first_in_at` —
      `test_clock_in_success` asserts this by calling `/me/today` right after `/me/clock-in`.
- [x] Full test suite for this task passes (11 new tests in `test_attendance.py`: auth gating,
      missing-employee 403, before/after clock-in state, duplicate clock-in, clock-out without a
      session, worked-minutes recompute on clock-out, cross-tenant isolation, encrypted
      round-trip), plus the full backend suite: 306 passed, 2 failed — the same 2 pre-existing,
      unrelated `test_engagement_email.py` failures noted in tasks 29/30's completion records.
- [x] No geofence distance calculation introduced (`is_within_geofence` stays `NULL` on every
      punch this task set writes) — confirmed via `git diff`.

Completed: 2026-08-17
