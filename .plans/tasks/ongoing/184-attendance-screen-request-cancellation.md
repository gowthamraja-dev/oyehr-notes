---
task: 184
title: Request cancellation on the HR Manager Attendance screen + employee drawer
status: ongoing
depends_on: [181]
---

# 184 — Request cancellation on the HR Manager Attendance screen + employee drawer

## Scope
`hrManager/Attendance.tsx` (the canonical attendance UI, also embedded by HR Admin Insights)
re-fetches tiles, exception chip counts and the register table on every
range/department/shift/search/filter/sort/page change. The chip counts and the table had no
staleness guard, so a slow older response could overwrite newer data. The drawer
(`shared/EmployeeAttendanceTab.tsx`) races the same way on its Day/Week/Month toggle and fires
two loads on every tab refocus.

**Configured entirely in `api.ts`, not in the components** (user's call, 05-Oct-26). Each
helper is wrapped with `latestOnly(fn, { lane })` from `src/lib/latestRequest.ts`. A newer call
in the same lane aborts the older HTTP request, and the older promise never settles, so the
components' existing `.then/.catch/.finally` code runs only for the latest call. Neither
component changed.

| Helper | Lane |
|---|---|
| `getManagerAttendanceSummary` | `attendance.summary` |
| `getManagerAttendanceRegister` | `attendance.table` |
| `getManagerAttendanceExceptions` | `attendance.table` with a `type` (the table), else `attendance.exception-counts` (the chips) |
| `getEmployeeAttendanceToday`, `getEmployeeAttendanceDaily` | `attendance.employee.view` |
| `getEmployeeAttendanceAnalytics` | `attendance.employee.analytics` |

Lanes are app-wide. That's safe here: each helper's only callers are these two components
(grep'd 05-Oct-26).

**Not in scope:** CSV export; the one-shot department/shift option loads;
`Employee/MyAttendance.tsx` (no changing inputs). Requests are not aborted on unmount; a late
response just lands on an unmounted component, which is harmless.

## Files
- `hrms/frontend/src/lib/latestRequest.ts` (new): `latestOnly`
- `hrms/frontend/src/lib/api.ts`: the six helpers above

## Acceptance criteria
- [x] `npx tsc --noEmit` and eslint clean on the touched files.
- [x] Node test with the real `secureFetch` against the dev API (05-Oct-26): superseded calls never settle, including across two helpers sharing a lane. The latest call resolves, another lane is unaffected, and a real error still rejects.
- [ ] With "Slow 3G": stepping the date or flipping department/shift/status quickly shows superseded `/attendance/{analytics,exceptions,register}` calls as `(canceled)`. Tiles, chips and table match the final selection, and no error card flashes.
- [ ] Typing in search cancels the previous register call (debounce unchanged).
- [ ] Live poll (range includes today) still refreshes tiles quietly every interval. A filter change during a poll cancels the poll and shows the skeleton, which then resolves.
- [ ] Drawer: Day→Week→Month quickly shows only Month's data. Returning to the tab fires one request per load, not two.

Work is in the top-level `hrms/` clone (user's call, 05-Oct-26).
