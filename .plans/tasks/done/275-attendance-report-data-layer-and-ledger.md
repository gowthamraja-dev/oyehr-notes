---
task: 275
title: Shared attendance report data layer + Attendance Ledger report
status: done
depends_on: [274]
---

# 275 — Shared attendance report data layer + Attendance Ledger report

## Scope
Two things, deliberately together because the ledger is the first consumer and proves the layer:

1. **`attendance_export/data.py` — the shared data layer** every attendance report (276–278) reads. It wraps what the register already
   computes so reports never re-derive status: `dashboard_service._build_scoped_rows_for_range(db, principal, from_, to, department_master_id, shift_id)`
   → `_register_row_out(scoped)` gives `effective_status`, `is_half_day`, `is_late`, `first_in_at`/`last_out_at`, `worked_minutes`,
   `late_by_minutes`, `overtime_minutes`, `has_pending_regularization`, `emp_id`, `name`, `department`, `shift_name`, and the work-location
   `time_zone`. **Reuse those (promote to a non-underscore public function in `dashboard_service` or import them as-is — do not copy logic).**
2. **Report `attendance_ledger`** — the basic one. Employees in rows, dates in columns.

### Shared params (`AttendanceReportParams`, used by 276–278 too)
`from` / `to` (dates, required, `to ≥ from`, ≤ 62 days, same validation as `attendance/router.py::_date_range`), `department_master_id?`,
`shift_id?`, `search?` (name / emp id), `employee_ids?` (optional explicit list, still intersected with the caller's scope), `format`.
No status filter (a ledger shows every status).

### Pivot helper
`pivot(rows, dates) -> (employees_in_order, {(employee_id, date): RegisterRowOut})`. Employee order: department, then name, then emp id.
A date the employee was not employed (before joining / after relieving — `is_employed_on` already excludes them from the rows) is a **blank
cell** — never "A". A date with no resolved shift renders `NS`.

### Ledger layout
```
Attendance Ledger · 01-Oct-26 to 31-Oct-26 · Department: All          (meta block, xlsx)
Emp ID | Name | Department | Shift | 01 | 02 | … | 31 | Present | Absent | Half | WO | H | L | Late | Payable days
                              (xlsx: merged band above the day columns "Oct-26", and a row of weekday letters M T W …)
```
* Day columns: header `01`…`31` for one month, `01-Oct` when the range crosses a month; XLSX adds the weekday-letter sub-row and the month band
  (`group_header`). CSV keeps a single header row with `dd-MMM` labels so it stays machine-readable.
* Cell codes: `P` present · `A` absent · `HD` half day · `WO` week off · `H` holiday · `L` on leave · `NS` no shift · `YTC` yet to check in
  (today/future working day) · blank = not employed. A late present day is still `P` (lateness is in the Late total — and in the hours ledger).
* Totals (computed from the same pivot, never re-queried): Present (P + 0.5×HD? — **no**: keep counts literal: Present = count of `P`,
  Half = count of `HD`), Absent, Week off, Holiday, Leave, Late (count of late days), **Payable days = Σ `payable_day_fraction`** of the
  employee-day rows (the attendance engine's own figure; check the field exists on `RegisterRowOut`, otherwise read it from
  `EmployeeAttendanceDetail.payable_day_fraction` via the scoped row — do not invent a formula).
* Legend (xlsx 2nd sheet / `ExportTable.legend`): every code above with its meaning.
* Pending regularisation days are **not** marked in the cell (that is the daily log's job, 278).
* Audit: `AttendanceAuditLog` row `action="AttendanceExported"`, `new_value={report: "attendance_ledger", from, to, filters, format, rows}` — same degradation
  as `export_register_csv` (skip when the caller has no `EmployeeMaster`).
* Registered under prefix `/api/v1/attendance-export`, `export_type="attendance_ledger"`, resource `ATTENDANCE`, READ.

Out of scope: other report types (276–278), the UI (279), docs (280).

## Files
* `backend/app/modules/attendance_export/__init__.py`, `data.py`, `params.py`, `ledger.py` (handler + `register`), `router.py`
* `backend/app/modules/file_export/handlers.py` (`_LAZY` entry), `backend/app/api/router.py` (mount)
* `backend/app/modules/attendance/dashboard_service.py` (only to expose the helpers; no behaviour change — existing `test_attendance_dashboard.py` stays green)
* `backend/app/tests/modules/test_attendance_export.py` (new; later tasks extend it)

## Acceptance criteria
- [x] `GET /api/v1/attendance-export/attendance_ledger?from=&to=&format=xlsx|csv` returns a file; CSV header = fixed columns + one per date + totals
- [x] A month with present / absent / half-day / week-off / holiday / leave / no-shift / not-yet-joined days yields the correct code in each cell (seeded test)
- [x] Employee who joined mid-range has blank cells before joining; relieved employee blank after
- [x] Totals equal the counts of the row's own cells; Payable days equals Σ the attendance engine's fraction
- [x] Reporting manager gets only their team; HR/Admin the whole CDP; **another tenant's employees never appear** (org-scoping test, as `test_attendance.py`)
- [x] `department_master_id`, `shift_id`, `search`, `employee_ids` narrow the rows; an `employee_ids` entry outside the caller's scope is silently dropped (not leaked, not 403)
- [x] Range > 62 days → 422; `to < from` → 422; > `MAX_CELLS` → 422
- [x] 401 without a token, 403 without ATTENDANCE READ
- [x] An audit row is written (and skipped without crashing for a caller with no employee row)
- [x] `test_attendance_dashboard.py` and `test_attendance.py` unchanged and green; `uv run pytest app/tests/modules/test_attendance_export.py` green

## Implementation notes
* Public helper `dashboard_service.employee_days_for_range` (+ `status_display_label`) wraps the register's own rows; no logic was copied.
* Params live in `attendance_export/params.py` (`date=` is accepted as from = to = date). Export cap is its own `MAX_EXPORT_DAYS = 62` (the register screen stays at 31).
* Payable days = Σ `payable_day_fraction` of the stored row; a day with no stored row counts 1 for WeekOff/Holiday, else 0 (the engine's rule, assembler.md §9).
* Filter labels in the XLSX meta block come from `DepartmentMaster` (CDP 0 or the caller's) and `ShiftMaster` (caller's tenant).

Completed: 2026-10-27
