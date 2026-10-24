---
task: 239
title: Shift Scheduling: Employee Directory filters on the roster
status: done
depends_on: []
---

# 239 — Shift Scheduling: Employee Directory filters on the roster

## Scope
Give the HR Manager Shift Scheduling grid the Employee Directory's filters: search, Department,
HR status, Reporting manager, Joining-date range (+ the existing Role dropdown, client-side).
Filtering is server-side via new query params on `GET /api/v1/shifts/employee-shifts/roster`
(`search`, `employment_status`, `reporting_manager_id`, `joining_date_from`, `joining_date_to`,
and `department` now matches `department_masters` like the directory). The directory's predicate
logic was extracted to `employees/service.py:apply_directory_filters` and is shared; the
directory's Filters drawer was extracted to `shared/EmployeeFilterDrawer.tsx`.
NOT in scope: the directory's Status dropdown (Inactive/Disabled — nothing to schedule).

## Files
- `hrms/backend/app/modules/employees/service.py` (`apply_directory_filters`)
- `hrms/backend/app/modules/shifts/{router,service}.py` (`list_shift_roster`)
- `hrms/backend/app/tests/modules/test_shifts.py` (2 new roster tests)
- `hrms/frontend/src/dashboards/shared/EmployeeFilterDrawer.tsx` (new), `EmployeeDirectory.tsx`
- `hrms/frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, `hrms/frontend/src/lib/api.ts`

## Acceptance criteria
- [x] Search + Filters drawer + chips + Role dropdown on Shift Scheduling
- [x] Shared filter predicate + shared drawer (no duplicated logic)
- [x] `tsc --noEmit` clean; ESLint clean on new/changed shift files; ruff unchanged
- [x] `uv run pytest app/tests/modules/test_shifts.py -k roster` green (9 passed, 24-Oct-26, local postgres:18 on :5433)
- [x] `test_employees.py`, `test_employee_import.py`, `test_employee_uan.py` green (drawer smoke still pending with the browser smoke below)
- [x] Manual smoke of Shift Scheduling in a browser

## Browser smoke (2026-10-24)
Headless Chrome (playwright-core) against a local stack — API :8001 on a fresh local postgres:18 migrated + `seed_dev.py` + RBAC defaults for the 'beta' tenant, Next copy on :3001 with `NEXT_PUBLIC_API_URL` overridden (the shared remote backend was never touched). Logged in as the seeded HR Manager.
- Search 'meera' → 1; Role=Engineer → 2; Department=Engineering → 2 (+ chip); Reporting manager → 4; Joining-from 01-Jan-26 → 2; drawer Reset → 7.
- Employee Directory: the shared Filters drawer opens with the same fields and Department=Engineering narrows the list (Meera, Kabir; not Priya).
- Not exercised in the browser: the HR-status select beyond opening it (every seeded employee is Active).
