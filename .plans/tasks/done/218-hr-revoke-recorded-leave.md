---
task: 218
title: HR revokes (deletes) a "Record leave taken" entry — reverses the ledger, cancels the request, rebuilds attendance
status: done
depends_on: [217]
---

# 218 — Revoke an HR-recorded leave

**Clone:** use the same clone and branch as task 217. Paths are relative to `hrms/`.

## Why
"Record leave taken" (task 197, `service.record_leave_on_behalf`, `POST
/leave/employees/{id}/requests/record`) writes three things:
- an **Approved `leave_request_details`** row and its day rows;
- **`Availed` ledger rows**, one per leave year touched (`write_availed_ledger_rows`);
- an **attendance rebuild** of those dates to `OnLeave` (`recompute_attendance_day`).

If HR records leave for the wrong employee, or for days the employee actually worked, nothing
undoes it:
- `cancel_my_request` refuses a request whose days are all past ("already been fully taken"),
  and recorded leave is always past;
- 217's Delete deliberately excludes `Availed` rows, because voiding only the ledger would
  leave the request Approved and attendance still `OnLeave`.

Task 207 (edit = re-record) lists "Revoke recording" as a later task. This is that task: the
**Delete** button on a recorded-leave ledger row removes the whole recording.

## Recognising a recorded request
`LeaveRequestDetail` has no source column. `record_leave_on_behalf` writes `CREATED` and
`APPROVED` `LeaveRequestAudit` rows with `changes="Recorded by HR on behalf"` (`service.py:~2364`).
- Make that string a module constant, `RECORDED_ON_BEHALF_NOTE`, and use it at the write site.
  Task 207 plans the same constant: whichever task lands first adds it, and the other reuses it.
- A request is "recorded" when it has an audit row with `action='CREATED'` and
  `changes=RECORDED_ON_BEHALF_NOTE`.
- On the read path, load the recorded request ids for the employee in **one batched query**.

`voidable_kind` (from 217) returns `"recorded_leave"` for an `Availed` row when **all** of these
hold:
- its `leave_request_detail_id` is a recorded request;
- that request is `Approved` and not archived;
- no Availed row of that request sits in a closed leave year (a `LapseExpiry` exists for that
  type and year).

`LeaveLedgerRowOut` gains `leave_request_detail_id` if 207 hasn't already added it.

## Backend
### `POST /api/v1/leave/employees/{employee_id}/requests/{request_id}/record/revoke`
- Put it on the leave EncryptedRoute router. Gate it with `dependencies=[_DELETE]` plus
  `service._require_admin(db, principal, "DELETE")`, the same tier as 217.
- **Body** `LeaveRecordRevokeIn`: `{remarks: str (min_length=1), dry_run: bool = False}`.
- **Response** `LeaveRecordRevokeResultOut`:
  - `{dry_run, request_id, leave_type_master_id, from_date, to_date, days,`
  - `ledger: list[{leave_year, quantity_reversed, balance_before, balance_after}],`
  - `attendance_dates: list[date], warnings: list[str]}`.

### Service: `reverse_recorded_request(...)`, shared with task 207
Put it in `ledger_edit_service.py`, or beside `record_leave_on_behalf`. Signature:
`reverse_recorded_request(db, principal, request, *, source, audit_action, audit_note)`. It
does no commit. Task 207's re-record calls it with `source='EDIT'`; this task calls it with
`source='VOID'`. If 207 has already landed with an inline reversal, extract that into this
helper instead of writing a second copy.

`revoke_recorded_leave(db, principal, employee_id, request_id, payload)`:
1. `_require_admin(…, "DELETE")` and `_get_employee_in_tenant`. Load the request scoped to the
   tenant and the employee. Anything else is a **404**.
2. Guards (each a 422 plus a WARNING log):
   - a request that isn't recorded → "Only leave recorded by HR can be deleted here — the
     employee cancels leave they applied for";
   - a request that isn't `Approved` (already Cancelled or Rejected) → "This leave is already
     cancelled";
   - any of its Availed rows is in a closed leave year → "Leave year 2025–26 is closed — use
     Adjust balance".
3. Lock each (type, year) ledger key the request touched, in **sorted order**.
4. `reverse_recorded_request`:
   - writes one `Reversal` per `Availed` row with `quantity = −availed.quantity` (the row is
     negative, so the reversal is a credit), `reversal_of_id = availed.id`,
     `leave_request_detail_id = request.id`, the same `effective_date`, and `source='VOID'`;
   - sets the request to `status='Cancelled'`, dual-writing `status_master_id` the same way
     `cancel_my_request` does, with `cancelled_at` / `cancelled_by_id`;
   - writes a `LeaveRequestAudit` row with `action='REVOKED'` and `changes=<HR's reason>`.
5. Recompute attendance (`recompute_attendance_day`) for every date the request covered, so
   those dates stop being `OnLeave` and fall back to punches, Absent, holiday or week-off.
6. `log_activity(action_type="DELETE", action_path="leave/requests/record/revoke",
   deleted_data={request_id, employee_id, leave_type, from_date, to_date, days, reason})`.
7. `dry_run` → run the guards and compute the result, write nothing, and skip step 5.
   Otherwise `db.commit()`, then log INFO (request, employee, days, years, by whom).
8. If the leave module has an existing "leave cancelled" employee notification, send it.
   Otherwise send nothing. Don't add a new template in this task.

### Read side (extends 217)
- An Availed row fully reversed by a `VOID` reversal is **voided**, the same as 217: hidden by
  default in the HR view behind "Show deleted (n)", and omitted from `/me/ledger`.
- The `VOID` reversal folds into its row like 217's. A cancel's own reversals (no `source`) are
  untouched and still list as today.
- `void_kind="recorded_leave"` appears only for a DELETE LEAVE holder.

## Frontend
- **`lib/api.ts`:** add `revokeRecordedLeave(employeeId, requestId, {remarks, dry_run})`
  through `secureFetch`, and `leave_request_detail_id` on `LeaveLedgerRow` if it isn't there.
- **`EmployeeLeaveTab.tsx`:** 217's `[🗑 Delete]` row button on a `void_kind ===
  "recorded_leave"` row opens **`RevokeRecordedLeaveModal`**. There is no separate column.
- **`RevokeRecordedLeaveModal`** in `LeaveBalanceActions.tsx`, on `ModalShell`:
  - **Summary:** leave type, "03-Oct-26 → 04-Oct-26 · 2 days", recorded by and on.
  - **"Reason for deleting"**, required.
  - **Preview** (dry run) lists the balance change per leave year ("Casual 2026–27: 3.00 →
    5.00") and "Attendance for 03-Oct-26, 04-Oct-26 will be recalculated".
  - **Delete**: a red primary button, enabled after a successful preview. It applies, then
    reloads the ledger **and** the Requests card, where the request now shows Cancelled.
- House rules as in 217.

## Not in scope
- Self-applied leave. The employee cancels it through the normal flow, so it is never deletable
  here.
- Partial revoke (some of the days). Use 207's Edit to shorten the recording.
- Revoking in a closed leave year.

## Files
- `backend/app/modules/leave/{service.py,ledger_edit_service.py,router.py,schemas.py}`
- `backend/app/tests/modules/test_leave_ledger_void.py` (extend from 217) and/or
  `test_leave_record_on_behalf.py`
- `backend/app/tests/modules/test_authz.py`
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/shared/{EmployeeLeaveTab.tsx,LeaveBalanceActions.tsx}`
- Docs: in `docs/leave-and-attendance/leave/ledger.md`, extend 217's "Deleting an entry" with
  revoking recorded leave. Also update `api-and-pages.md`.

## Progress (12-Oct-26)
- Built on `feature/gowtham_LedgerVoid` in top-level `hrms/`, on top of 217's uncommitted work.
  Not committed yet.
- **Backend done:**
  - `service.RECORDED_ON_BEHALF_NOTE` is now used at the write site.
  - New in `ledger_edit_service`:
    - `recorded_request_ids` and `_revocable_availed`, which mark the read path with
      `void_kind="recorded_leave"` (only for DELETE LEAVE holders);
    - `reverse_recorded_request(…, source, audit_action, audit_note)`, shared with 207;
    - `revoke_recorded_leave`.
  - `POST /employees/{id}/requests/{request_id}/record/revoke` (`_DELETE`). Its body reuses
    `LeaveLedgerVoidIn`, and it returns `LeaveRecordRevokeResultOut`.
  - `LeaveLedgerRowOut.leave_request_detail_id` is added.
  - No notification is sent, because no employee-facing cancelled template exists.
- **Tests:**
  - `test_leave_record_revoke.py` (new) has 13 cases, including the cross-leave-year one.
  - The leave ledger suites together give 94/94 on a throwaway pg:18.
  - The leave, authz, employee-leave-policy and attendance-recompute suites give 565 passed and
    11 failed. The same 11 fail on untouched `origin/main` (environment).
- **Frontend done:**
  - `revokeRecordedLeave` and `RevokeRecordedLeaveModal`. The summary comes from the tab's
    request list; the preview shows per-year balances and the attendance dates.
  - Delete on a `recorded_leave` row opens that modal.
  - `tsc` is clean. ESLint shows only the pre-existing `set-state-in-effect`.
  - The preview labels the year as the raw `leave_year` (e.g. "Balance 2026"), not "2026-27".
- **Docs done:** `ledger.md` §10.4 plus a §4 row, `api-and-pages.md`, `gaps.md`, and
  `roles-and-permissions.md` §7.
- **Shipped for review (12-Oct-26):** commit `0fe841f` (217 and 218 together). The user merged `main` in (`bd38f58`) and pushed. Bitbucket PR #159 → `main`: https://bitbucket.org/NanoHealth_India/hrms/pull-requests/159. After the merge, tsc is clean and the tests give 565 passed and 11 failed, the same 11 environment failures as main.
- **Remaining:** the rest of the UI checks below. One Opening delete (row 12540) was already done by the user through the UI against the local API. Then merge #159 and move this file to `done/`.

## Acceptance criteria
- [ ] Record 2 days of CL (03–04 Oct), then revoke it:
  - the request is `Cancelled` with a `REVOKED` audit row carrying the reason;
  - one `Reversal` (+2, `source='VOID'`, `reversal_of_id` = the Availed row) is written, and
    `get_balance` is back where it was before the recording;
  - attendance for 03 and 04 Oct is no longer `OnLeave`;
  - one `user_activity_details` row is written.
- [ ] A recording that spans a leave-year boundary → one reversal per year. Both keys are locked
      in sorted order.
- [ ] 422 cases:
  - a self-applied request;
  - an already-cancelled request;
  - a closed leave year;
  - an empty reason.
- [ ] 404 for another tenant's or another employee's request. 403 without DELETE LEAVE (the HR
      Manager default grid). 401 without a token. Encrypted round-trip test.
- [ ] `dry_run` writes nothing (ledger, request, audit, attendance and activity are all
      unchanged).
- [ ] The HR ledger hides the voided Availed row by default and shows it under "Show deleted".
      `/me/ledger` omits it. The last folded `balance_after` equals `get_balance`.
- [ ] `void_kind="recorded_leave"` never appears on self-applied leave rows.
- [ ] UI: Delete on a recorded-leave row → the preview shows the per-year balance and the
      attendance dates → Delete refreshes the ledger and the requests.
- [ ] pytest is green for the leave test modules and `test_authz.py`. Frontend `lint` and `tsc`
      are clean.

Completed: 2026-10-13
