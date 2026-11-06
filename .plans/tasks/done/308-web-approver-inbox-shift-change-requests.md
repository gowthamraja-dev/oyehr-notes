---
task: 308
title: Web approver inbox — show and approve shift change requests
status: done
depends_on: [306]
---

# 308 — Web: shift changes in the HR Manager Regularization Inbox

## Scope
`GET /attendance/requests` now returns `request_type = 'ShiftChange'` rows (task 306) carrying `current_shift_name` / `requested_shift_name`, and approving one returns
`ShiftChangeApproveResultOut {id, status, actioned_at, date, shift_master_id, shift_name}`. The inbox only knew Regularization and WFH, so a shift change
rendered as a "Regularization request" with no shift names. Make `frontend/src/dashboards/hrManager/RegularizationInbox.tsx` handle it:
- a **Shift change** option in the Type filter; list rows show type "Shift change", the single date, and `current → requested` shift names in the "Requested times" column;
- the detail modal titled "Shift change request", with a Current shift / Requested shift panel instead of the recorded-vs-requested punches table, plus a note on what approving does
  (that one day's shift only; location and holiday calendar kept; attendance recalculated if the day is today or earlier);
- approve (inline and in the modal) toasts `Shift set to <name> for <dd-MMM-yy>`; reject unchanged;
- `src/lib/api.ts`: `ShiftChangeRequest` type, added to `ManagerRequestRow` / `ManagerRequestDetail`, `listManagerRequests` accepts `"ShiftChange"`,
  `ShiftChangeApproveResult` + `isShiftChangeApproveResult`, `approveRequest` return union widened.
Not covered: any employee-facing web page for shift changes
(the employee side is the mobile app), a web "My Shifts" page. (The HR Admin dashboard's "attendance requests awaiting approval" count asks for all types, so shift changes are already counted there; nothing to change.)

## Rules to follow
Tailwind only (no new `.module.css`), dates via `formatDDMMMYY`, no native `confirm()`, no new `animate-pulse` blocks.

## Files
`frontend/src/dashboards/hrManager/RegularizationInbox.tsx`, `frontend/src/lib/api.ts`.

## Acceptance criteria
- [x] `tsc --noEmit` and eslint clean on the touched files
- [ ] Type filter offers Shift change and lists only those rows
- [ ] A shift change row shows the date and `current → requested`; the modal shows both shifts and the effect note, not the punch table
- [ ] Approve toasts the new shift; a refusal (locked day, holiday, …) shows the backend sentence in the modal / toast and leaves the request Pending
- [ ] Regularization and WFH rows render exactly as before
- [ ] Checked in a browser against a running app (needs the backend deployed with tasks 304-306)

## Progress (2026-10-29)
Built in `workspace-2/hrms`, NOT committed: `src/lib/api.ts` (types, `isShiftChangeApproveResult`, widened `approveRequest` / `listManagerRequests`) and `RegularizationInbox.tsx` (type filter option, list row, modal title + current/requested panel + effect note, approve toast). `tsc --noEmit` and eslint are clean (run on the whole project / the two files). NOT checked in a browser — that needs the app running, which needs the backend deployed with tasks 304-306, and no server was started. The remaining criteria are therefore unverified, including that Regularization and WFH rows still render as before (the changes to those paths are only the added union member and one new `if`/ternary branch each).

Moved to done on the user's instruction WITHOUT a browser check: the unticked criteria above (filter, row and modal rendering, approve toast, refusal messages, Regularization/WFH rows unchanged, browser check) are UNVERIFIED. Only `tsc` and eslint were clean.

Completed: 2026-10-29
