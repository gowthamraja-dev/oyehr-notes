---
task: 220
title: HR applies for leave on an employee's behalf — Pending to the approver, or "Approve now"
status: done
depends_on: []
---

# 220 — HR applies for leave on an employee's behalf

Build this in the **top-level `hrms/`** clone, on a new branch cut from `origin/main` (e.g.
`feature/gowtham_ApplyLeaveOnBehalf`). Paths and line numbers are relative to `hrms/` on
`origin/main` as of 13-Oct-26. Task 197 ("Record leave taken") is already on `main` and is
the model for this task.

## Why
Today only the employee can apply for leave. `apply_for_leave` (`backend/app/modules/leave/service.py:1461`)
resolves the employee with `_require_self_employee`. Employees without the app, or without
access that day, have to ask HR, and HR has no way to file the application for them.

"Record leave taken" (task 197) doesn't cover this. It accepts **past dates only** (`future_date`
violation), skips the policy gates, and always writes an Approved request.

This task adds a sibling action, **"Apply leave"**. HR files a normal leave application for the
employee, for today or a future date, under **the same policy gates the employee's own apply
runs**. HR then chooses the outcome:
- **Default: Pending.** The request goes to the employee's resolved approver, exactly as if the
  employee had applied.
- **"Approve now":** HR is the approver of record. The request is approved in the same
  transaction, so the `Availed` debit and the attendance rebuild happen right away.

## Decisions (user, 13-Oct-26)
- **Outcome:** HR picks at submit. Pending by default, with an "Approve now" checkbox.
- **Gates:** **all** self-service gates apply: notice, back-dating, max consecutive days,
  probation, balance, overlap, gender, type in force, joining/relieving dates. Past dates the
  notice gate refuses go through **Record leave** (the message says so). This task does **not**
  add a gate-skip list.
- **Clone:** top-level `hrms/`.

## Backend

### Endpoints
Add both to the existing leave `router` (`EncryptedRoute`, `backend/app/modules/leave/router.py`), next
to the `/requests/record` pair (`:408-427`). They mirror `/requests/preview` + `/requests`.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/leave/employees/{employee_id}/requests/apply/preview` | `LeaveRequestOnBehalfPreviewIn` | `LeaveRequestPreviewOut` (200, writes nothing) |
| POST | `/leave/employees/{employee_id}/requests/apply` | `LeaveRequestOnBehalfIn` | `LeaveRequestOnBehalfOut` (201) |

**Permission.** Use route dependency `_UPDATE` (`RequirePermission("UPDATE", "LEAVE")`) plus
`_require_admin(db, principal)` in the service, the same tier as `/requests/record`.
- **Do not gate on `CREATE LEAVE`.** The default Employee grid has `LEAVE: [READ, CREATE]`
  (`roles/defaults.py`), so a CREATE gate would let any employee file leave for anyone.
- `approve_now=true` also needs `_require_admin(db, principal, "APPROVE")`. Check it in both
  preview and apply, so the preview never offers an outcome the submit would refuse.
- The defaults give HR Admin `LEAVE: all` and HR Manager `LEAVE: [READ, UPDATE, APPROVE]`, so
  both get both. Reporting managers who aren't HR get neither: this is not
  `_require_manager_or_admin_for`.

### Schemas (`backend/app/modules/leave/schemas.py`)
```python
class LeaveRequestOnBehalfPreviewIn(LeaveRequestPreviewIn):
    approve_now: bool = False          # changes which gates apply (see below)

class LeaveRequestOnBehalfIn(LeaveRequestApplyIn):   # reason (min 1) + contact_during_leave
    approve_now: bool = False
    approver_remarks: str | None = Field(default=None, max_length=500)

class LeaveRequestOnBehalfOut(LeaveRequestOut):
    ledger_entries: list[LeaveLedgerEntryOut] = []      # empty when Pending
    attendance_dates_rebuilt: list[date] = []           # empty when Pending
```
If extending `LeaveRequestOut` gets awkward, returning `LeaveRequestOut` for the Pending path
and `LeaveApproveResultOut` for the approved path is also fine. Pick one and document it in
`api-and-pages.md`. The frontend only needs `status` plus enough to refresh.

### Service (`backend/app/modules/leave/service.py`)
Add a section "Admin: apply for leave on an employee's behalf (task 220)" after the task 197
block (`:2256+`). **Don't fork `apply_for_leave` or `approve_leave_request`.** Extract the
shared pieces they need.

1. **`_evaluate_on_behalf_gates(db, tenant_id, employee, leave_type, payload, approve_now)`**:
   - Call `_evaluate_apply_gates(...)` (`:1316`). Pass `skip=frozenset({"approver"})` when
     `approve_now`, because HR is the approver. Pass no skip otherwise, so a missing approver
     is a violation, as in self-service.
   - When `approve_now` and the leave type needs a document
     (`requires_document` and `total_days > doc_required_after_days`, or the threshold is
     None): add a violation, code `document_required`, message "This leave type needs a
     supporting document before approval — submit it as Pending and attach the document
     first". Factor the threshold check out of `validate_document` (`:1011`) as
     `document_required(leave_type, total_days) -> bool` and use it in both places. The
     on-behalf request has no attachment yet.
   - When the `min_notice_days` violation is present **and** `from_date < today`, change its
     message to add: "For leave already taken, use Record leave." This changes the message
     only, never the outcome.
2. **`preview_apply_on_behalf(db, principal, employee_id, payload)`**:
   - Call `_require_admin`, and `_require_admin(…, "APPROVE")` if `approve_now`.
   - Resolve the employee with `_get_employee_in_tenant` (404 cross-tenant) and the type with
     `_get_leave_type`.
   - Return `_preview_out(db, result)`.
3. **`apply_leave_on_behalf(db, principal, employee_id, payload)`**:
   - Same permission and resolution steps as the preview.
   - Resolve the policy and leave year, then call `ledger_service.lock_ledger(...)` **before**
     the gates, as `apply_for_leave` does (`:1467-1471`).
   - On violations: log WARNING (employee, type, tenant, acting user, first code and message),
     then raise 422 with the first message.
   - Insert `LeaveRequestDetail`, the `LeaveRequestDayDetail` rows and a `CREATED` audit.
     **Extract** the insert block that `apply_for_leave` (`:1486-1510`) and
     `record_leave_on_behalf` (`:2348-2370`) both repeat into
     `_insert_request(db, tenant_id, employee, leave_type, payload, result, *, status, approver, created_by_id)`.
     Use it from all three.
     - `created_by_id = principal.user.id` (HR). `employee_master_id` = the target.
     - Audit `CREATED` with `changes=APPLIED_ON_BEHALF_NOTE`, a new module constant
       `"Applied by HR on behalf"`.
     - **Keep it distinct from `RECORDED_ON_BEHALF_NOTE`.** Task 218's
       `revoke_recorded_leave` keys off that note. An HR-applied request is ordinary leave,
       undone through the normal employee cancel or manager reversal paths, never "revoke
       recorded".
   - **If `approve_now` is false:**
     - Set `status="Pending"` and `status_master_id` (dual-write).
     - Set the approver from `result.approver`. When `leave_type.requires_approval` is false,
       auto-approve as `apply_for_leave` gate 11 does (`:1512-1527`), and reuse that branch.
     - Commit, log INFO, then call `_notify_submitted` (the approver is pinged, as in
       self-service).
   - **If `approve_now` is true:**
     - Set `status="Approved"`, `status_master_id`, `actioned_at=now()`,
       `approver_user_id=principal.user.id`, `approver_employee_master_id` = the caller's
       employee (or None), and `approver_remarks`.
     - Call `write_availed_ledger_rows` (`:1417`).
     - Add an `APPROVED` audit (`changes=approver_remarks or APPLIED_ON_BEHALF_NOTE`).
     - Call `recompute_attendance_day` for each affected date. This is a no-op for future
       dates, but it is needed when the leave covers today.
     - Commit, log INFO, then call `_notify_approved`.
   - Return the result: the request out, plus ledger rows and rebuilt dates when Approved.

### Effects on existing flows (verify, don't change)
- The request shows in the employee's **My Leave** history like one they raised. They can
  cancel it while Pending, and cancel or withdraw it once Approved under the normal rules,
  because `employee_master_id` is theirs.
- A Pending request shows in the approver's queue (`manager-approvals.md`) and in HR's
  approval views. The approver approves or rejects it through the existing endpoints.
- Supporting documents: `upload_leave_attachment` (`:1856`) is self-only, so for a
  document-required type the **employee** attaches the document from My Leave before the
  approver approves. Letting HR attach is out of scope.

## Frontend
- **`lib/api.ts`:** add `previewApplyLeaveOnBehalf(employeeId, body)` and
  `applyLeaveOnBehalf(employeeId, body)` via `secureFetch`, typed next to
  `previewRecordLeave`/`recordLeaveOnBehalf`.
- **`dashboards/shared/LeaveBalanceActions.tsx`:** add an `ApplyLeaveOnBehalfModal` next to
  `RecordLeaveModal` (`:643`), using the same `ModalShell` and preview-then-submit pattern. Share
  the field/preview rendering with `RecordLeaveModal` (extract a common body component)
  instead of copying ~100 lines.
  - Fields:
    - leave type
    - From/To with half-day selects (`DateField`, **`min = today`**, no max)
    - reason (required)
    - contact during leave (optional)
    - an **"Approve now"** checkbox, rendered only when `usePermission("APPROVE", "LEAVE")`
    - approver remarks (optional), shown only when "Approve now" is ticked
  - Re-run the preview when any field changes, **including the checkbox**, because it changes
    the approver and document gates. Show the day breakdown, balance before and after, and
    every violation inline. The submit button stays disabled while there are violations.
  - Submit label: "Submit for approval", or "Apply & approve" when the box is ticked. The
    success toast says which outcome happened ("Sent to <approver> for approval" /
    "Approved").
  - House rules: modal chrome `px-5 py-4`, dd-MMM-yy dates, shimmer skeleton for the preview
    body, Tailwind only.
- **`dashboards/shared/EmployeeLeaveTab.tsx`:** add an **"Apply leave"** button next to "Record
  leave" (`:407`), shown under the same `canUpdate` (`UPDATE LEAVE`) condition. Its
  `setAction("apply")` opens the modal. On success, refresh balances, the ledger and request
  history, the same as `RecordLeaveModal`'s `onDone`.
- Copy: the two buttons need distinct tooltips. "Record leave" is for days already taken;
  "Apply leave" is for upcoming leave, which follows the leave policy.

## Not in scope
- An "Apply on behalf" entry point with an employee picker on the HR leave-approvals page
  (follow-up if HR wants it outside the employee profile).
- HR uploading the supporting document on the employee's behalf.
- A new notification telling the employee that HR applied for them. They see it in My Leave,
  and get `LEAVE_REQUEST_APPROVED` on approval.
- Relaxing any policy gate for HR, and any change to Record leave (197) or revoke (218).
- The mobile app.

## Files
- `backend/app/modules/leave/{router.py,schemas.py,service.py}`
- `backend/app/tests/modules/test_leave_apply_on_behalf.py` (new; model it on
  `test_leave_record_on_behalf.py`)
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/shared/{LeaveBalanceActions.tsx,EmployeeLeaveTab.tsx}`
- Docs:
  - `docs/leave-and-attendance/leave/api-and-pages.md`: the two endpoints and the Employee
    Leave tab action
  - `ledger.md` §6: on-behalf apply runs every gate, approve-now skips only `approver` and
    adds `document_required`
  - `manager-approvals.md`: an HR-filed request lands in the queue like any other

## Acceptance criteria
- [x] HR files CL for next Mon–Tue without "Approve now". This gives 1 **Pending** request with
      `total_days=2`, 2 day rows, **no** ledger row, `created_by_id` = HR,
      `approver_employee_master_id` = the employee's reporting manager, and a `CREATED` audit
      with the on-behalf note. The manager gets `LEAVE_REQUEST_SUBMITTED`, and the employee's
      available balance shows the pending commitment.
- [x] The same request with "Approve now": **Approved**, one `Availed` −2 ledger row linked to
      it, `approver_user_id` = HR, CREATED + APPROVED audits, and `LEAVE_REQUEST_APPROVED` to
      the employee.
- [x] Approve now covering **today**: today's attendance recomputes to `OnLeave`.
- [x] A leave type with `requires_approval=false` without the box: auto-approved, same as
      self-service.
- [x] Gates match self-service: a notice-period breach, a past date (message mentions Record
      leave), more than max consecutive days, probation, insufficient balance, overlap with a
      Pending/Approved request, and the wrong gender each → 422 with nothing written. For each,
      the preview lists the violation and returns 200.
- [x] Without the box, an employee with no resolvable approver → 422 "No approver could be
      resolved". With the box → succeeds.
- [x] A document-required type over the threshold with the box → 422 `document_required`.
      Without the box → Pending.
- [x] The employee cancels an HR-filed Pending request from their own cancel endpoint → 200.
      The approver approves an HR-filed Pending request through the existing endpoint → 200,
      and the debit happens.
- [x] Revoke-recorded (218) refuses an HR-applied, approved-now request (the note differs).
- [x] Permissions:
  - [x] Employee-grid user (READ, CREATE) → 403 on both endpoints.
  - [x] Non-HR reporting manager → 403.
  - [x] UPDATE without APPROVE with `approve_now=true` → 403. The same user without the box
        → 201.
  - [x] Employee from another CDP → 404, with nothing leaked.
- [x] Encrypted round-trip test for the new route.
- [x] Preview writes no request, day, ledger or audit rows.
- [x] Existing suites (`test_leave.py`, `test_leave_record_on_behalf.py`,
      `test_leave_record_revoke.py`, `test_authz.py`) show no new failures against a baseline
      run (throwaway Postgres, see the hrms-tests memory).
- [x] `npx tsc --noEmit` and lint show no new errors.
- [ ] Smoke test on the dev stack: the "Apply leave" modal updates its preview as fields and
      the checkbox change. A Pending submission appears in the manager's queue and in the
      employee's My Leave. An approve-now submission debits the balance on the Leave tab.

## Progress (13-Oct-26)
**The backend, frontend and docs are built. They're uncommitted on `feature/gowtham_ApplyLeaveOnBehalf`,
cut from `origin/main` @ `fa3c044`.** All boxes except the smoke test are ticked.

Changes from the plan:
- **Response shape:** `LeaveRequestOnBehalfOut` extends `LeaveRequestOut` with `ledger_entries`
  and `attendance_dates_rebuilt`.
- **Modal flow:** it previews, then submits, using the same Preview button as `RecordLeaveModal`.
  Any field change, including "Approve now", clears the preview. There's no automatic preview
  on change.
- **No toast:** the tab has no toast system. The modal closes and the tab reloads, so the new
  request shows in the tab's request list with its Pending/Approved pill.
- **No `test_authz.py` entry:** the other admin leave routes (record, adjust, void) are covered
  in their own module tests and aren't in `test_authz.py` either. This one follows them.

What was built:
- **`service.py`:**
  - New: `needs_document` (the threshold half of the document gate, now shared by
    `validate_document` and `_document_required`), `_insert_request` (now shared by
    `apply_for_leave`, `record_leave_on_behalf` and the new path) and `_caller_as_approver`.
  - The task 220 block: `APPLIED_ON_BEHALF_NOTE`, `_evaluate_on_behalf_gates`,
    `_require_on_behalf`, `preview_apply_on_behalf` and `apply_leave_on_behalf`.
- **`schemas.py`:** `LeaveRequestOnBehalfPreviewIn`, `LeaveRequestOnBehalfIn` and
  `LeaveRequestOnBehalfOut`.
- **`router.py`:** the two routes.
- **Tests:** `test_leave_apply_on_behalf.py` has 23 tests, all passing on a throwaway Postgres.
  The leave, attendance and authz suites have the same 26 failures with and without the change,
  all pre-existing.
- **Frontend:**
  - `api.ts`: `previewApplyLeaveOnBehalf`, `applyLeaveOnBehalf` and their types.
  - `LeaveBalanceActions.tsx`: `LeaveRangeFields` and `LeavePreviewSummary` are extracted and
    now shared with `RecordLeaveModal`. New `ApplyLeaveOnBehalfModal`.
  - `EmployeeLeaveTab.tsx`: the "Apply leave" button, plus a 4th shimmer button for it.
- **Docs:** `api-and-pages.md` (the two rows), `ledger.md` §6.5 and `manager-approvals.md` §2.1.

Not done: the smoke test on the dev stack. The user marked the task done without it on 13-Oct-26.

Completed: 2026-10-13
