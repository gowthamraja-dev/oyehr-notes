---
task: 54
title: Attendance module — manager/admin-scoped per-employee daily log endpoint
status: done
depends_on: []
---

# 54 — Attendance module — manager/admin-scoped per-employee daily log endpoint

## Discussion

The design prompt's employee-profile Attendance tab (§9) must "reuse the Attendance module's
employee-level API/data" and explicitly must **not** build a separate attendance data model.
Checked `backend/app/modules/attendance/router.py`: every existing read endpoint is `/me/*`
(`get_today`, `get_my_daily` — self only, via `_require_caller_employee`) or the regularization
**queue** (`GET /requests`, which lists pending/actioned regularization requests, not a
day-by-day attendance calendar). There is currently no way for a manager or admin to view
*another* employee's attendance at all. This task adds exactly that, reusing the same
`EmployeeAttendanceDetail` data and `DailyLogRow`/`DailyLogOut` shapes `get_my_daily` already
produces — this is a new authorization path onto existing data and existing query logic, not a
new table or a new response shape.

### Authorization — generalize the existing regularization-inbox predicate

`attendance/service.py` already has exactly the right predicate, just scoped to one request
object:

```python
def _manages(db: Session, manager_employee_id: int, target_employee_id: int) -> bool: ...
def _require_manager_or_admin_for(db: Session, principal: AuthPrincipal, req: AttendanceRequestDetail) -> None: ...
```

Add a sibling that takes an `employee_id` directly instead of a request row:

```python
def _require_manager_or_admin_for_employee(db: Session, principal: AuthPrincipal, employee_id: int) -> None:
    if principal.is_admin:
        return
    caller_employee = _require_caller_employee(db, principal)
    if employee_id == caller_employee.id:
        return  # viewing your own attendance through this path is fine
    if not _manages(db, caller_employee.id, employee_id):
        raise PermissionDenied("Not your direct report")
```

Reuse `_manages` as-is (already generic — takes two employee ids). Do not duplicate it.

### Endpoint

`GET /attendance/employees/{employee_id}/daily` — same response model (`DailyLogOut`) and same
query params (`from`/`to`/`limit`/`offset` via the existing `PaginationParams` dependency) as
`GET /me/daily`, just parameterized by path `employee_id` instead of the caller's own employee
row, and gated by `_require_manager_or_admin_for_employee` instead of `_require_caller_employee`.
Internally, factor `get_my_daily`'s query-building body into a shared
`_daily_log(db, tenant_id, employee_id, from_, to, limit, offset) -> DailyLogOut` that both
`get_my_daily` (self) and the new `get_employee_daily` (manager/admin) call — do not copy-paste
the query.

Also add `GET /attendance/employees/{employee_id}/today` mirroring `GET /me/today` /`TodayOut`
the same way, for the profile tab's "day" view (design prompt §9 lists Day/Week/Month — "Day" is
`today`-shaped, "Week"/"Month" are `daily` with a `from`/`to` range the frontend computes).

`employee_id` must be resolved through the same CDP the caller belongs to before any attendance
row is queried — reuse `EmployeeMaster`/`CorpMaster` join scoping exactly like `employees/
service.py`'s `get_employee` does; an `employee_id` belonging to another CDP must 404, not 403
(matches this codebase's established "don't leak existence across tenants" idiom).

## Files

- `backend/app/modules/attendance/router.py` — two new `GET` routes under the existing
  `EncryptedRoute` router
- `backend/app/modules/attendance/service.py` — `_require_manager_or_admin_for_employee`,
  `_daily_log` extraction, `get_employee_daily`, `get_employee_today`

## Tests (extend `backend/app/tests/modules/test_attendance.py`)

- A manager viewing a direct report's `/daily`/`/today` succeeds.
- A manager viewing a non-report → `403`.
- A manager viewing their own id through this path → `200` (not blocked as "not a report of
  yourself").
- Admin can view any employee in the CDP.
- `employee_id` from another CDP → `404`, not `403`, not a leaked row.
- Response shape for both new routes matches `get_my_daily`/`get_today`'s existing shape exactly
  (reuse the same assertions those tests already make, parameterized by employee id instead of
  the caller).

## Acceptance criteria

- [x] A manager can view a direct report's attendance (day/week/month, via `from`/`to`) without
      any new attendance table or duplicated query logic — `_daily_log` is called by both the
      self and manager/admin routes.
- [x] Cross-tenant employee ids 404 before any attendance data is touched.
- [x] `_manages`/`_require_manager_or_admin_for` (the existing regularization-inbox helpers) are
      reused, not reimplemented, for the new predicate.

## Completion notes

- `get_today`/`get_my_daily` were split into thin self-scoped wrappers calling new
  tenant_id/employee_id-parameterized cores (`_today_snapshot`, `_daily_log`); the new
  `get_employee_today`/`get_employee_daily` call the same cores after
  `_require_employee_in_tenant` (CDP scoping, 404 on cross-tenant) +
  `_require_manager_or_admin_for_employee` (reuses `_manages` as-is, per the task's own note).
- Routes added: `GET /attendance/employees/{employee_id}/today` and
  `GET /attendance/employees/{employee_id}/daily`, same response models/query params as their
  `/me/*` counterparts.
- 7 new tests in `test_attendance.py`: auth gating, manager-views-report success, non-report
  403, self-view-through-this-path 200, admin-any-employee 200, cross-CDP 404, and a response-
  shape assertion that both new routes' keys exactly match `TodayOut`/`DailyLogRow`'s fields.
  Full suite (75 tests) green; no regression in the 68 pre-existing attendance tests after the
  `get_today`/`get_my_daily` refactor.

Completed: 2026-08-19
