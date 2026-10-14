---
task: 183
title: Sweep remaining screens — wrap their re-fetching GET helpers in latestOnly
status: ongoing
depends_on: [182]
---

# 183 — Sweep remaining screens — wrap their re-fetching GET helpers in latestOnly

## Scope
These screens guard against stale responses with a hand-rolled
`let cancelled = false … return () => { cancelled = true }` flag. That hides the stale result
but doesn't stop the request. For each screen whose effect re-fetches a GET on changing input
(filters, date range, selected id, tab), wrap the helper it calls in
`latestOnly(fn, { lane })` in `src/lib/api.ts` (see tasks 184/182). Don't add cancellation
code to the component. Grep each helper's callers first: if another mounted screen uses it at
the same time, give it a separate helper/lane. Ignore flags unrelated to staleness (timers,
WebSocket/NOTIFY listeners, polling loops).

Candidates (from `grep -rln "let cancelled\|let ignore\|let active = true" src`, minus the
files task 182 owns):
- Employee: `EmployeeHome`, `EmployeeProfile`, `HolidayCalendar`, `MyLeave`, `MyPayslips`,
  `MyReimbursements`, `RegularizationModal`
- HR Admin: `index.tsx`, `HrAttributes`, `PayrollConfiguration`, `PayrollRequestsTab`,
  `AttendanceShifts_components/{hooks/useShifts,components/ShiftDefaults}`,
  `PayrollConfiguration_components/hooks/usePayrollConfig`,
  `WorkLocations_components/{hooks/useWorkLocations,components/LocationFormModal,components/NetworkPanel}`
- HR Manager: `Leave`, `RegularizationInbox`, `ShiftScheduling`
- Shared: `EmployeeDetailDrawer`, `PayrollRecordDrawer`, `PayrollRequestCard`, `SubmissionHistoryAccordion`
- Super Admin: `AddOrganizationModal`, `OrganizationsList`, `SuperAdminHome`
- (The HR Manager Attendance page + its drawer are task 184.)
- Out of scope: `app/forms/*` (nhforms package calls), `contexts/knowledge-context.tsx`.

Split into a follow-up task if this grows past one reviewable PR (e.g. one PR per dashboard).

## Files
The components/hooks listed above, under `hrms/frontend/src/`.

## Acceptance criteria
- [ ] Each migrated screen: changing its input quickly shows superseded requests as `(canceled)` and renders only the latest data.
- [ ] No screen hangs on a skeleton because another screen's call in the same lane superseded it.
- [ ] `npm run lint` and `npx tsc --noEmit` clean.
