---
task: 182
title: latestOnly for the employee list + employee search typeaheads
status: ongoing
depends_on: [181]
---

# 182 — latestOnly for the employee list + employee search typeaheads

## Scope
Same mechanism as task 184. Cancellation is configured in `src/lib/api.ts` with
`latestOnly(fn, { lane })` (`src/lib/latestRequest.ts`), never in components.

`getEmployees` can't take a single lane: the directory list and the employee typeaheads in
modals opened over it (AssignStructure, Payouts) would cancel each other, and the list would
hang on its skeleton. So split it by purpose, in `api.ts`:
- `getEmployees` (directory list): lane `employees.list`. Caller
  `shared/EmployeeDirectory.tsx:fetchList`, which has no guard today (the real race).
- `searchEmployees(query, pageSize = 25)` (new, typeaheads): lane `employees.search`. Point
  these callers at it: `shared/AssignStructureModal.tsx`, `shared/PayoutsTab.tsx`,
  `hrManager/Payroll.tsx`, `hrManager/VisitorManagement.tsx`, `hrAdmin/WorkflowBuilder.tsx`.
  Their existing `cancelled` flags can stay (harmless) or go.
- Leave one-shot loads (`EditEmployeeModal.tsx`, `hrAdmin/index.tsx`) on an **unwrapped**
  helper (e.g. `getEmployeesOnce`, or keep calling the raw function), because nothing
  supersedes them and they may run alongside the list.

Before wrapping, grep every caller of each helper and confirm that no two mounted components
use the same lane at once.

## Files
- `hrms/frontend/src/lib/api.ts`
- The typeahead components above (import swap only)

## Acceptance criteria
- [ ] Employee Directory: typing quickly in search / flipping filters shows earlier requests as `(canceled)` in the Network tab, and the table always matches the last input (check with "Slow 3G").
- [ ] No error toast or "failed to load" state appears for a cancelled request, and the directory never hangs on its skeleton when a typeahead modal is open over it.
- [ ] Each typeahead cancels the previous search when the query changes.
- [ ] No mutation helper is wrapped in `latestOnly`.
- [ ] `npm run lint` and `npx tsc --noEmit` clean.
