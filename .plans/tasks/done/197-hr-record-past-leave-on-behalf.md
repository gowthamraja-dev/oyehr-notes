---
task: 197
title: HR leave migration & correction — historic balance upload + record already-taken leave on behalf
status: done
depends_on: []
---

# 197 — HR leave migration & correction

Work in **`workspace-2/hrms/`** on branch **`feature/gowtham_HistoricLeave`**, cut from
`origin/main` @ `9c6c9ec`. This task is the exception to "leave work lives in top-level
`hrms/`". Paths and line numbers below are relative to `workspace-2/hrms/` on that branch.

## Why
When a company moves onto HRMS, HR has to do two things that the product can't fully do on
`main` today.

1. **Load each employee's existing leave balance from the old system (historic balance
   upload).** This was built as task 165 (commit `6af117ab`) on `feature/gowtham_LeaveMasters`,
   but that commit never reached `main`, so `main` has no opening-balance path and no
   "Adjust balance" UI.
2. **Record leave an employee already took without applying,** both during migration and in
   ongoing use. This means deducting it from the balance **and** recording the dates as leave.
   - **Applying is self-service only.** `apply_for_leave` (`backend/app/modules/leave/service.py:1448`)
     resolves the employee with `_require_self_employee`.
   - **Back-dated applications are refused.** `_DEFAULT_MAX_BACKDATED_LEAVE_DAYS = 0` (`:718`), so
     `validate_notice` (`:908`) returns 422 "Backdated leave applications are not allowed".
   - **"Adjust balance" corrects only the number.** It writes a bare `Adjustment` ledger row with
     no `leave_request_details` row. The dates never become `OnLeave` in attendance, because only
     an approved request does that (`calendar_resolver_service.resolve_approved_leave`).

## Part A — Historic balance upload (port task 165 onto this branch)
**Status: cherry-picked as `a2dbfa1`.** The only conflict was an import line in
`EmployeeLeaveTab.tsx`, where `main` had already switched to `formatDDMMMYY`. Both imports were
kept. What it brings:

- **Backend** (`backend/app/modules/leave/opening_balance_service.py`), one pipeline behind both
  entry points:
  - `POST /leave/employees/{id}/ledger/opening` (single), `router.py:410`.
  - `POST /leave/opening-balances/import` (bulk, ≤ 5,000 rows, `dry_run` preview),
    `router.py:421`.
  - Both endpoints are on EncryptedRoute and need `UPDATE LEAVE`.
  - It writes `Opening` ledger rows (`source='OPENING'`, `leave_policy_detail_id` set).
  - Every outcome is a per-row status: `ready`, `created`, `unchanged`, `conflict`, `blocked` or
    `error`.
  - An accrual double-count guard warns when an unprocessed accrual period straddles the opening
    date.
- **Frontend:**
  - **HR Admin → Leave → Policy assignments:** an "Import opening balances" modal. It offers a
    CSV template (`emp_id,leave_type_code,balance,as_of_date,remarks`), parses the file
    client-side (`lib/openingBalanceCsv.ts`), shows a preview, then applies.
  - **Employee Leave tab:** "Set opening balance" and "Adjust balance" actions
    (`dashboards/shared/LeaveBalanceActions.tsx`).
- Tests: `backend/app/tests/modules/test_leave_opening_balance.py`.
- **Merge note:** when `feature/gowtham_LeaveMasters` later merges to `main`, the same change
  arrives twice. Git normally drops the duplicate, but check `EmployeeLeaveTab.tsx`.

## Part B — Record already-taken leave on an employee's behalf

### Backend: `POST /api/v1/leave/employees/{employee_id}/requests/record`
Put it on the existing leave `EncryptedRoute` router. Gate it with
`RequirePermission("UPDATE", "LEAVE")` plus `_require_admin(db, principal)`, the same tier as
`/ledger/adjust` and `/ledger/opening`. It bypasses policy gates, so a reporting manager must not
get it through `_require_manager_or_admin_for`.

**Body** (`LeaveRequestRecordIn`):
`{leave_type_master_id, from_date, to_date, from_half?, to_half?, reason (required, min 1), dry_run: bool = false}`.

**Service** `record_leave_on_behalf(db, principal, employee_id, payload)`. Model it on
`apply_for_leave` and do not fork the gate logic:
1. Resolve the target employee with `_get_employee_in_tenant` (`:172`, raises `NotFound`
   cross-tenant). Resolve the leave type with `_get_leave_type`.
2. Resolve the policy with `resolution.resolve_policy_detail`, then the year with
   `resolve_leave_year`. Call `ledger_service.lock_ledger(...)` before any balance read.
3. **Gates.** Run `_evaluate_apply_gates` (`:1309`) with a way to skip some of them, such as a
   `skip: set[str]` param. Do not copy the function.
   - **Skip:** `min_notice_days` (this also covers back-dating), `max_consecutive_days`,
     `probation`.
   - **Keep:** `tenancy`, `type_in_force`, `gender`, `date_sanity` (joining/relieving date),
     `overlap` (`validate_no_overlap :932`), `insufficient_balance`.
   - If the balance is insufficient, refuse. The UI tells HR to load the opening balance first
     (Part A) or to pick the LOP type.
   - Reject `to_date > today`. Future leave goes through the normal apply flow.
4. **`dry_run=true`:** return the preview and write nothing. The preview has `total_days`, the
   day rows (week-off/holiday zeros included), `available_balance`, `balance_after`, and every
   violation, not just the first.
5. **Otherwise:**
   - Insert the `LeaveRequestDetail` with `status="Approved"` and `status_master_id` (dual-write),
     `approver_user_id = principal.user.id`, `actioned_at = now()`, and
     `created_by_id = principal.user.id`.
   - Insert the `LeaveRequestDayDetail` rows from `result.day_rows`.
   - Call `write_availed_ledger_rows` (`:1417`). It writes one negative `Availed` row per leave
     year, linked to the request.
   - Add two audits: `CREATED`, then `APPROVED` with `changes="Recorded by HR on behalf"`.
   - For every affected date, call `recompute_attendance_day`, the same as
     `approve_leave_request` (`:2010`, recompute at `:2084`). This turns past `Absent` days into
     `OnLeave`.
   - Send `_notify_approved` so the employee sees it.
   - Log at INFO with the employee, type, dates, days and acting user. Log at WARNING when a gate
     refuses.
6. Return `LeaveRequestOut` plus `attendance_dates_rebuilt`, the same as the approve response.

A recorded request is a normal Approved request. Reversing it later uses the existing
manager-reversal/cancel paths, so nothing new is needed for undo.

**Ordering with Part A.** An `Opening` row is effective at the as-of date. Leave recorded before
that date would be double-counted, because the old system's balance already reflects it. If
`from_date` is earlier than an existing `Opening` row's `effective_date` for that employee, leave
type and year, refuse with a clear message: "already reflected in the opening balance as of
dd-MMM-yy".

### Frontend
- `lib/api.ts`: add `recordLeaveOnBehalf(employeeId, body)`. Use `secureFetch`.
- `dashboards/shared/LeaveBalanceActions.tsx` + `EmployeeLeaveTab.tsx`: add a **"Record leave
  taken"** action next to "Adjust balance". Show it only with `UPDATE LEAVE`, using the same
  `usePermission` check the Part A actions use.
- **Modal** (`px-5 py-4` chrome):
  - Fields: leave type, from/to with half-day selects (`DateField`, `max = today`), and a
    required reason.
  - On change, fetch the dry run. Show the day breakdown, the balance before and after, and any
    violation inline.
  - Submit goes behind `useConfirm`. On success, refresh the balances, ledger and request history.
- House rules: dd-MMM-yy dates, shimmer skeleton for the preview body, Tailwind only.

## Not in scope
- **Bulk/CSV import of historic leave *requests*** (a day-by-day leave history). That is task 173,
  the attendance-history import. It adds `source`/`ledger_effect` on `leave_request_details` via
  task 170. If those columns exist when Part B lands, set `source='HR'`. Don't add them here.
- Making `max_backdated_leave_days` a tenant setting.
- Letting reporting managers record leave.

## Files
- **Part A** (ported): `backend/app/modules/leave/opening_balance_service.py`,
  `backend/app/modules/leave/{router.py,schemas.py}`,
  `backend/app/services/leave_accrual_service.py`,
  `backend/app/tests/modules/test_leave_opening_balance.py`,
  `frontend/src/dashboards/hrAdmin/Leave_components/{OpeningBalanceImportModal.tsx,PolicyAssignments.tsx}`,
  `frontend/src/dashboards/shared/{EmployeeLeaveTab.tsx,LeaveBalanceActions.tsx}`,
  `frontend/src/lib/{api.ts,openingBalanceCsv.ts}`, and the leave docs.
- **Part B:**
  - `backend/app/modules/leave/{router.py,schemas.py,service.py}`
  - `backend/app/tests/modules/test_leave_record_on_behalf.py` (new)
  - `frontend/src/lib/api.ts`
  - `frontend/src/dashboards/shared/{LeaveBalanceActions.tsx,EmployeeLeaveTab.tsx}`
  - Docs: `docs/leave-and-attendance/leave/api-and-pages.md` (the endpoint) and `ledger.md` §6
    (the gates the HR path skips, plus the Opening-date rule).

## Acceptance criteria
### Part A
- [x] Commit `6af117ab` cherry-picked onto `feature/gowtham_HistoricLeave` with its conflict resolved.
- [x] `npx tsc --noEmit` shows no new errors. The only errors are the existing missing
      `html2canvas`/`jspdf` modules.
- [x] `test_leave_opening_balance.py` passes on this branch (throwaway Postgres): 44 passed with
      `test_leave_policy_assignments.py`. Its `admin_token` fixture had to switch from
      `users.is_admin` to `set_admin_grid`, because `main` gates Leave on the grid alone.
- [ ] Smoke test: bulk CSV import preview, then apply. The balances show on the employee's
      Leave tab.

### Part B
- [x] HR records CL for 2 past days (a Mon–Tue last week). This creates 1 Approved request with
      `total_days=2`, 2 day rows and one `Availed` ledger row of −2 linked to the request. The
      attendance for both dates recomputes to `OnLeave`.
- [x] A range spanning a week-off on a type that excludes week-offs gives a 0 fraction for that
      day and the correct `total_days`.
- [x] A half day (`from_half=SecondHalf` on a single day) gives a 0.5 debit.
- [x] The preview endpoint returns the preview and writes no request, day, ledger or audit rows.
- [x] `to_date` in the future → 422. Overlap with an existing Approved/Pending request on a date
      → 422, and nothing is written.
- [x] Insufficient balance on a paid type → 422. The same dates on the LOP type succeed.
- [x] `from_date` before the employee's `Opening` effective date for that type and year → 422.
- [x] Back-dated beyond the notice/back-date gate succeeds here, while the self-service apply
      for the same dates still returns 422.
- [x] Without `UPDATE LEAVE` → 403. A reporting manager who is not an admin → 403. An employee
      from another CDP → 404, and nothing leaks.
- [x] Encrypted round-trip test for the new route.
- [ ] Modal: preview updates as fields change, submit refreshes the tab, and the employee gets
      the approved notification.

## Progress (08-Oct-26)
**Backend and frontend for Part B are built. They are uncommitted on `feature/gowtham_HistoricLeave`.**

Two changes from the plan above:
- **Two endpoints instead of a `dry_run` flag.** `POST …/requests/record/preview` returns
  `LeaveRequestPreviewOut`. `POST …/requests/record` returns `LeaveApproveResultOut` (201). This
  mirrors `/requests/preview` + `/requests`, so neither response shape is new.
- **The modal is preview-then-record, not `useConfirm`.** This matches the sibling
  "Set opening balance" modal. HR sees the day breakdown, the balance before and after, and any
  violation before the Record button is enabled.

What was built:
- `service.py`:
  - `_evaluate_apply_gates` takes `skip: frozenset[str]`.
  - New `_evaluate_record_gates`, `preview_record_on_behalf`, `record_leave_on_behalf`.
  - Helpers `_preview_out` and `_approve_result_out`, now shared with self-service preview and
    approve.
- `schemas.py`: `LeaveRequestRecordIn`.
- `router.py`: the two routes, gated with `_UPDATE` plus `_require_admin`.
- Tests: `test_leave_record_on_behalf.py` has 13 tests, all passing.
  - The leave, attendance and authz suites show **no new failures** against a baseline run with
    the changes stashed (44 failures both ways, all pre-existing on the throwaway DB).
  - The throwaway DB needed `seed_leave_request_status_masters.py` and
    `seed_attendance_status_masters.py`, run after inserting one user.
- Frontend:
  - `lib/api.ts`: `previewRecordLeave` and `recordLeaveOnBehalf`.
  - `LeaveBalanceActions.tsx`: `RecordLeaveModal`.
  - `EmployeeLeaveTab.tsx`: the "Record leave taken" action.
  - `tsc` shows no new errors.
- Docs: `api-and-pages.md` (the two rows) and `ledger.md` §6.4.

Still open: the modal smoke test in a running app, and the Part A UI smoke test.


Completed: 2026-10-13
