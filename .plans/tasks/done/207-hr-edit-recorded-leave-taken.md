---
task: 207
title: HR edits a "Record leave taken" entry (dates / halves / type) from the employee Leave tab ledger
status: done
depends_on: [206]
---

# 207 — Edit a recorded-leave ledger entry

Work in the **top-level `hrms/`** clone, not `workspace-2/`. Use the same branch as task 206.
Paths are relative to `hrms/`.

## Why
Task 206 adds **Edit** to the manual Opening and Adjustment rows. The third manual action,
**Record leave taken** (task 197, `service.record_leave_on_behalf`, `POST
/leave/employees/{id}/requests/record`), can't be fixed the same way, because it writes more than
a number:
- an **Approved `leave_request_details` row**, with its `leave_request_day_details`;
- **`Availed` ledger rows**: one per leave year touched (`write_availed_ledger_rows`);
- the **attendance rebuild** for those dates (`recompute_attendance_day` → `OnLeave`).

Changing only the Availed quantity would leave the request, its day rows and attendance saying
something else. And it can't be undone today. `cancel_my_request` refuses a request whose days
are all in the past ("already been fully taken"), and recorded leave is always in the past
(`future_date` gate).

So "edit" here means **re-record**. HR changes the leave type, the from/to dates, the halves or
the reason. The old recording is fully reversed and a new one is written in the same transaction.

## How to recognise a recorded request
`LeaveRequestDetail` has no source column. `record_leave_on_behalf` writes two
`LeaveRequestAudit` rows (`CREATED`, `APPROVED`) with `changes="Recorded by HR on behalf"`
(`service.py:~2370`).
- Make that string a module constant, `RECORDED_ON_BEHALF_NOTE`, and use it in both places.
- A request counts as recorded when an audit row has `action='CREATED'` and
  `changes=RECORDED_ON_BEHALF_NOTE`.
- No migration. If this proves fragile, a later task can add a `source` column to
  `leave_request_details`.

Extend 206's `editable_kind` so that an `Availed` row returns `"recorded_leave"` when **all** of
these hold:
- its `leave_request_detail_id` is a recorded request;
- that request is still `Approved` and not archived;
- the leave year of each of its Availed rows is open (no `LapseExpiry`).

Load the request ids in one batched query on the read path, not one query per row.
`LeaveLedgerRowOut` also gains `leave_request_detail_id`, so the modal can load the request.

## Backend
### Endpoints
Both go on the leave EncryptedRoute router and are gated by `_UPDATE` plus `_require_admin`, the
same as `/requests/record`.
- `POST /leave/employees/{employee_id}/requests/{request_id}/record/preview`: a dry run that
  writes nothing and always returns 200 (`LeaveRequestPreviewOut`).
- `PUT /leave/employees/{employee_id}/requests/{request_id}/record`: applies the edit and returns
  `LeaveApproveResultOut` for the **new** request.
- The body for both is `LeaveRequestRecordIn`, the same schema as recording:
  `{leave_type_master_id, from_date, to_date, from_half?, to_half?, reason}`.

### Service: `edit_recorded_leave(db, principal, employee_id, request_id, payload)`
Put it in `ledger_edit_service.py` from task 206, or beside `record_leave_on_behalf`.
1. `_require_admin`, `_get_employee_in_tenant`. Load the request scoped to the tenant and
   employee. Anything else is a **404**. Then:
   - a request that isn't recorded → 422 "Only leave recorded by HR can be edited here";
   - a request that isn't `Approved` → 422.
2. Before any read, **lock every ledger key touched**: the old request's Availed (type, year)
   pairs and the new one's resolved (type, year) pairs. Take them in **sorted order** so that two
   concurrent edits can't deadlock.
3. **Reverse the old recording in full.** If task 218 has landed, call its
   `reverse_recorded_request(..., source='EDIT', audit_action='EDITED', ...)` helper. Otherwise
   build that helper here so 218 can reuse it.
   - One `Reversal` per old `Availed` row: `quantity = −availed.quantity`,
     `reversal_of_id = availed.id`, `leave_request_detail_id = old.id`, `source = 'EDIT'`, effective
     date the same as the Availed row's.
   - Don't call `cancel_my_request`. It reverses only future days.
   - Set the old request to `status='Cancelled'`, dual-writing `status_master_id`, with
     `cancelled_at` and `cancelled_by_id`.
   - Add a `LeaveRequestAudit` row: `action='EDITED'`, `changes='Superseded by request #<new>'`.
   - Flush.
4. **Record the new one.** Extract `record_leave_on_behalf`'s body after its lock into a helper
   `_write_recorded_request(...)` and call that helper. Don't copy it.
   - Gates come from `_evaluate_record_gates`.
   - **The overlap gate must not see the old request.** It is already `Cancelled` in-session,
     but confirm that `validate_no_overlap` ignores Cancelled; otherwise pass `exclude_request_id`.
   - **The balance gate must count the reversed days as available again.** Gating after the
     reversal flush does this naturally.
   - Any violation → raise 422 with the first violation's message, which rolls back the whole
     transaction. The old recording stays intact.
5. Add audit on the new request: `CREATED`/`APPROVED` with `RECORDED_ON_BEHALF_NOTE`, plus
   `EDITED` with `'Edited from request #<old>'`.
6. Recompute attendance for the **union** of the old and new dates. Dates the leave no longer
   covers must stop being `OnLeave`.
7. Commit, then log INFO (old id → new id, dates, days, by whom). Send the employee the existing
   approved notification for the new request.

The preview runs steps 1–4 as a dry run. One way is a SAVEPOINT that is rolled back. The other
is evaluating the gates with the old request excluded and its days added back to the balance.
Pick one and note it in the code.

### Read-side folding (extends task 206)
- Old Availed rows that are fully reversed by `source='EDIT'` reversals have an effective value
  of 0. Leave them **and** their reversals out of the default ledger list.
- The new request's Availed rows show `edited=true`. `edits[]` is built from the `EDITED` audit
  chain: `{from old dates/days → new dates/days, reason, by, at}`.
- The running `balance_after` stays consistent, as in 206.

## Frontend
- **`lib/api.ts`:**
  - Add `previewEditRecordedLeave` and `editRecordedLeave` (`secureFetch`).
  - Add `leave_request_detail_id` to `LeaveLedgerRow`.
- **`EmployeeLeaveTab.tsx`:** the 206 `[✎ Edit]` row button on a `"recorded_leave"` row opens the edit modal,
  prefilled from the request (load it with the existing request-detail call, or carry it on the
  ledger row).
- **Modal:** turn `RecordLeaveModal` (`LeaveBalanceActions.tsx`) into a two-mode component, with
  `mode: "create" | "edit"` and `initial` values. Don't fork it.
  - The title changes to "Edit recorded leave", and the subtitle reads "Originally 03-Oct-26 →
    04-Oct-26 · 2 days".
  - Preview calls the edit preview. The button label is "Save changes".
- The Requests card already lists the old request as Cancelled and the new one as Approved. No
  change is needed there beyond an "Edited" chip on the new one, if it's cheap.

## Not in scope
- Editing leave the employee applied for themselves. Those rows are not editable. They go
  through the normal cancel flow.
- **Deleting a recorded leave outright.** There is no "remove" button. If it's needed, a later
  task can add a "Revoke recording" action on the same full-reversal path.
- Splitting or merging recorded requests.

## Files
- `backend/app/modules/leave/{service.py,router.py,schemas.py,ledger_edit_service.py}`
- `backend/app/tests/modules/test_leave_ledger_edit.py` (extend) and/or
  `test_leave_record_on_behalf.py`
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/shared/{EmployeeLeaveTab.tsx,LeaveBalanceActions.tsx}`
- `docs/leave-and-attendance/leave/ledger.md`: extend 206's "Editing a manual entry" section with
  the re-record flow. Also update `api-and-pages.md`.

## Acceptance criteria
- [ ] Record 2 days of CL (03–04 Oct) and edit it to 1 day (03 Oct).
  - The old request is `Cancelled` with an `EDITED` audit, and a new Approved request exists.
  - One full Reversal (+2) and one new Availed (−1) are written. Net balance +1 versus before
    the edit.
  - Attendance for 04 Oct is no longer `OnLeave`, and 03 Oct still is.
- [ ] Editing the leave type (CL → SL) debits SL and restores CL, with both ledger keys locked.
- [ ] Editing across a leave-year boundary splits Availed per year, as `write_availed_ledger_rows`
      does.
- [ ] A gate failure on the new values (overlap with another request, insufficient balance,
      future date, before the opening balance) returns 422 and leaves **nothing** changed. The
      old request stays Approved and the ledger is unchanged.
- [ ] `edit_kind="recorded_leave"` appears only on Availed rows of HR-recorded, still-Approved
      requests in an open year. Rows from self-applied leave never get it.
- [ ] The ledger API hides the fully-reversed old Availed row and its reversals. The new row
      shows `edited=true`, and the last balance equals `get_balance`.
- [ ] 404 for another tenant's or another employee's request. 403 without `UPDATE LEAVE` / not
      admin. 401 without a token. Encrypted round-trip test.
- [ ] Preview writes nothing.
- [ ] UI: the `[✎ Edit]` button on a recorded-leave row opens the prefilled modal, and Preview → Save
      refreshes the ledger and the requests.
- [ ] pytest is green for the leave test modules. Frontend `lint`/`tsc` are clean.

Completed: 2026-10-13
