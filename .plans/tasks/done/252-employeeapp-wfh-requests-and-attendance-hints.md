---
task: 252
title: Employee app — work-from-home requests, cancel, locked-day wording, missing clock-out fix
status: done
depends_on: [247, 250, 235, 236]
---

# 252 — Employee app: catch up with the employee-portal tasks 234–251

Repo: **`workspace-2/employeeapp/`** (React Native, its own git), branch `feature/gowtham_WfhRequests` cut from
`gowtham-dev`. **No backend change** — every endpoint already exists.

## What was reviewed
Done tasks 234–251, sorted by whether an employee can reach the feature.

| Task | Employee-facing? | In the app |
|---|---|---|
| 250 / 247 WFH request raise, list, cancel | yes | **built here** |
| 235 locked-day wording ("This day is locked. Ask HR to correct it.") | yes | **built here** (regularization form) |
| 236 missing clock-out explained | yes | **built here** (daily log) |
| 250 cancel a Pending request | yes | **built here**, both request types |
| 237 "How status is decided" legend | partly | not done: `GET /attendance/status-rules` is gated `READ ATTENDANCE` (HR). Needs an ungated `/me` variant first |
| 246 WFH marker on the roster | no | HR roster only; `/shifts/me/{date}` carries no `wfh_request` |
| 251 inbox approve / reject WFH | manager | not done: the app has no approvals inbox at all |
| 234, 245, 248, 249 | HR only | none |

## Scope
1. **WFH request form** — new screen `WfhRequest` (`ClockScreen/components/WfhRequestFormScreen/`): From / To, Reason,
   "Approver · name (designation)" from `GET /attendance/me/wfh-setup`; submit disabled with an explanation when there is no
   approver or no remote site; 31-day cap and end-before-start shown inline; server refusals (overlap, leave clash, locked day,
   past window) shown as-is through `getErrorMessage(..., { allowServerMessage: true })`. Reached from **Request WFH** in the
   requests list header.
2. **Requests list** (`RegularizationList`, now "MY REQUESTS") — it already received WFH rows from `GET /me/requests` and
   rendered them wrongly (`punch` null, first date only). Now: WFH rows show the date range and type "WFH"; Rejected has its own
   chip and shows the approver's remarks; Approved WFH says the work location is set to the remote site (name fetched once);
   **Cancel** on Pending rows (both types) through `showConfirmation`. The list also reloads on `refreshKey` now (it ignored it).
3. **Locked day** — `RegularizationFormViewModel.getSubmitErrorMessage` shows the server sentence for a 423 instead of the generic line.
4. **Missing clock-out** — daily log rows for a past day with a clock-in and no clock-out say "No clock-out recorded · Fix" instead of
   `0h 0m`; tapping opens the regularization form on that date set to Clock-out (`prefillDate` route param). Derived client-side
   (`isMissingClockOut`) because `missing_clock_out` is only on the day-analytics response; yesterday is not flagged while the
   employee is clocked in (a running night shift).
5. **Existing bug fixed on the way** — the regularization form sent `requested_in_at` / `requested_out_at` from the time picker, whose
   `Date` is *today*; for a past attendance date the punch would have landed on today. It now keeps the picked time on the attendance
   date. It also asks for the in/out time before submitting (was an uncaught invalid-date error).

## Files
- `src/api/EndPoints.js`, `src/navigation/BottomNavigator.js`, `src/screens/MenuScreen/Menu.js`
- `src/screens/ClockScreen/components/WfhRequestFormScreen/*` (new)
- `src/screens/ClockScreen/components/RegularizationListScreen/*`
- `src/screens/ClockScreen/components/RegularizationFormScreen/{RegularizationForm,RegularizationFormViewModel}.js`
- `src/screens/ClockScreen/components/AttendanceListScreen/{AttendanceList,AttendanceListViewModel,AttendanceListStyles}.js`

## Acceptance criteria
- [x] An employee can raise a WFH range, see it under My Requests with its range and status, and cancel it while Pending
- [x] Approved / Rejected / Cancelled rows have no Cancel; Rejected shows the remarks
- [x] No approver / no remote site → the form explains it and blocks submit; a failed setup call does not block
- [x] A locked day on regularization shows "This day is locked. Ask HR to correct it."
- [x] A past day with IN and no OUT shows the hint and opens the form prefilled; today and a running night shift are not flagged
- [x] `npx eslint` on the changed folders: 12 problems, identical to `gowtham-dev` (1 existing error, `Attendance.js:69`)
- [x] `react-native bundle --platform android` builds with the new screen
- [x] Pure logic checked (23 cases: range / blocker / date lines / cancel rule / missing-clock-out / 423 message), harness outside the repo
- [ ] **Device smoke test** (Android emulator or phone vs hrms-dev): raise → listed Pending → cancel; raise a clashing range → server
      message; approve from the web → "work location is set to …" note; past open day → Fix → form prefilled → submit lands on the
      right date. Needs a tenant with a remote site and a reporting manager; writes real rows, so wait for the go-ahead.
- [ ] `npm test` — still cannot run on `gowtham-dev` either (`@react-native/jest-preset` not installed; same as task 233)

## Notes
- The app's date format is DD-MMM-YYYY (`DateUtils.formatDate`), unchanged; the web's dd-MMM-yy rule is a web convention.
- A Regularization form for a night shift would need the out time on the *next* day; not handled, same as before.
- Not committed — left on the branch for review, like 233.

Closed 2026-10-26 at the user's instruction with two acceptance items left unverified and unticked above: the device smoke test (it writes real rows against hrms-dev, so it was waiting on a go-ahead) and `npm test` (cannot run: `@react-native/jest-preset` is not installed, same as task 233).

Completed: 2026-10-26
