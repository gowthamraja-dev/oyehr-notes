---
task: 70
title: Manager attendance dashboard — register (list) API
status: done
depends_on: [68]
---

# 70 — Manager attendance dashboard — register (list) API

## Scope

`GET /api/v1/attendance/register` — the daily attendance table endpoint `api-and-pages.md` §3.2
and §4.4 already reserve (currently "Not built"). This is the "still-mock-data" reason
`hrManager/Attendance.tsx`'s `REGISTER` array exists — replaces it entirely.

Server-side search, filter, sort, pagination over one manager's direct reports' (or, for admins,
the whole CDP's) attendance for **one date** — never the whole org, never unpaginated (design
prompt §7).

## Endpoint

`GET /attendance/register?date=2026-08-19&department=Cardiology&shift_id=4&status=late&search=rohan&sort=name&direction=asc&limit=25&offset=0`

Query params (extends the doc's §4.4 sketch — `search`/`sort`/`direction` are additions this
task makes explicit, since the design prompt requires them and the original doc sketch predates
that requirement; note this as a doc update in task 81, don't silently diverge):

- `date` (required)
- `department` (optional, exact match on `EmployeeMaster.department`)
- `shift_id` (optional, effective shift for `date` — same resolution as task 69)
- `status` (optional: `all|present|late|onleave|absent|weekoff|holiday|yettocheckin`, default
  `all`) — `late` is the range predicate from task 68 (`late_by_minutes > 0 AND day_type=
  'Working'`), **not** `effective_status == PRESENT` filtered further; every other value is an
  `effective_status` equality (task 68's enum)
- `search` (optional) — matches `EmployeeMaster.frst_nm`/`lst_nm`/`emp_id`/`mobile`
  case-insensitively, same columns the Directory search already covers
  (`employees/service.py::list_employees`'s search clause — mirror it, don't reinvent)
- `sort` (`name|status|clock_in|clock_out|worked_hours|late_by`, default `status`) paired with
  `direction` (`asc|desc`, default `asc`). Default sort with no explicit `sort` param is
  **status priority + employee name** per design prompt §7 — status priority order is the
  precedence list in task 68 (`Absent` and `Late` surfaced before `Present`, `WeekOff`/`Holiday`/
  `OnLeave` last), then name ascending as the tiebreaker.
- `limit`/`offset` — reuse the existing `PaginationParams` dependency from `app.api.deps`, same
  as `/me/daily`/`/employees/{id}/daily`, not the Directory's `page`/`page_size` convention (stay
  consistent with this module's own existing pagination shape).
- No `work_location_id`, no `team_id` — same reasoning as task 69.

### Response

Matches `api-and-pages.md` §4.4's shape, extended with the fields the design prompt's table (§6)
needs and task 68's classifier produces:

```json
{
  "items": [
    {
      "employee_master_id": 38, "emp_id": "NH-0142", "name": "Rohan Desai",
      "department": "Cardiology", "shift_name": "Morning",
      "avatar_initials": "RD",
      "first_in_at": "2026-08-19T04:02:00Z", "last_out_at": null,
      "worked_minutes": 0, "worked_hours_display": "Incomplete",
      "effective_status": "Present", "is_late": true, "late_by_minutes": 32,
      "day_type": "Working",
      "has_pending_regularization": false
    }
  ],
  "total": 24, "limit": 25, "offset": 0
}
```

`has_pending_regularization`: `true` if an `AttendanceRequestDetail` row exists for this
employee/date with `status = 'Pending'` — feeds the design prompt §10 "Regularization pending ·
Review" row treatment. Do not duplicate regularization data here beyond this one boolean +
enough to link to it (the existing `GET /attendance/requests/{id}` detail is where the frontend
navigates on "Review" — see task 78).

## Authorization & scope

Identical predicate and CDP-scoping rules as task 69 — reuse the same scope-resolution helper
task 69 builds (`_resolve_scoped_employee_ids(db, principal) -> list[int] | None` — `None`
meaning "whole CDP" for admins is a reasonable internal shape; do not duplicate the manager/admin
branching between tasks 69 and 70, factor it once and have both call it).

## Files

- `backend/app/modules/attendance/router.py` — one new `GET /register` route
- `backend/app/modules/attendance/service.py` / `dashboard_service.py` — `get_manager_register(db,
  principal, date, department, shift_id, status, search, sort, direction, limit, offset) ->
  RegisterOut`
- `backend/app/modules/attendance/schemas.py` — `RegisterRowOut`, `RegisterOut`

## Tests

- Search matches name, `emp_id`, and mobile.
- Each `status` filter value returns exactly the rows task 68's classifier would produce for a
  hand-built fixture set (reuse the yesterday/today Absent-vs-YetToCheckIn fixtures from task 68
  where relevant).
- Default sort is status-priority-then-name; explicit `sort=clock_in&direction=desc` works.
- Pagination `total`/`limit`/`offset` are correct across a >1-page fixture set.
- Manager sees only direct reports; cross-CDP rows never appear; admin sees the whole CDP.
- A row with `first_in_at` set and `last_out_at` null → `worked_hours_display: "Incomplete"`,
  `worked_minutes` not misrepresented as a completed duration.

## Acceptance criteria

- [x] Endpoint never returns more than one page of rows to the client regardless of org size —
      `limit`/`offset` are always applied server-side, not "return-all-then-slice".
- [x] Every filter/search/sort combination above is covered by a test.
- [x] Manager/CDP scoping enforced and tested.
