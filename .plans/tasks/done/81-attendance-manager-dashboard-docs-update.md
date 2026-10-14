---
task: 81
title: Manager Attendance dashboard — docs update
status: done
depends_on: [74, 78, 79, 80]
---

# 81 — Manager Attendance dashboard — docs update

## Scope

Bring `docs/leave-and-attendance/` back in sync now that tasks 68-80 have built the manager
dashboard surface it has documented as "Not built" since it was written. Matches this project's
own convention of a dedicated docs-update task closing out each feature cluster (see
`17-shift-assignment-docs-update.md`, `38-attendance-clock-regularization-docs-update.md`,
`51-leave-request-docs-update.md`).

## Updates

1. **`docs/leave-and-attendance/attendance/api-and-pages.md`**:
   - §3.1/3.2 rows for `/register`, `/analytics`, `/employees/{id}/analytics`: flip **Not built**
     → **Built**, update the sample contracts in §4.4/§4.5 to match what tasks 69/70/72 actually
     shipped (field names/shapes may have drifted slightly during implementation — verify against
     the real schemas, don't just relabel the existing sketch as built).
   - Add new rows/sections for `/exceptions` (task 71) and `/register/export` (task 73) — neither
     existed in the original sketch; document them as genuinely new additions, not corrections.
   - §2.3 (Manager pages table): flip `attendance` row's status from "**Not built** — `Attendance.
     tsx` is mock-data only" to **Built**, remove the top-of-file status callout's "Not built:
     ... the attendance register, analytics, per-employee analytics ... `Attendance.tsx` in
     `hrManager` is still mock-data-only" sentence (or rewrite it to reflect what's still
     genuinely unbuilt — devices, punches, rebuild/lock, `/me/summary`, `/team/today` — since
     those remain out of scope for this task cluster).
2. **`docs/leave-and-attendance/attendance/vocabularies.md`**: add the `effective_status` addendum
   from task 68 — a new dashboard-only, read-time-computed field, explicitly scoped to the
   manager-dashboard endpoints, that resolves a `NULL` `attendance_status` to `Absent` for past
   dates only. State plainly that this does **not** change §1's rule for the stored
   `attendance_status` column or for `/me/*`/`/employees/{id}/today`/`/daily` — those still never
   render `NULL` as `Absent`.
3. **`docs/leave-and-attendance/attendance/gaps.md`**: add a lettered addendum (following
   Addendum A's own pattern) recording that the manager dashboard's Absent/attendance-% numbers
   are now real but still bounded by Addendum A's underlying limitation (no auto-absent sweep) —
   i.e., today's date will under-report Absent until an employee's day fully elapses, by design,
   not by bug. Cross-reference from Addendum A to the new one.
4. **`docs/leave-and-attendance/README.md`** §1.1 (Personas and surfaces table): update the
   Manager row's `attendance` cell to reflect the real, wired dashboard instead of "still
   mock-data only: no `/attendance/register` or `/attendance/analytics` endpoint exists yet".
5. **`docs/leave-and-attendance/attendance/manager-approvals.md`**: add whatever this task
   cluster's actual manager-scope decisions (§3.3-style predicate reuse, department/shift filter
   semantics, no-team-table decision) belong in this file rather than only in the task files —
   check this doc's existing structure before adding, to avoid duplicating what's already stated
   there for the regularization inbox and simply cross-reference instead of restating.

## Files

- `docs/leave-and-attendance/attendance/api-and-pages.md`
- `docs/leave-and-attendance/attendance/vocabularies.md`
- `docs/leave-and-attendance/attendance/gaps.md`
- `docs/leave-and-attendance/attendance/manager-approvals.md`
- `docs/leave-and-attendance/README.md`

## Acceptance criteria

- [x] No doc in this corpus still describes the manager Attendance dashboard as mock-data-only
      or its APIs as "Not built" once tasks 68-80 are done.
- [x] The `effective_status`/read-time-Absent decision (task 68) is recorded as a flagged,
      justified deviation, not silently absent from the vocab doc (per this repo's own §3.2 rule:
      "Deviations are flagged, never silent").
- [x] Every doc claim added here was checked against the actual shipped code, not copied from
      this task-file cluster's proposals as if they were guaranteed to match the final
      implementation exactly.
