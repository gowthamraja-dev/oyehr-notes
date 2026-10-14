---
task: 78
title: Manager Attendance dashboard — employee attendance drawer
status: done
depends_on: [75, 76]
---

# 78 — Manager Attendance dashboard — employee attendance drawer

## Scope

Replace the current mock `EmployeeAnalyticsModal` in `hrManager/Attendance.tsx` (reads
`ANALYTICS_BY_PERIOD`, a `RegisterRow` from the mock array) with a real, API-driven drawer per
design prompt §8, reusing task 72's new per-employee analytics endpoint plus the existing task
54 endpoints already consumed by `frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx`.

**Do not build a second attendance-drawer component from scratch** — `EmployeeAttendanceTab.tsx`
already implements the Day/Week/Month period toggle, the "Day" clock-in/out card, and the
Week/Month daily table, wired to real `getEmployeeAttendanceToday`/`getEmployeeAttendanceDaily`
(task 54) and already used by the employee-profile view (task 59). This task's job is to (a) add
the aggregate metric tiles (design prompt §8's Worked hours/Average hours/Timely days/Late
days/Attendance %/Worked days) that component currently lacks, using task 72's new `GET
/employees/{id}/analytics`, and (b) present it inside a right-side drawer (design prompt's
"drawer pattern", not the current mock's centered modal) matching the header design prompt §8
specifies.

## Approach

- Extend `EmployeeAttendanceTab` (or a thin wrapper around it used only here, if the
  employee-profile context and the manager-dashboard context end up needing different chrome
  around the same core) to also call `getEmployeeAttendanceAnalytics` (task 75) whenever `period`
  changes, and render the metric-tile row above/alongside the existing Day card / Week-Month
  table using the existing `MetricTile` component already defined in `hrManager/Attendance.tsx`
  (move it to a shared location, e.g. `dashboards/shared/`, if both the employee-profile tab and
  this drawer now use it — don't duplicate the component).
- Drawer header (design prompt §8): avatar/initials, name, employee ID, department, role
  (`designation`), shift, current status — all already present in the register row (task 70's
  `RegisterRowOut`) that opens the drawer; no extra fetch needed for the header itself.
- "Today's attendance" section: clock in, clock out, worked hours, late duration, status, punch
  source if available — `punch_source` requires reading the underlying `AttendancePunchDetail`
  the day's `first_in_at` came from; if that's not already exposed by `/employees/{id}/today`
  (task 54), treat "punch source" as best-effort/omit rather than adding a new backend field for
  it in this task — it's explicitly "if available" in the design prompt, not required.
- Switching the drawer's own Day/Week/Month toggle must not affect the main table's `period`
  state from task 76 — they are independent, exactly as `EmployeeAnalyticsModal`'s current
  `modalPeriod` state already keeps them separate.

## Regularization integration (design prompt §10)

If the opened employee's register row has `has_pending_regularization: true` (task 70), show
**"Regularization pending"** with a **Review** action in the drawer. Clicking Review must not
open a second, competing regularization UI inside this drawer — per design prompt §10 and this
codebase's existing `RegularizationInbox.tsx` (tasks 33/36), navigate to that existing view via
the `navigate` callback the dashboard shell already passes to every view's `render(me, navigate)`
(`frontend/src/dashboards/types.ts`): thread `navigate` down from `hrManager/index.tsx`'s
`attendance` view registration (`render: (me, navigate) => <Attendance me={me}
navigate={navigate} />` — currently `render: (me) => <Attendance me={me} />` drops the second
param; this task must add it) into the drawer, and call `navigate("regularizations")` on Review.

Landing on the exact pending request within the inbox (rather than just switching to the view) is
out of scope for this task — `RegularizationInbox.tsx` has no query-param/deep-link support today
and adding one is a separate, `RegularizationInbox`-owned change; note it as a follow-up rather
than building it here.

## Files

- `frontend/src/dashboards/hrManager/Attendance.tsx` — replace `EmployeeAnalyticsModal` with the
  drawer, threading `navigate`
- `frontend/src/dashboards/hrManager/index.tsx` — pass `navigate` through to `<Attendance />`
- `frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx` — add the aggregate-metrics fetch/
  render (or extract a shared metrics-tile sub-component both this file and the drawer use)

## Manual verification

Open the drawer for an employee with a pending regularization; confirm the metric tiles show
real Day/Week/Month numbers matching what task 72's endpoint returns, and clicking Review lands
on the Regularization Inbox view.

## Acceptance criteria

- [x] Drawer shows real header/today/period-analytics data, no mock `ANALYTICS_BY_PERIOD`.
- [x] `EmployeeAttendanceTab`'s existing Day/Week/Month raw-data logic is reused, not
      reimplemented, for the parts it already covers.
- [x] "Review" on a pending regularization navigates to the existing Regularization Inbox view
      via the shell's `navigate` callback — no second regularization-approval UI is built.
- [x] Manually verified per above.
