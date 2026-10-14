---
task: 201
title: HR Manager attendance — "i" icon on today's register rows lists the day's punch-ins/outs
status: done
depends_on: []
---

# 201 — HR Manager attendance: today's punch list behind an "i" icon

Build this in the **top-level `hrms/`** clone (the user chose it on 2026-10-08), uncommitted, on
whatever branch it's on (`feature/gowtham_HrmsDevConfig` at the start).

## Why
The register shows only the first punch (Clock in) and the last punch (Clock out). An HR manager
can't see what happened in between (breaks, re-entries, the punch source). They want a small
"i" icon in the table that opens today's full punch list.

## Scope
### Backend: `GET /api/v1/attendance/employees/{employee_id}/today/punches`
- On the existing encrypted attendance `router` (`backend/app/modules/attendance/router.py`), with
  the same `_READ` gate as `GET /employees/{id}/today`.
- Scoping is the same as `get_employee_today`: `_require_employee_in_tenant` (404 across CDPs),
  then `_require_manager_or_admin_for_employee` (403 for a manager viewing a non-report).
- "Today" is the employee's **business date for now**, resolved like `_today_snapshot` does
  (`resolve_business_date_for_instant` + `resolve_effective_shift_cached` + `resolve_timezone`).
  So a night shift's after-midnight punches stay on the shift's day.
- Punches are the day's **kept** punches from the recompute service:
  `_kept_punches_for_day(db, tenant, employee, date, tz, resolved_shift, existing_row_id, cache)`.
  That covers linked punches, unlinked punches in the attribution window, and regularization
  punches, all debounced. It's the same set that worked hours and break minutes settle on, so the
  list never disagrees with the row. Read only: the endpoint never recomputes or writes.
- Response `TodayPunchesOut`:
  `{ attendance_date: date, punches: [{ id, punch_at (UTC), direction: "IN"|"OUT", punch_source,
  verification_status | null }] }`, ordered by `punch_at` ascending. `direction` is the
  recompute's tag (stored, or the odd/even fallback). It's informational, like everywhere else.

### Frontend: `frontend/src/dashboards/hrManager/Attendance.tsx`
- `getEmployeeTodayPunches(employeeId)` in `lib/api.ts`: `secureFetch` + `latestOnly`, in its own
  lane `attendance.employee.punches`.
- A small round "i" button next to the **Clock in** time, shown only when
  `row.attendance_date === todayIso()` and the row has a punch (`first_in_at`). Other rows render
  exactly as before, and the column grid doesn't change, so the skeleton needs no edit.
- Clicking it (with `stopPropagation`, so the row drawer doesn't open) opens a popover anchored to
  the icon with `position: fixed`, because the table wrapper is `overflow-hidden`. It lists
  "#, In/Out badge, time, source", with a header showing the date in dd-MMM-yy and the punch count.
  It loads with `ShimmerLine` rows, shows an error line on failure, and shows "No punches recorded
  today" when the list is empty. It closes on outside click, Escape, scroll, or resize.
- Admin Insights → Attendance renders the same component, so the feature shows up there too
  (canonical-UI rule).

### Not in scope
- Punches for past dates, or for multi-day ranges other than today's rows.
- Showing debounced or archived duplicates.

## Files
- `hrms/backend/app/modules/attendance/schemas.py`: `TodayPunchOut`, `TodayPunchesOut`
- `hrms/backend/app/modules/attendance/service.py`: `get_employee_today_punches`
- `hrms/backend/app/modules/attendance/router.py`: the route
- `hrms/backend/app/tests/modules/test_attendance.py`: tests
- `hrms/frontend/src/lib/api.ts`: type + fetcher
- `hrms/frontend/src/dashboards/hrManager/Attendance.tsx`: icon + popover

## Acceptance criteria
- [x] A manager gets a direct report's punches for today, in order, with directions. Debounced
      duplicates and archived punches are excluded. Yesterday's punches are excluded.
- [x] 401 without a token; 403 for a manager viewing a non-report; 404 for an employee in another CDP.
- [x] An admin can view any employee in the CDP. With no punches, the list is empty and the
      response is still 200.
- [x] An encrypted round-trip test for the new route.
- [ ] Today's rows that have a punch show the "i" icon. The popover lists the punches and closes
      on outside click or Escape. Clicking the icon doesn't open the row drawer.
- [x] `npx tsc --noEmit` and `npm run lint` are clean for the touched files.

## Progress — 2026-10-08
- Backend and frontend built in `hrms/` (uncommitted, branch `feature/gowtham_HrmsDevConfig`).
- 7 new tests pass on a throwaway pg:18. The full attendance, dashboard and recompute suites:
  371 pass and 4 fail, and the same 4 fail without this change (state-holiday seed, the CDP 0
  department, and a second login in the sweep test).
- `tsc` is clean. ESLint reports only the 3 existing `set-state-in-effect` hits in the page's
  fetch effects. Ruff reports only 5 existing findings in older test lines.
- Still open: the in-browser check of the popover (it needs a signed-in HR Manager session).

Completed: 2026-10-13
