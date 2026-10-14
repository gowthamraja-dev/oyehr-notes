---
task: 190
title: Shifts, roles, leave, payslip, visitors — department via department_master_id
status: ongoing
depends_on: [187, 188]
---

# 190 — Remaining readers: shifts, roles, leave, payslip PDF, visitors

Work in **`workspace-2/hrms/`**. Part of the "drop `employee_masters.department`" series (187–192).
These modules read the legacy free-text column the same way attendance did (task 188). Apply the
same pattern here: filter on `department_master_id`, show `department_masters.department_name`
resolved in a batch, and send ids from the frontend.

## Current readers
Filters (name strings, which become `department_master_id`):
- `backend/app/modules/shifts/service.py` ~L989: `EmployeeMaster.department == department` (roster).
  **Existing frontend bug:** `lib/api.ts:listShiftRoster` (~L2176–2182) sends
  `filters.departmentId` as the `department` param. Check the caller in
  `dashboards/hrAdmin/AttendanceShifts_components/`, whose `utils/types.ts:13` has `department: string`,
  and fix it end to end.
- `backend/app/modules/roles/service.py` ~L649 filter and ~L658 `EmployeeMaster.department.ilike(term)`
  search (role-assignment candidate picker). `roles/admin_router.py` L72 passes it through.
  Frontend `lib/api.ts` ~L4623–4628.

Display only (the response field stays `department: str | None` = name; add
`department_master_id` where the frontend could use it):
- `shifts/service.py` ~L802, ~L1014
- `roles/service.py` ~L415, ~L687
- `leave/service.py` ~L1861
- `services/payslip_pdf_service.py` ~L61 (the payslip PDF's Department line)
- `visitors/service.py` ~L124 (`HostBrief`)
- `payroll/service.py` ~L1398/1782/1802 already pass `department=None`. Fill these from the FK if cheap.
  Otherwise leave them, because this is not a column reference.

## Scope
For each module: no `EmployeeMaster.department` / `<emp>.department` reads remain. Names come from a
single batched `{department_master_id: name}` lookup (or a join) per request, never one query per row.
Filters take an id and stay CDP-scoped (own CDP or CDP-0 department ids only). Update the matching
frontend callers to send ids.

Out of scope: attendance (188), employees (189), writers (191), the column drop (192).

## Files
- `backend/app/modules/{shifts,roles,leave,visitors}/…`, `backend/app/services/payslip_pdf_service.py`
- Tests: `test_shifts.py`, `test_roles.py`, `test_authz.py`, `test_visitors.py`, leave/payslip tests
  that assert `department`
- `frontend/src/lib/api.ts` and the shift-roster / role-assignment UIs

## Acceptance criteria
- [ ] `grep -rn "\.department\b" backend/app/modules/{shifts,roles,leave,visitors} backend/app/services`
      shows no `EmployeeMaster.department` reads (`department_master`/`department_name` are fine).
- [ ] Shift roster and role-candidate filters work by id, with a cross-CDP isolation test for each.
- [ ] The shift-roster `departmentId` → `department` param bug is fixed and verified in the browser.
- [ ] Payslip PDF, leave detail and visitor host show the FK department name.
- [ ] Affected test files green. Frontend type-check clean.
