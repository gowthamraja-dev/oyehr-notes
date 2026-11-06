---
task: 321
title: Web — Home quick calendar shows the employee's shifts, week offs and swap markers
status: ongoing
depends_on: [302, 320]
---

# 321 — Web: Home calendar filled with shift data

## Scope
`QuickCalendarCard` in `EmployeeHome.tsx` (~line 217) today marks holidays only (`getMyHolidayCalendar`). Fill it with the month calendar that task 309's Calendar tab
showed, from `GET /shifts/me/calendar?from&to` (`getMyShiftCalendar`, `ShiftCalendar` / `ShiftCalendarDay` already in `lib/api.ts`):
- Per-day marker: green = shift assigned, blue = week off, pink = holiday (calendar response already carries the holiday name), small amber dot when a change request is Pending.
  Keep the card's compact sizing (`h-[22px]` cells) — the dot goes under the date number, the existing holiday tint stays.
- Fetch the shift calendar for the visible month alongside the holiday call (re-fetch on month change, cancel on unmount); on shift-calendar failure fall back to the current holiday-only rendering — never blank the card.
- Selecting a day shows a small detail strip under the grid (shift name + `fmtTimeOfDay` range / "Week off" / holiday name / HR swap note). For today-or-later working days it has a
  **Request change** button that opens `RequestFormModal` from task 320 (prefilled with that date), and refreshes the markers on success.
- Small legend row (3 dots + pending).
- "View full calendar" link stays pointing at `holidays`.
Reuse the day-kind logic (`kindOf`, `DOT_CLASS`, `dayTitle`, `monthBounds`) from `MyShifts.tsx` — move them into a shared module (`Employee/shiftCalendarUtils.ts`) rather than copying.

Not covered: the "This Week" strip / "Today's Shift" card (separate), the Home "My Shifts" assigned-list card (see open question in 322), mobile.

## Rules
Tailwind only; 10px spacing; the card's existing shimmer loading rows stay (grid skeleton must still match the real grid); dates `dd-MMM-yy` in any text.

## Files
`frontend/src/dashboards/Employee/EmployeeHome.tsx`, `frontend/src/dashboards/Employee/shiftCalendarUtils.ts` (new), `frontend/src/dashboards/Employee/ShiftChangeRequests.tsx` (import only).

## Acceptance criteria
- [x] `tsc --noEmit` clean; eslint adds nothing new (one pre-existing unused `parseIsoDateLocal` warning in EmployeeHome.tsx)
- [ ] Home calendar shows shift / week-off / holiday / pending markers for the visible month and a legend; month pager refetches
- [ ] Day click shows its detail; "Request change" only for today-or-later working days and opens the swap form prefilled
- [ ] Shift calendar failure still renders the holiday calendar
- [ ] Layout height still pairs correctly with Quick Actions (no shift)
- [ ] Checked in a browser against a running app

## Progress (2026-11-02)
Built in `workspace-2/hrms/frontend`, NOT committed: `QuickCalendarCard` in `EmployeeHome.tsx` now fetches `getMyShiftCalendar` for the visible month (keyed by month, so a month change never shows stale dots; failure -> holiday-only), draws a shift/week-off/holiday dot per day plus an amber pending dot, a 4-item legend, and a clickable-day detail strip with "Request change" (today-or-later, assigned shift, nothing pending) opening `RequestFormModal` from task 320 and refetching on submit.
New `Employee/shiftCalendarUtils.ts` holds the shared day-kind helpers; `MyShifts.tsx` now imports them. Grid cells grew 22px -> 26px (skeleton rows too) to fit the dot, so the card is slightly taller and the paired Quick Actions card stretches with it. The grid stays Sunday-first, as Home's was.
NOT run in a browser: all other criteria UNVERIFIED (incl. whether the taller card looks right beside Quick Actions).
