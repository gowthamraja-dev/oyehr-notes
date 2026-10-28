---
task: 278
title: Daily log report + move the existing register CSV onto the engine
status: done
depends_on: [275]
---

# 278 — Daily log report + move the existing register CSV onto the engine

## Scope
1. Report type `daily_log`: **one row per employee-day** (the detail/audit layout). It is the current register CSV
   (`dashboard_service.export_register_csv`, endpoint `GET /attendance/register/export`) re-expressed as an engine handler, with extra columns.
2. Re-point `GET /attendance/register/export` at the engine so there is **one** CSV code path. The URL, query params (`from/to/date`, department, shift,
   status, search), filename and the **existing CSV columns/values must not change** — `hrManager/Attendance.tsx` (`exportAttendanceRegister`) keeps working
   untouched until 279 replaces its button. Existing tests (`test_attendance_dashboard.py`, `test_attendance.py` export cases) stay green unmodified.

### `daily_log` layout
`Date | Day | Employee Name | Employee ID | Department | Shift | Work location | Status | Clock In | Clock Out | Worked Hours | Late By (min) | Early Exit (min) | [Overtime (min)] | Regularized | Pending request | Source`
* Status label = `_status_display_label` (same words as the register), half day → "Half day". Times `HH:MM:SS` in the work-location time zone, dates `dd-MMM-yy`.
* `Regularized` = `is_regularized` (Yes/blank), `Source` = Auto / Manual / Regularized / Import (`EmployeeAttendanceDetail.source`) — the point of this report is that an
  auditor can see which days were typed in or imported. Add the extra columns only for `daily_log`; the compat `/register/export` keeps its original header.
* Params = 275's plus `status` (the register's `_RegisterStatus` filter) and `sort` default `date desc, status, name` (range) / `status, name` (single day) — same as today.
* Audit action stays `AttendanceExported` with the same `new_value` keys (`date`, `from`, `to`, `filters`) plus `report`.

## Files
* `backend/app/modules/attendance_export/daily_log.py`; `backend/app/modules/attendance/router.py` (`export_register` delegates to the handler's builder);
  `backend/app/modules/attendance/dashboard_service.py` (delete the now-duplicated CSV assembly once delegating; keep `_CSV_HEADER` value-for-value in the compat path)
* extend `backend/app/tests/modules/test_attendance_export.py`

## Acceptance criteria
- [x] Golden test: for a seeded range, `/attendance/register/export` output is **byte-identical** to the pre-change output (capture it before refactoring)
- [x] `daily_log` returns one row per employee-day with the extra columns; `Source` shows Import for an imported day and Regularized for a regularized one
- [x] Single `date=` and `from/to` forms both work; filename unchanged
- [x] Scoping / limits / 401 / 403 / audit criteria of 275 hold; the audit row keeps its old keys
- [x] No second CSV writer left in `dashboard_service` (grep `csv.writer` in `app/modules/attendance`)
- [x] `uv run pytest app/tests/modules/test_attendance_export.py app/tests/modules/test_attendance_dashboard.py app/tests/modules/test_attendance.py` green

## Implementation notes
* One builder, `daily_log.register_table(..., extended=bool)`: `extended=False` is the register's original columns for `/attendance/register/export`.
  `dashboard_service.export_register_csv` and `_CSV_HEADER` are deleted; `register_pairs_for_export` holds the filter + sort.
* Golden files of the old output: `app/tests/golden/register_export_legacy.json` (four calls: range, single date, status filter, search); the endpoint matches them byte for byte.
* One intentional difference: the engine's formula-injection guard now also applies to this CSV, so a cell whose text starts with `=`, `+`, `@` (or `-` plus more) gets a leading `'`. No such value appears in normal data.
* The audit row keeps its old keys and gains `report` / `format` / `employee_ids`.

Completed: 2026-10-27
