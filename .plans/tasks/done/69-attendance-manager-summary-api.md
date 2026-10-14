---
task: 69
title: Manager attendance dashboard — KPI summary API
status: done
depends_on: [68]
---

# 69 — Manager attendance dashboard — KPI summary API

## Scope

`GET /api/v1/attendance/analytics` — the KPI-row endpoint `docs/leave-and-attendance/attendance/
api-and-pages.md` §3.2 already reserves for the manager surface (currently "Not built"; used by
`hrManager/Attendance.tsx`'s hardcoded `ANALYTICS_BY_PERIOD`/KPI tiles per that file's own
top-of-file comment). Manager-scoped only in this task — the same route also serves admin
per the doc's §3.1 row, but that predicate ("any employee in the CDP") is not this task's
concern; just don't block it (see Authorization below, it falls out of the existing predicate for
free).

Returns the design prompt's (§4, §12) KPI counts for one date, one manager's direct reports:
`present_count`, `late_count`, `on_leave_count`, `absent_count`, `yet_to_checkin_count`,
`attendance_percentage`, plus the doc's own existing `/analytics` contract fields (period
trend numbers — see Response below) since the frontend's `ANALYTICS_BY_PERIOD` band (Total
logged hours / Timely logins / Late logins / Average logged hours / Punctuality % / Attendance
%) reads the same endpoint with `period=day|week|month`.

## Endpoint

`GET /attendance/analytics?date=2026-08-19&period=day&department=Cardiology&shift_id=4`

Query params:
- `date` (required, ISO date) — anchors both the KPI-row snapshot (always exactly this one date,
  regardless of `period`) and the trend window's end.
- `period` (`day|week|month`, default `day`) — controls only the trend numbers (`total_logged_
  minutes`, `average_logged_minutes`, `timely_logins`, `late` count over the period, `punctuality_
  pct`, `attendance_pct`), per design prompt §3 ("selected period controls analytics cards ...
  but should not unexpectedly change the daily employee table"). `week` = the ISO week containing
  `date`; `month` = the calendar month containing `date` — same range helpers the frontend
  already has in `EmployeeAttendanceTab.tsx` (`currentWeekRange`/`currentMonthRange`), just
  computed server-side here from `date` instead of "now".
- `department` (optional, matches `EmployeeMaster.department` string, case-sensitive exact match
  — same column the Directory filters already use, no new master table)
- `shift_id` (optional, `shift_master_id` — resolve via the employee's *effective* shift for
  `date`, using `resolve_effective_shift` from `app/services/calendar_resolver_service.py`, the
  same resolver `attendance_recompute_service.py` already calls — do not compare against
  `employee_shift_assignment` rows directly, an assignment can be superseded)
- No `work_location_id` param — explicitly excluded per design prompt §3/§13.
- No `team_id` — there is no team table in this codebase; "team" **is** "this manager's direct
  reports" (`reporting_manager_id`), which is the base scope, not a filter.

### Response

```json
{
  "date": "2026-08-19", "period": "day",
  "present_count": 6, "late_count": 2, "on_leave_count": 1, "absent_count": 1,
  "yet_to_checkin_count": 0, "attendance_percentage": 87.5,
  "total_logged_minutes": 3492, "average_logged_minutes": 349,
  "timely_logins": 4, "punctuality_pct": 66.7,
  "headcount": 8
}
```

`attendance_percentage` for the `date` snapshot: `count(effective_status == PRESENT) /
count(employees expected to work today)`, where "expected to work" excludes `ON_LEAVE`,
`WEEK_OFF`, `HOLIDAY` from the denominator — matches design prompt §14 exactly. For the `period`
trend fields, apply `gaps.md #35`'s definition literally: `Σ payable_day_fraction /
count(day_type = 'Working')` over the period's date range, across the same scoped employee set —
do not invent a different formula for the period case.

## Authorization & scope

Reuse `_manages`/`_require_caller_employee` exactly as they exist in `attendance/service.py`
(task 54's pattern) — do not add a new predicate helper. The employee set is: `principal.
is_admin` → every `EmployeeMaster` in the caller's CDP (via `EmployeeMaster.corp_master_id →
corp_masters.care_delivery_program_master_id`, same join `employees/service.py::list_employees`
uses); otherwise → `EmployeeMaster.reporting_manager_id == caller_employee.id` (direct reports
only, non-transitive, matching §3.3 of the project's own `docs/leave-and-attendance/README.md`).
A caller who is neither admin nor has any direct reports gets a `200` with all-zero counts, not
a `403` — this is a summary of *their own* scope, unlike the single-employee routes in task 54
where a non-report target is a permission error.

**CDP scoping is non-negotiable and untested-by-the-DB** — every `EmployeeAttendanceDetail` /
`EmployeeMaster` query here must filter by `principal.tenant_id`, same as every other query in
this module (`README.md` §2.2).

## Files

- `backend/app/modules/attendance/router.py` — one new `GET /analytics` route on the existing
  `EncryptedRoute` router
- `backend/app/modules/attendance/service.py` (or `dashboard_service.py`, matching wherever task
  68 landed) — `get_manager_analytics(db, principal, date, period, department, shift_id) ->
  AnalyticsOut`, built on task 68's `compute_effective_status`
- `backend/app/modules/attendance/schemas.py` — `AnalyticsOut`

## Tests (`app/tests/modules/test_attendance.py` or the new dashboard test file)

- Manager sees only direct reports' counts; a second manager's reports never leak in.
- `on_leave_count` matches employees with an approved leave covering `date` (reuse the same
  `leave_request_day_details` join `calendar_resolver_service.resolve_day_type` already performs
  — do not requery leave from scratch).
- Yesterday's date: a never-punched Working-day employee counts toward `absent_count`, not
  `yet_to_checkin_count` (task 68's date-boundary rule).
- Today's date: the same never-punched row counts toward `yet_to_checkin_count`, not
  `absent_count`.
- Cross-CDP employees never enter any count.
- `department`/`shift_id` filters narrow the counts correctly.
- Admin sees the whole CDP; a manager with zero direct reports gets all-zero counts, `200`.

## Acceptance criteria

- [x] Endpoint returns real, DB-derived counts — no hardcoded values.
- [x] `attendance_percentage` and the period trend fields use the formulas above, not an ad hoc
      one.
- [x] Manager scope and CDP scope both enforced server-side; covered by tests above.
