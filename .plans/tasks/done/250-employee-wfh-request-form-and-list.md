---
task: 250
title: Employee — "Work from home" request form, own list, cancel
status: done
depends_on: [247]
---

# 250 — Employee — "Work from home" request form, own list, cancel

Part of `.plans/shift-wfh-plan.md`. Backend contract: task 247 (`POST /attendance/requests/wfh`,
`GET /attendance/me/requests` with WFH rows, `POST /attendance/requests/{id}/cancel`).

## Scope
An employee raises a WFH request for a date range, sees their WFH requests, and cancels a Pending one.
No effect on attendance/payroll is shown or promised — approval just moves their work location to the remote site.

## Files
- `frontend/src/lib/api.ts` — `submitWfhRequest`, widen the request types (`request_type`, `from_date`, `to_date`).
- `frontend/src/dashboards/Employee/WfhRequestModal.tsx` (new), modelled on `RegularizationModal.tsx`:
  From / To via `DateField` (dd-MMM-yy), Reason (required), footer "Approver · <name> (<designation>)" resolved
  live; submit disabled with a message when there is no approver or the organisation has no remote site
  (server returns 422 — surface its message). Modal header/footer real and static; body shimmer while loading;
  `useSecureFetch`/`secureFetch` only.
- Entry point beside the existing Regularization action on the employee's attendance page
  (`dashboards/shared/EmployeeAttendanceTab.tsx` / the Employee dashboard — find where Regularization is launched).
- Request list: WFH rows with a date range chip and status; Cancel on Pending only, confirmed with `useConfirm`
  (never native `confirm`). Approved rows say "Your work location is set to <remote site> for these days".
- Tailwind only; shared `Shimmer*` primitives; spacing per `hrms-spacing`.

## Acceptance criteria
- [x] Employee raises a WFH range from the attendance page; validation messages show for bad ranges / blank reason
- [x] No approver / no remote site → form explains it and blocks submit
- [x] Own WFH requests listed with range + status; Cancel works on Pending only
- [x] `tsc` + ESLint clean on changed files; headless-browser smoke against a local DB: raise → listed Pending →
      cancel; raise a clashing range → server message shown

## Implementation notes (24-Oct-26)
- **Backend addition** (not in the original 247 scope): `GET /attendance/me/wfh-setup` → `WfhSetupOut {approver, remote_site_name}`
  (`attendance.service.get_my_wfh_setup`; self-service, read-only, tenant-scoped, archived / other-tenant remote sites ignored),
  because the form's "Approver · name" footer and the "no approver / no remote site" blocks need that before submit —
  nothing resolved the approver ahead of a request until now. 5 tests added to `test_attendance_wfh.py` (41 passing).
- `lib/api.ts`: `WfhRequest`, `MyRequest = RegularizationRequest | WfhRequest` (`listMyRequests` / `cancelMyRequest` use it),
  `getMyWfhSetup`, `submitWfhRequest` (string `detail` → inline message, anything else → a generic line).
  **`listManagerRequests(status, requestType = "Regularization")`**: the manager inbox and the HR dashboard's pending count
  only render regularizations, and WFH rows now exist, so they keep asking for Regularization only until 251 passes
  `"All"` / `"WFH"`. (Side effect until 251: a manager can't see WFH requests in the UI.)
- `WfhRequestModal.tsx`: shimmer body while the setup loads (header / footer stay real, submit disabled); From / To `DateField`s
  (To's `min` follows From), "N days", inline range problems (end before start, > 31 days), required reason; amber notice
  and disabled submit when there is no approver or no remote site; footer "Approver · name (designation)"; server errors
  (overlap, leave clash, locked, window …) shown in the footer; success toast names the approver.
- `MyAttendance.tsx`: "Request work from home" beside "Request regularization"; the list is now **My Requests**; WFH rows show the date
  range (`formatRangeLabel`), "Work from home", status; Approved → "Your work location is set to <site> for these days." (site
  name fetched once, only when an approved WFH row exists); Rejected shows the approver's reason. Cancel (Pending only) now asks
  through `useConfirm` for **both** request types (it was an immediate click before — the component had no `useConfirm`, only
  `ClockCard` did).
- Verification: `tsc` clean; ESLint on the changed files shows only the two findings already on the committed `MyAttendance.tsx`
  (`me` unused, `setState` in the `loadDaily` effect). Headless-browser smoke against a local DB (never the shared one) 21/21:
  empty state, shimmer while loading, approver footer, range / reason validation, submit → listed Pending with range + reason
  + DB row, overlap refused inline, confirm → Cancelled, blocked with no remote site, blocked with no approver, approved note.
  Screenshots `50`–`55-wfh-*.png` in the session scratchpad.
- Docs: `attendance/api-and-pages.md` (`/me/wfh-setup` row, My Attendance page row); `hrms-mobile-api-integration` skill row.
