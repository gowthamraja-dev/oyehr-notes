---
task: 188
title: Attendance module — filter and display department via department_master_id
status: ongoing
depends_on: [187]
---

# 188 — Attendance module: department via `department_master_id`

Work in **`workspace-2/hrms/`**. Part of the "drop `employee_masters.department`" series (187–192).
After this task the attendance module must not reference `EmployeeMaster.department` anywhere.

## Current state (every place attendance uses the free-text column)
Backend, `backend/app/modules/attendance/`:
- `dashboard_service.py:_scoped_employees` (~L263) filters with `EmployeeMaster.department == department`
  (a name string). Every manager endpoint goes through it: `get_manager_analytics` (single date and
  `_manager_analytics_for_range`), `_build_scoped_rows_for_range`, the register, the exceptions
  (+ summary) and `export_register_csv`.
- `dashboard_service.py:_register_row_out` (~L718): `department=emp.department` → `RegisterRowOut.department`.
- `dashboard_service.py` CSV export (~L1058): `row.department` goes into the "Department" column
  (header list at ~L1016).
- `service.py` (~L1636, regularization inbox `EmployeeBrief`): `department=target.department`.
- `router.py` L440/452/468/491: `department: str | None` query param on `/manager/analytics`,
  `/manager/register`, `/manager/exceptions`, `/manager/register/export`.
- Log lines print `department=%s`. Switch them to `department_master_id=%s`.
- `schemas.py`: `EmployeeBrief.department` (L344) and `RegisterRowOut.department` (L430).

Frontend:
- `frontend/src/lib/api.ts` ~L2568–2651: `department?: string` → `qs.set("department", …)` for
  analytics, register, exceptions and export. Also `department: string | null` on the register row
  and brief types (~L2442, ~L2517).
- `frontend/src/dashboards/hrManager/Attendance.tsx`: `department` state is a **name** string. The
  chip label is that name (L435–440).
- `frontend/src/dashboards/hrManager/AttendanceFilterBar.tsx`: the radio options are
  `departments.map(d => ({ value: d.name, label: d.name }))` (L212). **Saved views**
  (`useSavedViews`, localStorage, per user) persist `department` as a name.
- Options come from `GET /employees/departments` (`employees/service.py:list_departments`), which
  returns `DepartmentOption{name, employee_count}` with **no id**.

## Scope
Backend:
1. Replace the `department: str | None` query param with `department_master_id: int | None` on all
   four manager endpoints. `_scoped_employees` filters `EmployeeMaster.department_master_id == id`.
   Treat a `department_master_id` that isn't the caller's own CDP or CDP-0 as no match. Return empty
   results, not 403, matching how the filter behaves today. Primary department only: this is the
   agreed rule. It deliberately ignores additional `employee_department_mappings` rows.
2. Display name: the department column in the register row, `EmployeeBrief` and the CSV comes from
   `department_masters.department_name` via `department_master_id`. Batch it: one
   `{id: name}` lookup per request for the scoped employees, **no per-row query**. Keep the response
   field `department: str | None` (the name), so the UI stays the same, and add
   `department_master_id: int | None` next to it.
3. ~~`DepartmentOption` gains `id`~~ **Changed while building (2026-10-07):** the filter's options
   come from the existing `GET /employees/department-options` (`DepartmentIdOption{id, name}`, own
   CDP + CDP-0, no legacy branch; frontend `getDepartmentIdOptions`). It already carries ids and
   also covers CDP-0 departments, which `/employees/departments` leaves out. `DepartmentOption` is
   untouched. Task 189 owns that endpoint.
4. Swap logging placeholders to `department_master_id`.

Frontend:
5. The filter state becomes `departmentId: number | null`. Radio value = `d.id`, label = `d.name`.
   The chip label is looked up from the loaded options. `api.ts` sends `department_master_id`.
6. Saved views: store `departmentId`. A legacy view that still has a `department` name string is
   resolved to an id against the loaded options when it is applied. If no option matches, drop it.
   Never send a name to the backend.

Out of scope: every other module's department use (189, 190), writers (191), dropping the column (192).

## Files
- `backend/app/modules/attendance/{router,dashboard_service,service,schemas}.py`
- `backend/app/modules/employees/{service,schemas}.py` (only the `DepartmentOption.id` addition)
- `backend/app/tests/modules/test_attendance_dashboard.py`, plus regularization-inbox tests if
  `EmployeeBrief.department` is asserted there
- `frontend/src/lib/api.ts`, `frontend/src/dashboards/hrManager/{Attendance,AttendanceFilterBar}.tsx`
- `docs/leave-and-attendance/…` (the api-and-pages doc that lists the manager endpoints' params)

## Acceptance criteria
- [ ] `grep -n "\.department\b" backend/app/modules/attendance/` returns nothing (excluding `department_master`).
- [ ] Analytics, register, exceptions and CSV export filter by `department_master_id`. Tests cover:
      a match, no match, a department from **another CDP's** id (no leak, empty), and a CDP-0 department.
- [ ] Register row, CSV "Department" column and regularization `EmployeeBrief` show the
      `department_masters` name, including for an employee whose legacy text differs from the FK's
      name (FK wins).
- [ ] No N+1: department names are resolved in one query per request.
- [ ] The department filter options come from `/employees/department-options` (ids, own CDP + CDP-0).
- [ ] HR Manager attendance page: the department filter, chip, saved view (new and legacy-name) and
      CSV export all work in the browser.
- [ ] `uv run pytest app/tests/modules/test_attendance_dashboard.py` green. `npm run build` (or
      `tsc --noEmit`) clean.
