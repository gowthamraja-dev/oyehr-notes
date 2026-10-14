---
task: 79
title: Manager Attendance dashboard — exceptions section
status: done
depends_on: [75, 77]
---

# 79 — Manager Attendance dashboard — exceptions section

## Scope

Add the design prompt §9 Exceptions section to `hrManager/Attendance.tsx`, backed by task 75's
`getManagerAttendanceExceptions` client (task 71's API). Placed below the KPI row and above (or
beside, per design prompt §18's "below the employee table or alongside it depending on screen
width") the main table — pick below the KPI row and above the table, since exceptions are meant
to redirect attention *before* scanning the full register, matching the design prompt's framing
("surface actionable problems rather than forcing managers to inspect every employee").

## UI

A row of compact count chips/cards, one per exception type from task 71 (`missing_clock_out`,
`late_arrival`, `early_departure`, `unresolved_regularization`; include `missing_clock_in` only
if its count is nonzero — it's a rare data-anomaly type, not worth a permanent zero-value tile).
Each chip shows the type's label and count (e.g. "Missing clock-out · 2"), fetched once per
date/department/shift change (reuse the same date/filter state task 76 owns — the exceptions
counts should reflect the same scope, not need their own separate filter bar).

Clicking a chip sets the main table's `status`/exception filter to that type and scrolls to the
table (design prompt: "allow the manager to filter the main table to that exception") — implement
this by having the exceptions section set the same `statusFilter`/dedicated-exception-type state
task 77's table reads, re-triggering its register fetch with the narrowed query. Do not fetch and
render a second, separate row list here for the clicked exception — the main table becomes that
list, which avoids building two parallel table renderers.

## Loading/empty

Skeleton chips while loading (short shimmer bar per chip, matching this file's existing skeleton
conventions). If every count is zero, still render the row (all-zero chips) rather than hiding
the whole section — a manager should be able to see "0 exceptions" as a positive signal, not
wonder whether the section failed to load. On fetch failure, show a compact inline retry rather
than the full-page error state task 77 uses for the table (this is a secondary section, not the
primary content).

## Files

- `frontend/src/dashboards/hrManager/Attendance.tsx`

## Manual verification

Seed at least one row per exception type; confirm each chip's count matches, clicking a chip
narrows the table below to exactly those rows, and the table's existing status pill filter and
the exception-chip filter don't fight each other (clicking a status pill should clear any active
exception-type filter and vice versa — pick one source of truth for "what's currently filtering
the table" rather than two independent filter states that can silently conflict).

## Acceptance criteria

- [x] All exception counts are real, from task 71's API, scoped to the current date/filters.
- [x] Clicking an exception chip filters the existing table rather than rendering a duplicate
      list.
- [x] Manually verified per above.
