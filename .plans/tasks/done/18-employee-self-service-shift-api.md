---
task: 18
title: "Employee self-service shift APIs — GET /shifts/me and GET /shifts/me/{date}"
status: done
depends_on: []
---

# 18 — Employee self-service shift APIs (`GET /shifts/me`, `GET /shifts/me/{date}`)

## Scope

Add the two endpoints from `.design/prompts/Shift Assignment — Manager & Employee UI
Implementation Prompt.md` §17 "Employee" section that do not exist yet:

- `GET /api/v1/shifts/me` — the caller's current + upcoming shifts.
- `GET /api/v1/shifts/me/{date}` — the caller's shift for one specific date.

(Use the `/shifts/me*` path, not a bare `/me/shifts` — this module's router already owns the
`/shifts` prefix per `backend/app/modules/shifts/router.py`; there is no separate `/me` router in
this codebase and creating one just for this would fragment routing for no benefit.)

Confirmed via repo search: **no employee self-service shift endpoint exists today.**
`backend/app/modules/shifts/router.py` only has admin/manager-facing routes
(`/shifts`, `/shifts/employee-shifts`, `/shifts/team/employee-shifts`, `/shifts/assignments*`) —
every one of them requires `_require_admin` or `_require_manager_or_admin` in `service.py`. An
employee with no reports and no admin flag cannot call any of them for their own id today.

## The per-date-vs-standing resolution decision (read before writing the query)

Two independent tables can each claim to be "the employee's shift for date X" —
`docs/leave-and-attendance/shifts/gaps.md` #43 documents that they are unsynced:

- `employee_shift_assignments` (per-date, `app/models/employee_shift_assignment.py`) — what the
  Manager Portal's roster grid writes (`shifts/service.py: create_shift_assignment` etc.). This is
  what actually reflects a manager's day-by-day override for a rotational employee, per the
  design prompt §8 ("the roster is therefore the source of the employee's actual shift for a
  specific date").
- `employee_shift_details` (effective-dated range, `app/models/employee_shift_detail.py`) — the
  "standing" assignment, what the attendance assembler currently reads.

Gap #43 leaves the *attendance-calculation* side of this unresolved on purpose — do not touch
`app/modules/attendance/service.py` in this task, and do not attempt to make the assembler read
`employee_shift_assignments` (that is a separate, larger decision explicitly out of scope per the
design prompt §15: "the exact overtime/early-departure policy should not be invented as part of
this UI task").

For this task's narrower "what shift does the employee see for date X" question, resolve with a
simple, documented precedence — **per-date assignment wins if one exists and is `ASSIGNED`;
otherwise fall back to the standing detail effective on that date; otherwise no shift**:

```python
def _resolve_employee_shift(db, tenant_id, employee_id, target_date) -> ShiftMaster | None:
    per_date = db.scalar(
        select(EmployeeShiftAssignment).where(
            EmployeeShiftAssignment.employee_master_id == employee_id,
            EmployeeShiftAssignment.assignment_date == target_date,
            EmployeeShiftAssignment.status == "ASSIGNED",
        )
    )
    if per_date is not None:
        return _get_shift_by_id(db, tenant_id, per_date.shift_master_id)

    standing = db.scalar(
        select(EmployeeShiftDetail).where(
            EmployeeShiftDetail.employee_master_id == employee_id,
            EmployeeShiftDetail.effctv_dt <= target_date,
            or_(EmployeeShiftDetail.trmntn_dt.is_(None), EmployeeShiftDetail.trmntn_dt >= target_date),
        )
        .order_by(EmployeeShiftDetail.effctv_dt.desc())
    )
    return _get_shift_by_id(db, tenant_id, standing.shift_master_id) if standing else None
```

## Files

- `backend/app/modules/shifts/schemas.py` — add `MyShiftOut` (date, shift fields inline —
  `shift_master_id`, `name`, `code`, `color`, `start_time`, `end_time`, `is_day_off`,
  `is_night_shift` — plus `source: Literal["assignment", "standing"]` so the frontend/tests can
  tell which table answered) and `MyShiftsOut` (`shifts: list[MyShiftOut]`).
- `backend/app/modules/shifts/service.py` — add `_resolve_employee_shift` (above) and:
  - `get_my_shift(db, principal, target_date) -> MyShiftOut | None` — resolves the caller's own
    `employee_master_id` via `_require_caller_employee` (already exists, used by
    `list_team_employee_shifts`), then calls `_resolve_employee_shift`. Returns `None` if nothing
    resolves (not a 404 — "no shift assigned for this date" is a valid state, matching
    `EmployeeRosterOut`'s empty-assignments precedent, not an error).
  - `list_my_shifts(db, principal, from_dt, to_dt) -> MyShiftsOut` — same caller resolution, one
    row per date in `[from_dt, to_dt]` inclusive via `_resolve_employee_shift` per day. Default
    range when the router receives no `from`/`to`: today through +13 days (two weeks), matching
    the design prompt §13 "Upcoming shifts" example. Skip dates that resolve to `None` (don't
    emit empty rows for days genuinely unscheduled).
- `backend/app/modules/shifts/router.py` — add, in the existing `EncryptedRoute` router:
  ```python
  @router.get("/me", response_model=MyShiftsOut)
  def list_my_shifts(
      principal: CurrentPrincipal, db: DbSession,
      from_dt: date | None = Query(default=None, alias="from"),
      to_dt: date | None = Query(default=None, alias="to"),
  ) -> MyShiftsOut:
      return service.list_my_shifts(db, principal, from_dt, to_dt)

  @router.get("/me/{target_date}", response_model=MyShiftOut | None)
  def get_my_shift(target_date: date, principal: CurrentPrincipal, db: DbSession) -> MyShiftOut | None:
      return service.get_my_shift(db, principal, target_date)
  ```
  Place these **above** the existing `/{shift_id}` PATCH route's path-param routes if FastAPI
  route-ordering could make `/me` match `/{shift_id}`'s pattern — check whether `/{shift_id}` is
  declared as an int path param (it is: `shift_id: int`), which means `/me` (a string) won't
  match it and ordering doesn't matter; still, put the new routes in their own
  `# ── Employee self-service ──` section for readability, near `/team/employee-shifts`.
- `backend/app/tests/modules/test_shifts.py` — add a new section following this file's existing
  style (see `test_team_employee_shifts_*` for the caller-employee-record pattern):
  - `test_my_shifts_unauthenticated` — 401.
  - `test_my_shifts_requires_caller_employee_record` — a principal with no `EmployeeMaster` row
    (via `user_id`) gets `PermissionDenied` (403), same as `test_team_employee_shifts_requires_caller_employee_record`.
  - `test_my_shift_for_date_resolves_from_per_date_assignment_over_standing` — seed both an
    `EmployeeShiftDetail` (standing) and an `EmployeeShiftAssignment` (per-date, different shift)
    for the same employee/date; assert `GET /shifts/me/{date}` returns the per-date one with
    `source: "assignment"`.
  - `test_my_shift_for_date_falls_back_to_standing_when_no_per_date_row` — only the standing row
    exists; assert the response has `source: "standing"`.
  - `test_my_shift_for_date_returns_none_when_nothing_resolves` — neither row exists; assert
    `200` with a `null`/empty body (not `404`).
  - `test_my_shifts_range_returns_one_entry_per_resolved_date` — assignments on 2 of 5 days in
    range, standing detail covering the other 3; assert 5 entries, correct `source` per day.
  - `test_my_shifts_scoped_to_caller_only` — a second employee's assignments in the same date
    range are never returned to the first employee's token.
  - `test_encrypted_my_shifts_roundtrip` — follow the existing
    `test_encrypted_team_employee_shifts_roundtrip` pattern (this router is `EncryptedRoute`).

## Explicitly out of scope

- **Leave-conflict signaling** (design prompt §10) — no `leave_request`-type model exists in this
  codebase (confirmed by task 16's Discussion section and `docs/leave-and-attendance/leave/
  gaps.md`); there is nothing to query. Do not invent a leave check. Covered in task 20's docs
  update, not here.
- Wiring `employee_shift_assignments` into `app/modules/attendance/service.py`'s late/OT/overtime
  calculation (gap #43's attendance half) — separate, larger decision, not this task.
- Overnight-shift-crosses-midnight attendance association (design prompt §16) — that's an
  attendance-assembler concern (`docs/leave-and-attendance/attendance/assembler.md`), not this
  read-only self-service endpoint.

## Acceptance criteria

- [x] `GET /api/v1/shifts/me?from=&to=` returns the caller's own resolved shifts for the range
      (default: today .. +13 days when `from`/`to` omitted), each dated entry showing
      `source: "assignment"` or `"standing"`.
- [x] `GET /api/v1/shifts/me/{date}` returns the caller's resolved shift for one date, or a null
      body when nothing resolves (not a 404).
- [x] Per-date `employee_shift_assignments` rows take precedence over `employee_shift_details`
      when both exist for the same date.
- [x] Both endpoints are scoped to the caller's own `employee_master_id` only — never accept or
      honor an `employee_master_id` query param from the client.
- [x] Both endpoints 401 unauthenticated and 403 when the caller has no `EmployeeMaster` row.
- [x] `uv run pytest app/tests/modules/test_shifts.py` passes, including the new tests listed
      above. (63 passed — 54 pre-existing + 9 new.)

Completed: 2026-08-17
