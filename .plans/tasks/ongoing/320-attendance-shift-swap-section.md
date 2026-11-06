---
task: 320
title: Web — Shift swap (change requests) moves into My Attendance
status: ongoing
depends_on: [305]
---

# 320 — Web: Shift swap section inside My Attendance

## Scope
The "Requests" tab and the "Request shift change" flow from task 309's `MyShifts.tsx` move into the **My Attendance** page (`MyAttendance.tsx`), next to the
existing Regularization / WFH requests, because a shift swap is an attendance request. Nothing about the APIs changes (`/shifts/me/change-requests`,
`/shifts/me/available`, contracts in `.plans/my-shifts-mobile-api.md`).

Move (do not rewrite) from `MyShifts.tsx`:
- `RequestsTab` (status filter All/Pending/Approved/Rejected/Cancelled, paged list, row -> details) -> a **"Shift swap requests"** section on My Attendance, same card
  style (`bg-white border border-border rounded-[14px]`) and 10px spacing as its sibling request sections.
- `RequestFormModal` (DateField min today, read-only Current Shift, Requested Shift select, Reason 0/500) and `RequestDetailModal` (Cancel via `useConfirm`, only when `can_cancel`).
- A **"Request shift change"** button in the same header row as the existing Regularization / WFH request buttons (`MyAttendance.tsx` ~line 649 area), opening `RequestFormModal`.
- Extract them to a new `Employee/ShiftChangeRequests.tsx` (exports `ShiftChangeRequestsCard`, `RequestFormModal`, `RequestDetailModal`, plus the small helpers they use: `Pill`, `ShiftChip`, `STATUS_PILL`, `formatTime`/`timeRange`) so Home (task 321) can open the same form modal. Keep a shimmer skeleton for the card (compose from `Shimmer.tsx` primitives; no fabricated elements).

Not covered: the calendar (task 321), removing the nav item/page (task 322), approver inbox (task 308), mobile.

## Rules
Tailwind only; dates `formatDDMMMYY` / `DateField`; shimmer skeletons; `useConfirm()`; `secureFetch` for every call; gate the button/section on the same `ATTENDANCE` resource the page already uses.

## Files
`frontend/src/dashboards/Employee/ShiftChangeRequests.tsx` (new), `frontend/src/dashboards/Employee/MyAttendance.tsx`, `frontend/src/dashboards/Employee/MyShifts.tsx` (code removed here, file deleted in 322).
`frontend/src/lib/api.ts` already has the six functions — no change expected.

## Acceptance criteria
- [x] `tsc --noEmit` clean; eslint adds nothing new (MyAttendance.tsx keeps its 1 existing set-state-in-effect error and unused-`me` warning)
- [ ] My Attendance shows a "Shift swap requests" section with status filter, paging and a details modal
- [ ] "Request shift change" button opens the form; submit refreshes the list; a backend refusal sentence shows inline and keeps the modal open
- [ ] Cancel asks for confirmation and only appears for Pending requests
- [ ] Section/button do not appear for a role without `ATTENDANCE` access
- [ ] Checked in a browser against a running app (backend with 304-306 deployed)

## Progress (2026-11-02)
Built in `workspace-2/hrms/frontend`, NOT committed: new `Employee/ShiftChangeRequests.tsx` (`ShiftChangeRequestsCard`, `RequestFormModal`, `RequestDetailModal`, exported `formatTime`/`timeRange`);
`MyAttendance.tsx` gets the "Shift Swap Requests" card (left column, under My Requests), a "Request shift change" button in the Daily Log header (header now wraps) and the form modal;
`MyShifts.tsx` loses its Requests tab/modals and imports the form from the new file (it still compiles; the file is deleted in 322). Not run in a browser; every other criterion is UNVERIFIED.
Not done: no `ATTENDANCE` gate on the section/button — My Attendance itself is the gated nav item (`resource: "ATTENDANCE"`), so it inherits that; no separate check was added.
