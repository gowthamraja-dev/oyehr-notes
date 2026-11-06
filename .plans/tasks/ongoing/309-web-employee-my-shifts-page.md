---
task: 309
title: Web — Employee "My Shifts" page (calendar, assigned list, shift change requests)
status: ongoing
depends_on: [302, 303, 305]
---

# 309 — Web: Employee My Shifts page

## Scope
A new Employee-dashboard page, **My Shifts** (nav key `myShifts`, `resource: "ATTENDANCE"`, placed under My Attendance), mirroring the mobile mockup
(`.plans/my-shifts-mockup.jpeg`) on the APIs from tasks 302/303/305 (`.plans/my-shifts-mobile-api.md` has the contracts). Three tabs:
- **Calendar** — month grid (Mon first) from `GET /shifts/me/calendar?from&to`; dot per day (green shift assigned, blue week off, pink holiday), a small marker when a
  change request is Pending; month pager; selected-day card (shift + times, "Assigned" / "Week off" / holiday name, HR swap note, "Request change" for today-or-later working days).
- **My Shifts** — "Assigned Shifts" list for the month (today onwards in the current month), Week Off rows, holiday rows.
- **Requests** — status filter (All / Pending / Approved / Rejected / Cancelled), paged list (`GET /shifts/me/change-requests`), row → details modal
  (`GET .../{id}`) with Cancel (via `useConfirm`, `POST .../{id}/cancel`, only when `can_cancel`).
- **Request shift change** modal — `DateField` (min today), read-only Current Shift and a Requested Shift select from `GET /shifts/me/available?date=` (current one disabled),
  Reason textarea with 0/500 counter; submit → `POST /shifts/me/change-requests`; backend refusal sentences shown inline.
Not covered: approver side (task 308), the Home page's week strip / "Today's Shift" card, any mobile work.

## Rules
Tailwind only; dates `dd-MMM-yy` (`formatDDMMMYY`) and `DateField` for the date input; shimmer skeletons from `components/ui/Shimmer.tsx` (no hand-rolled `animate-pulse`);
`useConfirm()` not `window.confirm`; 10px page spacing (hrms-spacing); every API call through `secureFetch` (encrypted routes).

## Files
`frontend/src/lib/api.ts` (types + 6 functions), `frontend/src/dashboards/Employee/MyShifts.tsx` (new), `frontend/src/dashboards/Employee/index.tsx` (NAV, `views`, `CUSTOM_VIEWS`).

## Acceptance criteria
- [x] `tsc --noEmit` and eslint clean
- [ ] Page appears in the Employee nav and loads without a placeholder ("coming soon")
- [ ] Calendar shows dots/legend and a month pager; selecting a day shows its card; week-off / holiday / unassigned / outside-employment days render distinctly
- [ ] My Shifts tab lists the month's days; Requests tab filters by status and pages; details modal shows both shifts, reason, status, remarks
- [ ] Submitting a request refreshes the calendar marker and the Requests list; a backend refusal shows its sentence and keeps the modal open
- [ ] Cancel asks for confirmation and only appears for Pending requests
- [ ] Checked in a browser against a running app (needs the backend deployed with tasks 304-306)

## Progress (2026-10-29)
Built in `workspace-2/hrms/frontend`, NOT committed: `src/lib/api.ts` (types `MyShiftBrief`, `ShiftCalendar`, `MyAvailableShifts`, `MyShiftChangeRequest`, … and six functions), new `src/dashboards/Employee/MyShifts.tsx` (page, skeleton, three tabs, request form and details modals), and `src/dashboards/Employee/index.tsx` (nav item under My Attendance, `views`, `CUSTOM_VIEWS`). `tsc --noEmit` and eslint are clean. NOT run in a browser: no server was started, and the endpoints are not deployed to the shared dev API yet, so every other criterion above is UNVERIFIED. Known simplifications: the Home page's "This Week" strip and "Today's Shift" card are not part of this task; the pending marker is a small amber dot; the My Shifts tab lists the visible month only.

## Superseded (2026-11-02)
Page being broken up: Calendar -> Home calendar (task 321), Requests + request form -> My Attendance (task 320), standalone nav item/page removed (task 322). Do not build further on `MyShifts.tsx`.
