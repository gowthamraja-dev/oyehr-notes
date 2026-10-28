---
task: 286
title: Attendance grid endpoint (employee x day cells)
status: done
depends_on: []
---

# 286 — Attendance grid endpoint (employee x day cells)

## Scope
`GET /api/v1/attendance/grid` — the data behind the HR Manager "Regularization" tab (tasks 290-292): one row per employee, one cell per date, so HR sees the
same attendance as the register in a roster-style view. Read-only. NOT the selection UI (290/291) and NOT the apply paths (287/288).

Query: `from_date`, `to_date` (span <= 31 days), `department_master_id?`, `shift_id?`, `search?`, `page`, `page_size` (default 50, max 100). Paged by EMPLOYEE.
Gate: `ATTENDANCE` READ (same as the register), scoped by `principal.tenant_id` and the caller's own scope exactly like `dashboard_service.employee_days_for_range`.

Reuse, do not re-implement: `dashboard_service.employee_days_for_range` + `attendance_export.data.build_lines` / `day_cell` (same status rules and codes as the register and the
ledger export). Plain `APIRouter` or the attendance router's existing encryption class — follow what `/attendance/register` uses.

Response: `{ employees: [{ employee_id, emp_id, name, department, shift_name, joining_date, relieving_date, cells: [Cell] }], total, page, page_size }`
where `Cell = { date, code, effective_status, is_half_day, is_late, is_wfh, has_pending_regularization, is_regularized, is_locked, first_in_at, last_out_at, day_type, actionable: { regularize: bool, leave: bool, reason: str|null } }`.
`actionable` is a HINT for dimming cells (future date, before joining / after relieving, payroll-closed period, pending request -> regularize false; leave stays true for future days).
The preview/apply endpoints remain authoritative.

## Files
`backend/app/modules/attendance/router.py`, `schemas.py`, `dashboard_service.py` (or a new `grid.py` beside `regularize_range.py`), `backend/app/tests/modules/test_attendance_grid.py`.

## Acceptance criteria
- [ ] Cell codes/status for a day match `/attendance/register` for the same employee-day (test compares them)
- [ ] Paging is by employee; `total` is the employee count; filters (department, shift, search) apply
- [ ] Never leaks across tenants; a caller without READ gets 403; a manager with team scope sees only their scope
- [ ] `actionable.regularize` is false for future / pre-joining / post-relieving / payroll-closed / pending days, `leave` true for future days
- [ ] Span over 31 days or `to < from` -> 422

## As built (2026-10-28)
`GET /attendance/grid` in `attendance/grid.py` (+ `GridCell` / `GridEmployee` / `AttendanceGridOut` in `schemas.py`, route in `router.py`). Query is `date` or `from`+`to` (the register's `_DateRange`, <= 31 days), `page`, `page_size` (default 50, max 100). `is_wfh` = the day sits on the tenant's remote work location (there is no stored WFH status). 10 tests in `test_attendance_grid.py`.

Completed: 2026-10-28
