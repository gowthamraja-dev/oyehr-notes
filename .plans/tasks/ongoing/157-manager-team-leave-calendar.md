---
task: 157
title: HR Manager team leave calendar
status: ongoing
depends_on: [148]
---

# 157 — HR Manager team leave calendar

Follow-up recorded by 148: its scope said "reuse the existing team-leave view if there is one; if
not, record a follow-up task instead of building it here". There is none today — the manager
portal only has the "On leave today" widget on `dashboards/hrManager/Leave.tsx` and the Holiday
Master tab (`hrManager/LeaveSection.tsx` → `HolidayCalendarAdmin`).

## Scope
Role: **HR Manager** (`hr_manager`), a "Team calendar" view in the manager's Leave area
(`hrManager/LeaveSection.tsx` tab strip, next to Requests / Holiday Master).
- Month grid (and a list fallback below 1000px) of the manager's **direct reports'** leave —
  Approved and Pending, Pending visually distinct — plus the tenant's holidays and week-offs.
- Click a leave block → the existing `RequestDetailModal` (approve/reject stays there).
- Data: prefer the existing `GET /leave/requests` (manager-scoped to direct reports, `from`/`to`
  filters) over a new endpoint; only add a backend route if per-day expansion (half days, holidays)
  can't be done from it. If one is added: gated `READ LEAVE`, manager = direct reports only,
  admin = whole CDP, tests incl. cross-tenant.
- Not in scope: org-wide calendar for HR Admin, iCal export.

Shimmer skeleton (grid structure), 10px page spacing, dd-MMM-yy dates, Tailwind only,
`hrms-responsive-side-panel` rules if it gets a side rail.

## Files
- `hrms/frontend/src/dashboards/hrManager/LeaveSection.tsx` (new tab)
- `hrms/frontend/src/dashboards/hrManager/TeamLeaveCalendar.tsx` (new)
- `hrms/frontend/src/lib/api.ts` (only if a new endpoint is needed)

## Acceptance criteria
- [ ] A manager sees only their direct reports' approved/pending leave for the month, with holidays.
- [ ] Clicking a leave opens the request detail; approving it there updates the calendar.
- [ ] Narrow viewport readable; `tsc`/lint clean.
