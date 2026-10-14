---
task: 153
title: Attendance date-range filter — HR Manager Attendance page
status: done
depends_on: [152]
---

# 153 — HR Manager Attendance page uses a date range

> Part of requirement "4. Attendance Date Range Filters". Work in **`workspace-2/hrms/`**;
> paths are relative to it.

## Scope

`frontend/src/dashboards/hrManager/Attendance.tsx` holds a single `selectedDate`, drives
`getManagerAttendanceSummary` / `getManagerAttendanceExceptions` / `getManagerAttendanceRegister`
/ `exportAttendanceRegister` with it, and renders prev/next arrows + `DateField` + "Today"
(around lines 382-420). Replace that with a `DateRange`.

**This is the one implementation.** The HR Manager UI is the finalized design (user,
29-Sep-26), and HR Admin Insights will render this same component (task 154) rather than keep
its own copy. So build the range here only, and keep the component driven by props and
local state (no manager-only assumptions beyond the existing `navigate("regularizations")`,
which 154 makes optional).

**Not in this task:** mounting it in HR Admin Insights / deleting the Insights copy (154).

- **State:** `selectedDate` → `range: DateRange` (default `{today, today}`). Every place that
  sets the date also resets `page` to 1, as it does now.
- **Header control:** prev arrow · `DateRangeField` (`max` = today) · next arrow · "Today".
  Arrows call `shiftRange`; next is disabled when `range.to >= today`.
- **Period toggle / analytics band:** single day → unchanged (Day/Week/Month toggle drives the
  band). Multi-day → hide `PeriodToggle`; the band shows the range's numbers and its sub-labels
  use `formatRangeLabel(range)` instead of "today / this week / this month".
- **KPI tiles:** multi-day → sub-label "employee-days" (the counts are employee-day totals,
  task 151).
- **Register table:**
  - Multi-day → prepend a sortable **Date** column (dd-MMM-yy + weekday), before Employee. Keep
    the two `gridTemplateColumns` strings as named constants next to `SORTABLE_COLUMNS`, and
    have `TableSkeletonRows` use the **same** constant as the live table (shimmer rule: header
    row + same columns).
  - Entering range mode sets `sort = "date", direction = "desc"`; returning to a single day
    restores `status`/`asc`, but only if the user hadn't picked another sort.
  - Row React key → `` `${employee_master_id}-${attendance_date}` ``.
  - Empty state: "No attendance records for this date range" in range mode.
- **Exceptions chip row:** passes the range; counts read as employee-days in range mode.
- **Employee drawer:** anchored to the clicked row's `attendance_date`, not the page's date
  (check what `EmployeeDrawer` / `EmployeeAttendanceTab` currently receive and switch it).
- **Export:** passes the range; download filename matches the server's
  (`attendance-{from}.csv` / `attendance-{from}_to_{to}.csv`).
- Keep the existing split-loading behaviour: a period-only change shimmers only the analytics
  band, and a range change reloads everything.
- Spacing: follow the page's existing padding/gaps (it predates the 10px rule; don't re-space
  unrelated sections in this task).

## Files
- `frontend/src/dashboards/hrManager/Attendance.tsx`

## Acceptance criteria
- [ ] Default load (today) looks and behaves exactly as before: no Date column, Day/Week/Month
      toggle present, same requests sent.
- [ ] Choosing "Last 7 days" shows employee-day rows with a Date column, sorted newest first,
      paginated, and the KPI/band/exceptions all reflect the same 7 days.
- [ ] Prev/next shift a 7-day window by 7 days; next is disabled at today.
- [ ] Status/exception/department/shift/search filters and every sortable column work in range
      mode.
- [ ] Skeleton matches the live table's columns in both modes (no layout shift).
- [ ] Clicking a row opens the drawer for that row's date.
- [ ] CSV export of a range downloads one line per employee-day with the range filename.
- [ ] Verified in the browser as an HR Manager (direct reports only) and an HR Admin.
- [x] `npm run lint` / `npx tsc --noEmit` clean (no new problems).

## Progress (29-Sep-26)
- Implemented as scoped: range state + `changeRange` (enters a range → `sort=date desc` from the
  default sort; back to one day → resets a `date` sort), arrows via `shiftRange` (stepping
  forward clamps to a window ending today). For a multi-day range: `PeriodToggle` → range label,
  KPI caption "Counts are employee-days across …", band `sub`s use the range, Date column
  (`ATTENDANCE_RANGE_ROW_GRID`, `min-w-[1080px]`) shared by the header, rows and
  `TableSkeletonRows withDate`, row key `${employee_master_id}-${attendance_date}`, empty state and
  footer "employee-days", range export filename.
- Drawer: header shows the row's date. `EmployeeAttendanceTab` gained optional `anchorDate`: Week
  and Month centre on it, and a past Day reads that day's log row (`/today` only covers today).
  The employee profile page passes nothing, so it's unchanged.
- **Redesign (user feedback on the first version, 29-Sep-26):** the presets `<select>` + two date
  boxes + a separate Today button repeated themselves. `DateRangeField` is now one trigger
  ("Today · 29-Sep-26", "Last 7 days · 23-Sep-26 – 29-Sep-26", or just the dates when custom)
  opening a popover: the presets list applies on click; custom From/To (`DateField`s) with
  "Max 31 days" (amber when clamped) + Cancel/Apply; closes on outside click / Escape; stacks
  below 640px. The page's Today button was removed (Today is a preset).
- `npx tsc --noEmit` clean; eslint shows no new problems.

**Still open:** the browser checks (the unticked boxes above). This needs a dev-DB tenant with
attendance data and an HR Manager login. The dev servers for workspace-2 run on :8001 (API,
scheduler off) and :3001 (web).

Completed: 2026-09-29 — browser/manual checks verified by the user.
