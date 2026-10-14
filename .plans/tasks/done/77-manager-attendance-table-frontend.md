---
task: 77
title: Manager Attendance dashboard — register table behavior
status: done
depends_on: [76]
---

# 77 — Manager Attendance dashboard — register table behavior

## Scope

The main employee attendance table's runtime behavior, per design prompt §6-7 and §23: server-
side pagination, sorting, loading/empty/error states, on top of the shell task 76 built. Columns
and semantic status colors are already close to correct in the current mock table — this task
is about making the table real and complete, not restyling it.

## Columns (design prompt §6)

Employee (avatar/initials + name + emp id — already correct), Department, Shift, Status, Clock
In, Clock Out, Worked Hours, Late By, Attendance (redundant with Status per the design prompt's
own table — fold into one Status cell showing the effective-status pill plus the existing amber
"Late" badge when `is_late`, exactly as the current mock already renders it; don't add a
duplicate seventh "Attendance" column), Actions (opens the drawer — already wired via row
`onClick`, task 78 owns what the drawer shows).

`Worked Hours` renders `worked_hours_display` from the register API verbatim (already formatted
as `"Incomplete"`/`"Nh MMm"`/`"—"` by the backend, task 68/70) — no client-side duration math.
`Late By` renders `late_by_minutes` as `"Nm"` when `is_late`, else `"—"`.

## Behavior

- **Pagination**: page-size 25 (matches task 70's default `limit`), Prev/Next controls, showing
  "Showing X–Y of N employees" — replace the current mock's flat "Showing N of M" footer.
- **Sorting**: clickable column headers for Employee/Clock-in/Clock-out/Worked hours/Late
  duration (design prompt §7's optional list), toggling `sort`/`direction` and re-fetching.
  Default (no explicit sort applied) is the backend's own default (status-priority + name,
  task 70) — don't re-sort client-side on top of what the server returned.
- **Loading**: skeleton rows matching the real column grid (reuse/extend `AttendanceSkeleton`'s
  table-skeleton block) while a register fetch is in flight — including on page/sort/filter
  change, not just first mount.
- **Empty states** (design prompt §23), distinguished by cause:
  - Zero employees in scope at all (e.g. manager has no direct reports) → **"No employees
    found"**
  - Employees exist but zero attendance rows for the selected date → **"No attendance records
    for this date"**
  - Rows exist for the date but the active filters/search exclude all of them → **"No employees
    match your filters"**
  These three are distinguishable from the register response's `total` combined with whether any
  filter/search/status is active — encode this as a small pure function, not ad hoc JSX
  conditionals scattered through the render.
- **Error**: **"Attendance data could not be loaded"** with a **Retry** button that re-issues the
  same register request (same date/filters/page/sort) — do not reset filters on retry.
- Filter/search/sort changes reset `page` to 0 (changing what you're looking at shouldn't leave
  you stranded on an out-of-range page).

## Files

- `frontend/src/dashboards/hrManager/Attendance.tsx`

## Manual verification

Seed enough attendance rows to exceed one page; confirm pagination, each sort column, each of the
three empty-state messages (by manipulating date/filters), and the error+retry path (e.g. by
temporarily pointing the API base at a bad port, or throttling in devtools) all render correctly
and match the states described above.

## Acceptance criteria

- [x] Pagination and sorting are server-side (drive `limit`/`offset`/`sort`/`direction` params),
      never client-side re-slicing of a fully-fetched array.
- [x] All three empty-state messages and the error+retry state are implemented and distinguished
      correctly, matching design prompt §23's exact copy.
- [x] Manually verified per above.
