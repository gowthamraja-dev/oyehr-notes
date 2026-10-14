---
task: 168
title: HR Manager attendance — merge the duplicated tile rows, drop the Day/Week/Month toggle
status: ongoing
depends_on: []
---

# 168 — Attendance: one tile row, one date control

Work in **`workspace-2/hrms/`**. The branch at planning time was
`feature/gowtham_AttendanceDateRange` (head `98832e6`, task 167). Run
`git -C workspace-2/hrms status -sb` first. Task 166 edits the same file
(`hrManager/Attendance.tsx`, the Late-by cell around line 841). It touches a different region,
so either order works, but rebase carefully if both are in flight.

## Why
The HR Manager Attendance page (`frontend/src/dashboards/hrManager/Attendance.tsx`) shows the
same numbers in more than one place, and it has two time selectors:

1. **Two tile rows that repeat each other.** The KPI row (`KpiTile` ×6, ~line 559) and the
   "Attendance analytics" band (`MetricTile` ×5, ~line 621) read the same `summary` object:

   | KPI row                     | Analytics band                       | Same value?                         |
   |-----------------------------|--------------------------------------|-------------------------------------|
   | Late arrivals `late_count`  | Late logins `late_count`             | **Yes. Same field, shown twice.**   |
   | Attendance % `attendance_percentage` | Attendance % `attendance_percentage` | **Yes. Same field, shown twice.** |
   | Present / On leave / Absent / Yet to check in | n/a                | n/a                                 |
   | n/a                         | Timely logins, Avg logged hours, Punctuality % | Unique, but windowed by `period` |

   The two rows also use two different tile designs: an icon chip versus a dot label.

2. **A redundant Day/Week/Month toggle.** `PeriodToggle` (~line 612, `Period` state at line
   121) re-windows only the analytics band, through backend `_period_range` (ISO week or
   calendar month around the selected day). The header `DateRangeField` already offers the
   **Today / Yesterday / This week / Last 7 days / This month / Last month / Custom** presets
   (`lib/dateRange.ts:65`). A multi-day range already makes *every* number cover that window
   (task 151/153), and the toggle is already hidden in that case. With a single day selected,
   the result is mixed scopes on one screen: the KPI row shows "today" while the band below
   shows "this month". `periodLabel` and `snapshotLabel` (~line 332) exist only to explain
   that mismatch.

3. The status pills under the filter bar (All / Present / Late / On leave / Absent / Yet to
   check in …) list the same categories as the KPI tiles a third time. The tiles are not
   clickable, so the two don't connect.

## Decision
- **The header date range is the only time control.** Remove the Day/Week/Month toggle. To
  see the week, pick "This week". Every tile, the exceptions chips and the register then share
  one scope.
- **One tile row**, built from the KPI design (icon chip + value + label, `KpiTile`):
  `Present · Late · On leave · Absent · Yet to check in · Attendance % · Avg logged hours · Punctuality %`
  - "Late logins" and the second "Attendance %" are dropped. They were exact duplicates.
  - "Timely logins" folds into the Punctuality tile as a sub-line, e.g. `42 of 48 on time`.
    Use `timely_logins` and `late_count`.
  - Add an optional `sub?: string` to the page's `KpiTile` so Avg logged hours and
    Punctuality % can carry that one line. Keep it out of the other tiles so the row stays
    even.
- **Count tiles act as filters.** Clicking Present / Late / On leave / Absent / Yet to check in
  calls the existing `selectStatus(...)`. The tile that matches `activeStatusValue` gets an
  active ring (`border-teal-700` / `bg-teal-50`, the same as an active exception chip).
  Clicking the active tile again resets to `"all"`. The status pills **stay**: they also cover
  Half day / Week off / Holiday, which have no tile. Attendance %, Avg logged hours and
  Punctuality % aren't statuses, so they are not clickable.

## Scope
**In — frontend** (`frontend/src/dashboards/hrManager/Attendance.tsx`, `frontend/src/lib/api.ts`):
1. Delete the `Period` type, `PERIODS`, the `period` state, the `PeriodToggle` component, the
   `isFirstPeriodRender` effect and the `fetchSummary("analytics")` path. Remove the `period`
   param from `getManagerAttendanceSummary`, and remove the `period` field from the
   `AttendanceAnalytics` type, along with its comment.
2. Merge the two loading flags (`kpiLoading` / `analyticsLoading`) into one `summaryLoading`.
   The period-only change that justified the split no longer exists. Update the long comment
   above them (~line 134).
3. Replace the KPI row and the "Attendance analytics" heading + band with the single 8-tile
   row above. Keep the multi-day caption ("Counts are employee-days across …") above it. Delete
   `periodLabel` and `snapshotLabel`. A tile needs at most one scope hint, and for a range the
   caption already provides it.
4. Remove the page-local `MetricTile` (line ~969). If nothing else in the file uses it, drop the
   `ShimmerMetricTile` import too. Do **not** touch `dashboards/shared/MetricTile.tsx`, because
   `shared/EmployeeAttendanceTab.tsx` still uses it.
5. Skeleton: one row of 8 placeholders in the same grid, all using the KpiTile shape
   (`ShimmerRow avatarSize={42} avatarShape="square"`), as the KPI row already does. Take the
   count from the same tile-definition array that the real render maps over. Don't hardcode a
   second `8`. See CLAUDE.md "Loading states".
6. Clickable count tiles, as described in Decision. Render them as `<button type="button">`
   (keyboard-focusable), with `aria-pressed` set to the active state.

**In — backend** (user, 05-Oct-26: the HR Manager screens are not yet integrated anywhere
else, and the mobile app doesn't call `/attendance/analytics`, so the param can go):
7. `backend/app/modules/attendance/router.py` `get_manager_analytics`: drop the
   `period: _Period = "day"` query param and pass nothing for it. Update the docstring.
   `_Period` stays, because `/me/analytics` and `/employees/{id}/analytics` still use it.
8. `backend/app/modules/attendance/dashboard_service.py` `get_manager_analytics`: drop the
   `period` arg. For a single date, the band (logged hours / timely / punctuality) covers that
   date only, so remove the `_period_range(period, date_)` call and query `attendance_date ==
   date_`. `_period_range` stays, because the employee analytics still use it. Drop
   `period=` from the INFO log line and from both `AnalyticsOut(...)` constructions.
9. `backend/app/modules/attendance/schemas.py` `AnalyticsOut`: remove the `period` field. Fix
   the comments on `from_`/`to`: they are now the window the whole response covers (`from ==
   to == date` for one day). `EmployeeAnalyticsOut` is untouched.
10. Tests in `backend/app/tests/modules/test_attendance_dashboard.py`:
    - `:1561` `test_analytics_range_counts_employee_days`: drop `period="week"` from the
      params and the `body["period"] == "range"` assertion.
    - `:1582` `test_analytics_single_date_reports_its_band_window`: rewrite it as
      `test_analytics_single_date_band_covers_that_day`. Seed one row on `d` and one on
      `d - 1 day`. Assert that `from == to == d`, that `"period" not in body`, and that only
      `d`'s worked minutes count toward `total_logged_minutes`. Passing a stray `?period=week`
      must not change the result, because unknown query params are ignored.
11. Docs in `docs/leave-and-attendance/attendance/`:
    - `api-and-pages.md`: the page row (:85, "Day/Week/Month analytics band"), the two
      `/analytics` endpoint rows (:146, :174), and §4.5's heading, prose and JSON example.
      The heading anchor is linked from `gaps.md:186`, so update that link too.
    - `manager-approvals.md`: §1.1 ("regardless of the analytics-band period selector") and
      §1.2 now describe one 8-tile row scoped by the date range, with no period control.
    - `gaps.md:186-190`: the "Week/Month band" wording.

**Out:**
- **Employee-scoped analytics.** `/me/analytics` (`get_my_analytics`) and
  `/employees/{id}/analytics` (`get_employee_analytics`, the employee drawer's Day/Week/Month
  log) keep their `period` param. The mobile app and the drawer use them.
- **Exceptions chips.** "Late arrivals · N" is close to the Late tile, but exceptions are an
  *actionable* list (it switches the table to the exceptions source). It is a different
  concept, so leave it. If the user still finds it repetitive after this ships, file a
  follow-up.
- **Employee-side attendance screens** (`Employee/MyAttendance.tsx`,
  `shared/EmployeeAttendanceTab.tsx`). Those have their own period toggle, and it is a different
  screen.
- **Other HR Manager pages** (Leave, Visitor Management) each have one tile row and no
  duplicates. They are not in scope.

## Files
- `workspace-2/hrms/frontend/src/dashboards/hrManager/Attendance.tsx`
- `workspace-2/hrms/frontend/src/lib/api.ts` (`AttendanceAnalytics`, `getManagerAttendanceSummary`)
- `workspace-2/hrms/backend/app/modules/attendance/{router,dashboard_service,schemas}.py`
- `workspace-2/hrms/backend/app/tests/modules/test_attendance_dashboard.py`
- `workspace-2/hrms/docs/leave-and-attendance/attendance/{api-and-pages,manager-approvals,gaps}.md`

The page is shared: HR Admin → Insights → Attendance mounts the same component with
`embedded` (task 154), so this change covers both screens.

## Acceptance criteria
- [ ] Neither page has a Day/Week/Month toggle. `grep -n "PeriodToggle\|PERIODS\|setPeriod"
      frontend/src/dashboards/hrManager/Attendance.tsx` returns nothing.
- [ ] Exactly one tile row: Present, Late, On leave, Absent, Yet to check in, Attendance %,
      Avg logged hours, Punctuality % (with the "N of M on time" sub-line). No label or value
      appears twice. The "Attendance analytics" heading is gone.
- [ ] Today: every tile reflects today. "This week" or "This month" preset: every tile and the
      register reflect that window, and the employee-days caption shows.
- [ ] Clicking the Late tile sets the status filter to Late. The tile and the "Late" pill both
      show active, and a filter chip appears. Clicking it again resets to All. Present / On
      leave / Absent / Yet to check in behave the same way.
- [ ] A changed date, department or shift shimmers the whole tile row once, with 8 placeholders
      in the same shape and grid. The page makes one `/attendance/analytics` request per
      change, with no duplicate fetch on mount (check the Network tab).
- [ ] The error state still shows the single "Couldn't load the attendance summary" banner with
      Retry.
- [ ] `GET /attendance/analytics` has no `period` param and returns no `period` field. A
      single date's band covers only that date. `/me/analytics` and
      `/employees/{id}/analytics` still accept `period`.
- [ ] `uv run pytest app/tests/modules/test_attendance_dashboard.py` is green.
- [ ] `npx tsc --noEmit` and `npm run lint` are clean in `workspace-2/hrms/frontend`. Run
      `npm install` first if `node_modules` is missing.
- [ ] Manual check at ≥1280px and at ~900px width (the grid wraps cleanly with no orphaned
      single tile looking broken): HR Manager → Attendance and HR Admin → Insights → Attendance.
