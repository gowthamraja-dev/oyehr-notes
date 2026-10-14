---
task: 151
title: Attendance date-range filter — KPI analytics + CSV export over a range (backend)
status: done
depends_on: [150]
---

# 151 — Analytics & register export accept a date range (backend)

> Part of requirement "4. Attendance Date Range Filters" (Manager/Admin register only; one row
> per employee-day). Work in **`workspace-2/hrms/`**; paths are relative to it.

## Scope

The page's date control drives the KPI tiles, analytics band and CSV export as well as the
register, so these must follow the range or the page would show different numbers for
different date windows. Reuse task 150's `_resolve_date_range` dependency (`date` | `from`+`to`,
same 422 rules, `MAX_REGISTER_RANGE_DAYS = 31`) and `_build_scoped_rows_for_range`.

**Not in this task:** register/exceptions (150), frontend (152-154), docs (155).

### `GET /api/v1/attendance/analytics`
Today: KPI counts are a single-day snapshot of `date` (`get_manager_analytics` in
`backend/app/modules/attendance/dashboard_service.py`); the analytics band (total/average logged
minutes, timely logins, punctuality %) uses `_period_range(period, date)`.

- `?date=X&period=…` → **unchanged**.
- `?from=A&to=B` → `period` ignored; response `period = "range"` (extend the `Literal` in
  `AnalyticsOut`), and `AnalyticsOut` gains `from`/`to` (`Field(alias="from")`); `date` = `from`.
  - `present_count`, `late_count`, `on_leave_count`, `absent_count` = **employee-day** counts
    over the range, using the same `compute_effective_status` per employee-day (build from the
    range rows, not a second derivation).
  - `yet_to_checkin_count` only counts employee-days that are "today" in the employee's tz.
  - `attendance_percentage` = present employee-days / (employee-days minus OnLeave/WeekOff/
    Holiday), one decimal, `0.0` if the denominator is 0.
  - `headcount` = distinct scoped employees (after the per-day `shift_id` filter: an employee
    counts if they matched on at least one day).
  - Band metrics computed over `[from, to]` instead of `_period_range`.
- Log line gains `from`/`to`.

### `GET /api/v1/attendance/register/export` (plain router, CSV)
- Accepts the same range params; rows = the same employee-day rows `/register` returns for
  those filters (unpaginated), sorted like `sort=date` in range mode, `status` otherwise.
- CSV gets a leading **`Date`** column (always — single-date exports too), formatted
  **dd-MMM-yy** per the `hrms-date-format` skill, plus a `Day` column (weekday).
- Filename: `attendance-{from}.csv` for one day (unchanged), `attendance-{from}_to_{to}.csv` for
  a range (router builds the `Content-Disposition`).
- `AttendanceAuditLog` `AttendanceExported` `new_value` gains `"from"` / `"to"`; keep `"date"`
  (= `from`) so existing audit readers don't break.

## Files
- `backend/app/modules/attendance/router.py` — `/analytics` and `/register/export` use
  `_resolve_date_range`; export filename.
- `backend/app/modules/attendance/dashboard_service.py` — `get_manager_analytics(from_, to, …)`,
  `export_register_csv(from_, to, …)`, `_CSV_HEADER`.
- `backend/app/modules/attendance/schemas.py` — `AnalyticsOut.period` Literal + `from_`/`to`.
- `backend/app/tests/modules/test_attendance_dashboard.py`.

## Acceptance criteria
- [x] `?date=X&period=day|week|month` analytics unchanged (existing tests green).
- [x] Range analytics: employee-day counts, attendance %, and band metrics match hand-computed
      values for a seeded 3-employee × 5-day fixture incl. a leave day, a week-off and a late day.
- [x] Range analytics 422s match task 150's rules.
- [x] Export over a range: one CSV line per employee-day, `Date` column in dd-MMM-yy, range
      filename, audit row stores `from`/`to`.
- [x] Single-date export still works; its only change is the new `Date`/`Day` columns.
- [x] Tenant scoping: another CDP's rows never appear in range analytics counts or the CSV.
- [x] Manager sees only direct reports in both; 401/403 cases covered.
- [x] `uv run pytest app/tests/modules/test_attendance_dashboard.py` green.

## What shipped
Branch `feature/gowtham_AttendanceDateRange` in `workspace-2/hrms/`.

- `/analytics` and `/register/export` take task 150's `_DateRange` (same 422 rules).
- `get_manager_analytics(from_, to, …)`: single date keeps its pre-151 body. A range goes to
  `_manager_analytics_for_range`, built on `_build_scoped_rows_for_range` (per-day shift filter,
  employee-day counts, % excludes OnLeave/WeekOff/Holiday, headcount = distinct employees). The band
  rules moved into `_logged_time_band`, shared by both paths (identical, since the minute
  columns are NOT NULL).
- `AnalyticsOut`: `period` gains `"range"`, plus `from`/`to` = the band window (the `period`
  window for a single date, the range otherwise).
- Export: leading `Date` (dd-MMM-yy) and `Day` columns on every export. Range rows run
  newest day → status → name. Filename is `attendance-{from}_to_{to}.csv` for a range, and the audit
  `new_value` gains `from`/`to` (`date` = `from` kept).
- Tests: 7 new (range analytics hand-computed over 3 employees × 5 days incl. leave/week-off/late,
  single-date band window, 422s, admin scope + 401/403, range CSV lines/order/filename/cross-CDP,
  audit from/to, export 401/422). `test_export_csv_header_and_row` was updated for the new
  columns and asserts the single-date filename is unchanged.
  `test_attendance_dashboard.py` now 99 passed; batch resolver 5 passed;
  attendance/recompute/assembler/authz/shifts 288 passed; ruff clean.
- Correction to task 150's record: it added **25** tests to `test_attendance_dashboard.py`
  (not 26). The file collected 92 after task 150.

Completed: 2026-09-29
