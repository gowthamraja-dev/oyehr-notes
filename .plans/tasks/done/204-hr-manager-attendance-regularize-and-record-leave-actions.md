---
task: 204
title: Frontend — "Regularize" and "Record leave" actions on Absent / Missing clock-out / Late rows in HR Manager attendance
status: done
depends_on: [203]
---

# 204 — HR Manager attendance: Regularize and Record leave actions

Build this in the **top-level `hrms/`** clone. Paths are relative to `hrms/`.

## Why
On the HR Manager attendance register (`frontend/src/dashboards/hrManager/Attendance.tsx`),
HR sees Absent, Missing clock-out and Late rows but can't act on them. The drawer
(`EmployeeDrawer`) only offers "Review" when the employee has already raised a pending
regularization. HR wants to:
- **regularize** the day themselves (backend from task 203), and
- **record leave the employee actually took** for that day. The backend and
  `RecordLeaveModal` already exist from task 197:
  `frontend/src/dashboards/shared/LeaveBalanceActions.tsx`, which calls
  `previewRecordLeave`/`recordLeaveOnBehalf` in `lib/api.ts`. Today it's only reachable
  from the employee Leave tab.

## Scope
1. **When the actions show.** On a register row and in the drawer, show them for:
   - `effective_status === "Absent"`: **Regularize** (default punch = Both) and **Record leave**.
   - Missing clock-out (`first_in_at` set, `last_out_at` null, day closed, or the
     `missing_clock_out` exception filter): **Regularize** (punch = Clock-out).
   - `is_late`: **Regularize** (punch = Clock-in).
   - Hide them when `has_pending_regularization`. The existing "Review" link wins.
   - Hide them on future dates and for users without the permission. Use the same
     permission source the page already uses for the "Review" link (APPROVE ATTENDANCE).
     The backend 403s anyway.
2. **`RegularizeModal`** (new, in `frontend/src/dashboards/hrManager/`): fields for date (read-only,
   from the row), punch selector, the in/out time inputs the selector needs (prefilled
   from the shift start/end or existing punches), reason (same `REGULARIZATION_REASONS`
   list as the employee form), and a required note.
   - Calls the new `regularizeOnBehalf(employeeId, body)` in `lib/api.ts` via `secureFetch`.
   - Modal chrome follows the `px-5 py-4` convention. Dates use `formatDDMMMYY` and
     `DateField` (hrms-date-format skill).
3. **Record leave**: open the existing `RecordLeaveModal` with `from_date = to_date =` the
   row's date, prefilled. No new leave UI.
4. **After success**, refetch the summary, register and exceptions (`fetchSummary`,
   `fetchTable`, `fetchExceptions`), then show a toast. The row should now read
   Present/On leave.
5. Errors (409/422/423) show the backend `detail` inline in the modal.

**Not in scope:** backend changes (203 / task 197) and tile headcount (202).

## Files
- `frontend/src/dashboards/hrManager/Attendance.tsx`: row action buttons, drawer actions,
  modal wiring, refetch
- `frontend/src/dashboards/hrManager/RegularizeModal.tsx` (new)
- `frontend/src/lib/api.ts`: `regularizeOnBehalf` and its types
- `frontend/src/dashboards/shared/LeaveBalanceActions.tsx`: only if `RecordLeaveModal`
  needs an `initialFrom/initialTo` prop

## Acceptance criteria
- [ ] Absent row: Regularize (Both) turns it Present. Record leave turns it On leave, and
      the balance is debited (confirm on the employee Leave tab).
- [ ] Missing clock-out row: Regularize (Clock-out) sets the clock-out and worked hours.
- [ ] Late row: Regularize (Clock-in) clears the Late badge.
- [ ] No actions on rows with a pending regularization (Review shows instead), on future
      dates, or for a role without APPROVE ATTENDANCE.
- [ ] Tiles, register and exception chips refresh after each action, with no full-page
      skeleton flash.
- [ ] `npm run build` / lint pass, and a manual smoke test on the dev stack (CDP 100240).

Completed: 2026-10-13
