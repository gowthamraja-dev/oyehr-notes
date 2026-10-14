---
task: 189
title: Employees directory, headcount and department options — drop the free-text fallback
status: ongoing
depends_on: [187, 188]
---

# 189 — Employees module: department only via `department_master_id`

Work in **`workspace-2/hrms/`**. Part of the "drop `employee_masters.department`" series (187–192).
The employees module is the biggest reader of the legacy column, because it was built to fall back to
the column for tenants that had not "migrated" to `department_masters`. Task 187's backfill removes
the need for that fallback.

## Current state (`backend/app/modules/employees/`)
- `service.py` ~L163, sort key: `func.coalesce(DepartmentMaster.department_name, EmployeeMaster.department)`.
- `service.py` ~L326, search: `EmployeeMaster.department.ilike(term)` next to `DepartmentMaster.department_name.ilike`.
- `service.py` ~L330–336, filter: `or_(EmployeeMaster.department == department, DepartmentMaster.department_name == department)` (a name).
- `service.py` ~L388, ~L446–447, ~L1026, ~L1066: display fallbacks `… or dept_name or e.department`.
- `service.py:_department_masters_for_tenant` + `list_departments` (~L1121–1180): the "has this
  tenant migrated" gate, plus a legacy branch that groups by `EmployeeMaster.department`.
- `service.py:get_headcount` (~L1290–1316): the same gate and legacy group-by for `by_department`.
- `service.py` ~L1371: `func.coalesce(DepartmentMaster.department_name, EmployeeMaster.department)`.
- `router.py` L73/82: `department` sort/filter query param (a name). L145: a docstring about the fallback.
- Frontend `lib/api.ts` ~L825–846 (`EmployeeSortBy`, `department?: string`), plus the directory
  sidebar and filter drawer that use `getEmployeeDepartments()` names.

## Scope
1. Filter param: `department_master_id: int | None` replaces the `department` name. Filter on the
   primary FK, CDP-scoped. *Decide while doing this:* the directory currently **displays** every
   active `employee_department_mappings` department. If the filter should also match additional
   departments, use `EXISTS` on active mappings. Otherwise filter the primary only (the same as
   attendance, task 188). Write down the choice in the PR and doc.
2. Search, sort and display use only `DepartmentMaster.department_name` (via the FK or mappings).
   Remove every `EmployeeMaster.department` reference and every `coalesce(…, EmployeeMaster.department)`.
3. `list_departments` / `get_headcount`: remove the "migrated?" gate and the legacy branch. Always
   return the tenant's departments (own CDP + CDP-0 that actually have employees, or own CDP only:
   keep today's semantics for which rows appear) with `id`, `name` and `employee_count`.
   `DepartmentOption.id` becomes non-null. `DepartmentHeadcountOut` gains `department_master_id`.
4. Frontend directory: the sidebar and filter drawer send `department_master_id`. Keep the URL
   state/back-compat the same way task 188 handles saved views.

Out of scope: other modules (190), writers / employee import (191), the column drop (192).

## Files
- `backend/app/modules/employees/{router,service,schemas}.py`
- `backend/app/tests/modules/test_employees.py`
- `frontend/src/lib/api.ts`, plus the employees directory page and filter components (find them via
  `getEmployeeDepartments` / `listEmployees` callers)

## Acceptance criteria
- [ ] `grep -n "EmployeeMaster.department\b\|e\.department\b\|emp\.department\b" backend/app/modules/employees/` returns nothing.
- [ ] Directory filter, search and sort by department work from the FK. Tests cover cross-CDP
      isolation (another tenant's department id → no rows) and an employee whose stale text differs
      from its FK name (FK wins in display, search and sort).
- [ ] `/employees/departments` and `/employees/headcount` give the same result for a tenant whose
      departments are all CDP-0 and for one with its own departments. There is no legacy branch.
- [ ] Directory page filters by department in the browser.
- [ ] `uv run pytest app/tests/modules/test_employees.py` green. Frontend type-check clean.
