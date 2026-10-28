---
task: 276
title: Hours ledger report (worked hours per employee per date)
status: done
depends_on: [275]
---

# 276 — Hours ledger report

## Scope
Report type `hours_ledger`: same grid shape as the attendance ledger (employee rows × date columns) but each cell carries **time**, for
timesheet and overtime review. Built on 275's `data.py` pivot and `AttendanceReportParams`; registered in the same attendance export router.
Not the status ledger (275), not the summary (277).

### Layout
```
Emp ID | Name | Department | Shift | 01 | 02 | … | 31 | Days worked | Total hours | Avg hours/day | Late (min) | Early exit (min) | Overtime (min)
```
* Cell = worked time as `H:MM` (e.g. `8:45`) for days with worked minutes > 0; for a non-working day the status code from 275's table
  (`WO`, `H`, `L`, `A`, `NS`) so the grid still reads as a calendar; blank = not employed. No numeric-only cells in the day columns — XLSX
  and CSV both get text, but the totals columns are real numbers (hours as a decimal, 2 dp) so HR can sum/filter.
* Optional param `cell=hours|in_out` (default `hours`). `in_out` renders `09:02-18:10` (local to the work-location time zone, 24h) so the sheet doubles as a punch view;
  a day with an In but no Out renders `09:02-?` (missing punch is exactly what HR looks for).
* Totals come from the same rows: Days worked = days with worked minutes > 0; Total hours = Σ worked_minutes / 60; Avg = total / days worked (blank when 0);
  Late / Early exit / Overtime = Σ minutes. **Overtime column only when the CDP has an active overtime policy** — the same
  `overtime.sync.effective_policies` test `export_register_csv` uses, so unchanged orgs see no new column.
* Legend as in 275 plus "`H:MM` = worked hours, `?` = no clock-out".
* Audit row like 275 with `report: "hours_ledger"`.

## Files
* `backend/app/modules/attendance_export/hours_ledger.py`; `_LAZY`/router registration; extend `test_attendance_export.py`

## Acceptance criteria
- [x] A seeded employee with a full day, a half day, a missing punch, a week-off and a leave day renders `8:45`, the right half-day time, `09:02-?`, `WO`, `L`
- [x] `cell=in_out` and `cell=hours` give the same totals; times are in the employee's work-location time zone (a test with a non-UTC zone)
- [x] Total hours = Σ cells; Avg handles zero days worked without dividing by zero
- [x] Overtime column appears only with an active overtime policy
- [x] All the scoping / limits / 401 / 403 / audit criteria of 275 hold for this type (parametrise the shared tests over both report types)
- [x] `uv run pytest app/tests/modules/test_attendance_export.py` green

## Implementation notes
* Param `cell=hours|in_out` is validated by the pydantic model (anything else is a 422). The dialog shows it automatically (it is an `enum` in the params schema).

Completed: 2026-10-27
