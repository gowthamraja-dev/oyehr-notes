---
task: 76
title: Manager Attendance dashboard — top controls, KPI row, real data wiring
status: done
depends_on: [75]
---

# 76 — Manager Attendance dashboard — top controls, KPI row, real data wiring

## Scope

Rewire `frontend/src/dashboards/hrManager/Attendance.tsx` from its current mock-data prototype
(`REGISTER`, `ANALYTICS_BY_PERIOD` constants, the "Preview data" badge at line ~141) to real,
API-driven state, per design prompt §1-4 and §22-23. This task covers the page shell, top
controls, and KPI row; the table's own behavior (pagination/sort/loading-empty-error) is task 77,
the drawer is task 78, exceptions section is task 79, export is task 80 — keep this task scoped
to the shell so it stays reviewable.

**Delete** `REGISTER`, `ANALYTICS_BY_PERIOD`, `DEPARTMENTS` (the derived-from-mock one), and the
"Preview data" badge entirely — design prompt §22 is explicit that these prototype constants must
be removed, not left dead in the file.

## Page title/subtitle (design prompt §1)

Title: **Attendance**. Subtitle: **Monitor team attendance, working hours and exceptions** — add
this subtitle under the `<h1>`; it doesn't exist in the current mock header.

## Top controls (design prompt §3)

- **Date selector**: default today; previous-day/next-day buttons either side of a native
  `<input type="date">` (this codebase's established date-input pattern — see
  `HolidayCalendarAdmin.tsx`/`MyLeave.tsx`, no date-picker library is used anywhere in this repo,
  don't add one) plus a "Today" shortcut button. Block picking a date after today client-side
  (disable via the input's `max` attribute) — design prompt §3 forbids future operational
  attendance dates; the backend doesn't need to separately validate this for now since every new
  endpoint (69-71) treats a future date as simply "no rows yet", which is harmless, but the UI
  should still not offer it.
- **Period selector**: Day/Week/Month segmented control — reuse the existing `PeriodToggle`
  component already in this file verbatim (it's already correct, just needs to drive the real
  `getManagerAttendanceSummary` call's `period` param instead of indexing into
  `ANALYTICS_BY_PERIOD`). Per design prompt §3, changing period must refresh only the analytics
  band, never re-fetch or reset the table's `date`/filters/pagination — keep the period state and
  the table's fetch effect independent.
- **Filters**: Department (native `<select>`, options from the existing `GET /employees/
  departments` endpoint — reuse it, don't hardcode or derive from row data anymore), Shift
  (native `<select>`, options from the existing `GET /shifts` list endpoint), Status (keep the
  existing pill-group UI pattern, values now `all|present|late|onleave|absent|weekoff|holiday|
  yettocheckin` matching task 70's `status` param — expand the current 5-value `STATUS_FILTERS`
  array). No Location filter (design prompt explicitly excludes `work_location_id` for now).
- **Search**: a text input (name/emp id/mobile) debounced (~300ms) before triggering the
  register re-fetch — server-side per design prompt §3, not client-side `Array.filter` like the
  current mock's `filtered` memo.

## KPI row (design prompt §4)

Six tiles from `getManagerAttendanceSummary`'s response: Present (with `%`), Late, On Leave,
Absent, Yet to Check In, Attendance %. Reuse the existing `KpiTile` component; add the sixth
(Attendance %) tile — the current mock only has 5 (it folds Attendance % into the Present tile's
subtitle). Every tile must show a shimmer skeleton (per `CLAUDE.md`'s loading-states convention —
reuse `AttendanceSkeleton`'s already-correct KPI-tile skeleton block) while the summary request is
in flight, and must not render `0` as if it were a loaded real value when the request has failed
(design prompt §23) — track summary loading/error state separately from the table's.

## State (design prompt §22)

`selectedDate`, `period`, `department`, `shiftId`, `statusFilter`, `search`, plus (owned by task
77 but declared here since this is the shell) `page`/`sort`/`direction`. Summary
(loading/error/data) and register (loading/error/data) are separate async states with
independent retry — a failed summary must not block the table from rendering, and vice versa.

## Files

- `frontend/src/dashboards/hrManager/Attendance.tsx` — primary rewrite
- No changes to `hrManager/index.tsx`/`registry.ts` — the `attendance` view key and its mount
  point already exist and are already live; this task only changes what's inside the component.

## Manual verification

Run the dev server, log in as a manager with ≥1 direct report who has attendance data, open
Attendance, and confirm: KPI tiles show real counts matching the seeded data, changing the date
(prev/next/picker/today) refetches the summary, changing period only changes the KPI/analytics
band not the table, department/shift dropdowns are populated from real endpoints.

## Acceptance criteria

- [x] No hardcoded `REGISTER`/`ANALYTICS_BY_PERIOD`/"Preview data" badge remain in the file.
- [x] All top controls and the KPI row are backed by tasks 69/75's real API calls.
- [x] Department/Shift filter options come from existing real endpoints, not mock arrays.
- [x] Manually verified in the browser per above.
