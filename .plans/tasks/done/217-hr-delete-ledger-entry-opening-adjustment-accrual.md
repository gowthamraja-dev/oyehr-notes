---
task: 217
title: HR deletes (voids) an Opening balance, a manual Adjustment or an Accrual credit from the employee Leave tab ledger
status: done
depends_on: []
---

# 217 — Delete (void) a ledger entry: Opening / Adjustment / Accrual

**Clone:** 206 (merged, PR #151) and 207 were built in the top-level `hrms/` clone. Confirm which
clone to use at the start of the work, then cut a fresh branch from `origin/main`. Run
`git status -sb` first. Paths below are relative to `hrms/`.

## Why
Admin / HR on Employee profile → **Leave** tab → **Ledger** card
(`frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`) has these actions today:

| Action | Since | What it does |
| --- | --- | --- |
| Set opening balance | 165 | One `Opening` row per (employee, leave type), ever (`uq_leave_ledger_opening_once`) |
| Adjust balance | — | A signed manual `Adjustment` row |
| Record leave taken | 197 | An Approved request plus `Availed` rows plus attendance |
| Edit (row button) | 206 | Changes the value of an Opening or a manual Adjustment through an `EDIT` Reversal |

**Nothing can be removed.**
- A wrong Adjustment can only be cancelled by adding an opposite one. 206 refuses to edit an
  Adjustment to 0. The ledger then reads "+2 Adjustment, −2 Adjustment".
- A wrong Opening can be edited to 0, but it still shows as an "Opening balance 0.00" row.
- An **Accrual credited by mistake** is never editable. Examples: the wrong policy was
  assigned, the employee was credited during LOP or a notice period, or a joiner was credited
  before their probation ended. HR's only recourse is a negative Adjustment that nobody can trace
  back to the accrual it cancels.

This task adds a **Delete** action, gated on **DELETE LEAVE**, for those three kinds of row. It
also lets HR **edit** an Accrual's quantity through 206's Edit path, for example to fix a
wrong proration.

Revoking an HR-recorded leave (the 4th kind) is **task 218**. It also has to cancel the request
and rebuild attendance.

## Design: a delete is a full Reversal, never a SQL DELETE
`employee_leave_balance_ledgers` is append-only (`docs/leave-and-attendance/leave/ledger.md` §5.3).
Rows are never DELETEd, and `is_active` / `updated_at` are never touched. A delete ("void") is
the same shape as 206's edit, with a different `source`:

- One `Reversal` row through `ledger_service.write_ledger_entry`, under
  `ledger_service.lock_ledger(tenant, employee, type, leave_year)`:
  - `reversal_of_id` = the voided row;
  - **`quantity = −current_effective_value`**, so the row's effective value becomes 0;
  - **`source = 'VOID'`** (new value; the column is a free `String(20)`, with no check
    constraint, so **no migration**);
  - the same `leave_type_master_id`, `leave_year`, `effective_date` and `leave_policy_detail_id`
    as the original;
  - `leave_request_detail_id = NULL`;
  - `remarks` = HR's reason (required);
  - `created_by_id`.
- **Why not a hard DELETE.** It would break accruals:
  - A deleted Accrual row frees `uq_leave_ledger_accrual_period` (employee, rule, period).
  - `leave_accrual_service.grant_first_credits` (a 30-day catch-up sweep) and
    `process_onboarding` would then **credit it again**.
  - An `ONBOARDING` grant is "at most once" only because `_already_granted_on_joining` finds the
    row.
  - Keeping the row and reversing it keeps every idempotency key intact. Assert this in a test.
- **Effective value** becomes `original.quantity + Σ quantity of its EDIT and VOID reversals`.
  Generalise `ledger_edit_service.effective_quantities` and `is_edit_row` to
  `source IN ('EDIT', 'VOID')`. Add a module constant `VOID_SOURCE = "VOID"` beside `EDIT_SOURCE`.
- A row is **voided** when its latest correction is a VOID reversal and its effective value
  is 0.

## Which rows can be deleted / edited
Extend `ledger_edit_service.edit_kind` / `editable_kind`. These stay the single source of truth;
the read path and the write path both call them.

| Row | Recognised by | Edit (UPDATE LEAVE) | Delete (DELETE LEAVE) |
| --- | --- | --- | --- |
| Opening | `txn_type='Opening'`, `source='OPENING'` | yes (206) | **yes** |
| Manual Adjustment | `txn_type='Adjustment'`, `leave_request_detail_id IS NULL` | yes (206) | **yes** |
| Accrual (any source: `SCHEDULED`, `ONBOARDING`, catch-up) | `txn_type='Accrual'` | **yes (new, `edit_kind="accrual"`)** | **yes** |
| HR-recorded leave (`Availed`) | — | task 207 | task 218 |
| CarryForward / LapseExpiry | year-close | never: use Adjust | never |
| Availed / Reversal from apply, approve or cancel | — | never | never |
| Encashment | — | never (ties into payroll) | never |
| EDIT / VOID Reversal rows themselves | — | hidden (folded) | hidden |

Add a sibling to `editable_kind`: `voidable_kind(row, closed, effective) -> str | None`. It
returns the same kind, but None when the year is closed or the row is already voided
(effective value 0).

## Guards (each raises 422 and logs a WARNING with the values that failed it)
Run them in `void_ledger_entry` after the lock, the same as in `edit_ledger_entry`:
1. Tenant- and employee-scoped load. Another tenant's or employee's row is a **404**.
2. The row kind is not deletable → "This entry is system-generated and can't be deleted".
3. **The leave year is closed** (a `LapseExpiry` exists for employee, type, leave_year) →
   "Leave year 2025–26 is closed for this employee — use Adjust balance to correct the current
   balance".
   - Year close already settled the balance including this row. Voiding it now would leave the
     carry-forward/lapse wrong.
4. The row is already voided, or its effective value is already 0 → "This entry is already 0".
5. **Negative result:**
   - **Opening** → reject, the same as 206: "The employee has already used more than this
     balance — deleting it would leave … Record the shortfall with Adjust balance instead."
   - **Adjustment / Accrual** → allowed, but `warnings` carries "This leaves the balance at −1.00
     (negative)". The modal shows the warning in the preview before HR confirms. This is the
     clawback case: the leave was credited wrongly and has already been used.
6. `remarks` is empty → 422 (Pydantic `min_length=1`).

**Accrual edit guards** (206's `edit_ledger_entry`, new `kind == "accrual"` branch):
- `new ≥ 0`. Editing to 0 is allowed, but the UI steers that case to Delete.
- `new ≤` the rule's `max_balance` when it is capped. Reuse 206's check.
- Same closed-year rule and same no-change rule.
- A negative resulting balance comes back as a warning, not an error, like Adjustment.

## Backend
### `POST /api/v1/leave/employees/{employee_id}/ledger/{ledger_id}/void`
- Put it on the leave **EncryptedRoute** router, next to `/ledger/{ledger_id}/edit` (`router.py:~437`).
- Gate it with `dependencies=[_DELETE]` **and** `service._require_admin(db, principal, "DELETE")`
  (`require_grid_permission`, so a role with no grid is refused).
  - Default grids: Admin and HR Admin have DELETE LEAVE; HR Manager does **not**. A tenant
    enables it for HR Manager by ticking LEAVE → DELETE on Roles & Permissions. Don't change
    `defaults.py`.
- **Body** `LeaveLedgerVoidIn`: `{remarks: str (min_length=1), dry_run: bool = False}`.
- **Response** `LeaveLedgerVoidResultOut`: `{dry_run, ledger_id, txn_type, leave_type_master_id,
  leave_year, quantity_before, quantity_after (=0), delta, balance_before, balance_after,
  warnings: list[str]}`. This is the same shape as `LeaveLedgerEditResultOut`; subclass it or
  reuse it if the fields match exactly.
- **Service** `ledger_edit_service.void_ledger_entry(db, principal, employee_id, ledger_id,
  payload)`. Share the load/lock/closed-year/effective-value steps with `edit_ledger_entry`
  through a private helper. Don't copy them.
- When not a dry run:
  - write the Reversal;
  - **write an activity row**: `activity_log_service.log_activity(db, user_id=…, tenant_id=…,
    role_master_id=…, action_type="DELETE", action_path="leave/ledger/void",
    deleted_data={ledger_id, employee_id, txn_type, leave_type, leave_year, quantity_before,
    reason})` (hrms-activity-logging rule for every new deletion);
  - `db.commit()`;
  - log INFO: "Ledger row %s (%s) voided (was %s) for employee %s leave_type %s year %s, balance
    %s -> %s (tenant %s, by user %s)".

### Read side (`ledger_edit_service.ledger_rows`)
- VOID reversals fold into their row exactly like EDIT reversals. They are never listed on their
  own, and the folded `balance_after` stays a running sum whose last row equals `get_balance`.
- New `LeaveLedgerRowOut` fields (`backend/app/modules/leave/schemas.py`):
  - `voided: bool`;
  - `void_kind: Literal["opening", "adjustment", "accrual"] | None`. Non-null only on the
    employee endpoint, only when the **caller holds DELETE LEAVE** (one
    `require_grid_permission`-style boolean check per request, not per row), and only when
    `voidable_kind` allows it;
  - `edit_kind` gains `"accrual"`.
  - Voided rows put a `LedgerEditOut` entry with `quantity_after = 0` in `edits[]`. Add
    `kind: Literal["edit", "void"]` to `LedgerEditOut` so the popover can say "Deleted".
- **`/me/ledger` (employee self-service) omits voided rows entirely.** Their effective value is 0,
  so the running balance is unaffected. It never returns `edit_kind` / `void_kind`.
- **HR view returns voided rows.** The frontend hides them by default (see below).

### Opening after a void: "Set opening balance" re-opens it
The once-per-type index keeps the voided Opening row, so a second `Opening` insert is
impossible. Make re-entry work anyway:
- In `opening_balance_service` (single and bulk, `_type_history` / `_check_ledger`): when the
  existing Opening for (employee, type) is **voided**, treat the row as `ok`, not `conflict`.
  The message reads "Re-opens the deleted opening balance of 01-Apr-26".
- On apply, write an **`EDIT` Reversal** on that Opening for the new value. Do not insert a new
  Opening.
- The same open-year rule applies. If that year is closed, return `conflict` pointing at Adjust
  balance.
- The "already tracked in HRMS" rule (206) is unchanged.

## Frontend
- **`lib/api.ts`:** add `voided`, `void_kind` and `edit_kind: "accrual"` to `LeaveLedgerRow`,
  `kind` to the edit history entry, and
  `voidLedgerEntry(employeeId, ledgerId, {remarks, dry_run})` through `secureFetch`.
- **`EmployeeLeaveTab.tsx` Ledger card:**
  - `const canDelete = usePermission("DELETE", "LEAVE")`. The trailing actions column shows when
    `canUpdate || canDelete`.
  - In each row's action cell, put the existing `[✎ Edit]` button (when `row.edit_kind`) and a new
    **`[🗑 Delete]`** button (when `row.void_kind`):
    - the same compact secondary style, with red text/border on hover
      (`hover:text-red-700 hover:border-red-200`);
    - `aria-label="Delete entry"`.
  - Widen the column to fit two buttons (e.g. `w-[150px]`). Update `LedgerSkeleton`'s
    `gridTemplateColumns` and its `withActions` to match (shimmer rule: header and body share the
    grid).
  - **Voided rows are hidden by default.** Add a small toggle in the Ledger toolbar, "Show deleted
    (n)", shown only when n > 0. A shown voided row:
    - renders muted (`text-ink-400`);
    - shows its original quantity struck through (`line-through`);
    - has a "Deleted" chip (`bg-red-50 text-red-700 text-[10.5px] font-semibold rounded-full px-2
      py-0.5`);
    - has no Delete button. Edit stays only on a voided Opening (re-enter).
  - The history popover lists edits and the void: "1.50 → 0 · Deleted · reason · by <name> ·
    09-Oct-26" (`formatDDMMMYY`).
  - Accrual rows now get `[✎ Edit]`. `EditLedgerEntryModal` labels the entry type "Accrual" and
    the input "New credit (days)" (≥ 0).
- **`DeleteLedgerEntryModal`** in `LeaveBalanceActions.tsx`, on `ModalShell` (`px-5 py-4` chrome).
  This is not a native `confirm()` (hrms-confirm-dialog rule), because it needs a reason and a
  preview:
  - **Read-only summary:** leave type, entry type (Opening / Adjustment / Accrual, plus the
    accrual period for an accrual), date, current value.
  - **"Reason for deleting"**, required.
  - **Preview** runs the dry run and shows "Balance 5.00 → 3.50" plus any warnings, the negative
    warning in amber. For an Accrual, add the line "The accrual job will not credit this period
    again."
  - **Delete**: a red primary button, enabled only after a preview has succeeded for the
    current reason. It applies, reloads the tab and closes. Server 422s show inline.
- **`SetOpeningBalanceModal`:** a type whose Opening is voided is **enabled** again, labelled
  "Casual Leave — deleted on 12-Oct-26 · will re-open".
- House rules: Tailwind only, dd-MMM-yy, 10px page spacing, and modal internals follow the modal
  convention.

## Not in scope
- Revoking HR-recorded leave → **task 218**. Editing it → **task 207**.
- Deleting CarryForward, LapseExpiry, Encashment or system Availed/Reversal rows. Correct those
  with Adjust balance.
- Deleting in a closed leave year.
- **Re-running accrual** for a voided period. A void is final for that (rule, period). If HR
  wants it back, they Edit the voided Accrual row up from 0, or add an Adjustment.
- Bulk delete.
- Undo of a void. For Opening and Accrual, Edit back up from 0 is the undo. A voided Adjustment
  is re-entered as a new Adjustment.

## Files
- `backend/app/modules/leave/ledger_edit_service.py`: `VOID_SOURCE`, the generalised effective
  value and folding, `voidable_kind`, `void_ledger_entry`, and the accrual branch in
  `edit_kind` / `edit_ledger_entry`
- `backend/app/modules/leave/{router.py,schemas.py,service.py}`, including the `get_employee_ledger`
  caller passing `can_delete`
- `backend/app/modules/leave/opening_balance_service.py` (re-open a voided Opening)
- `backend/app/tests/modules/test_leave_ledger_edit.py` (extend) or `test_leave_ledger_void.py` (new)
- `backend/app/tests/modules/test_leave_opening_balance.py` (re-open case)
- `backend/app/tests/modules/test_authz.py` (the DELETE LEAVE gate)
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/shared/{EmployeeLeaveTab.tsx,LeaveBalanceActions.tsx}`
- Docs:
  - `docs/leave-and-attendance/leave/ledger.md`: extend "Editing a manual entry" with
    "Deleting an entry": the VOID shape, the deletable rows, and why it is never a SQL DELETE
    (the accrual idempotency keys).
  - `api-and-pages.md`: the endpoint.
  - `docs/roles-and-permissions.md`: add the endpoint to the list of gated endpoints under
    DELETE LEAVE.

## Progress (12-Oct-26)
- Branch `feature/gowtham_LedgerVoid` in top-level `hrms/`, cut from `origin/main` @ `95b21b2`.
  Not committed yet.
- **Backend done:**
  - `ledger_edit_service`: `VOID_SOURCE`, `correction_state` (value + voided), `voidable_kind`,
    `void_ledger_entry`, the shared `_load_target`, the accrual branch of `edit_kind` /
    `edit_ledger_entry`, and `reopen_opening`.
  - `POST /ledger/{ledger_id}/void` is gated on `_DELETE` plus `_require_admin(…, "DELETE")`.
    `get_employee_ledger` passes `can_void = grid_allows(DELETE LEAVE)`.
  - `opening_balance_service` sets a deleted Opening again as an EDIT reversal, dated as the
    original, through both the single and bulk paths.
- **Tests:**
  - `test_leave_ledger_void.py` (new) has 26 cases, including the scheduled and ONBOARDING
    no-re-credit cases and the EDIT-without-DELETE 403.
  - In `test_leave_ledger_edit.py`, Accrual was dropped from the "system rows" parametrize,
    since it is now editable.
  - Void, edit and opening together: 68/68 on a throwaway pg:18.
  - Leave, authz and employee-leave-policy suites: 458 passed, 11 failed. The same 11 fail on
    untouched `origin/main` (notifications and nhforms environment), so there are no
    regressions.
  - The DELETE gate test lives in the void module, as 206's did, not in `test_authz.py`.
- **Frontend done:**
  - `voidLedgerEntry`.
  - Row `[Delete]` beside `[Edit]`. The column is 166px with both buttons, 84px with one.
  - "Show deleted (n)" toggle; deleted rows are struck through, with a red "Deleted" chip and
    history.
  - `DeleteLedgerEntryModal`.
  - Accrual edit in `EditLedgerEntryModal`.
  - The opening modal re-enables deleted types with "deleted (date) · sets it again".
  - `tsc` is clean. ESLint shows only the pre-existing `set-state-in-effect`.
  - The modal summary shows the entry date, not the accrual period, because
    `LeaveLedgerRowOut` carries no `accrual_period`.
- **Docs done:** `ledger.md` §10.3 (new) plus updates to §4, §10 and §10.2, `api-and-pages.md`,
  `gaps.md`, and the leave row of `roles-and-permissions.md` §7.
- **Shipped for review (12-Oct-26):** commit `0fe841f` (217 and 218 together). The user merged `main` in (`bd38f58`) and pushed. Bitbucket PR #159 → `main`: https://bitbucket.org/NanoHealth_India/hrms/pull-requests/159. After the merge, tsc is clean and the tests give 565 passed and 11 failed, the same 11 environment failures as main.
- **Remaining:** the rest of the UI checks below. One Opening delete (row 12540) was already done by the user through the UI against the local API. Then merge #159 and move this file to `done/`.

## Acceptance criteria
- [ ] Delete a manual Adjustment (+2):
  - one `Reversal` (−2, `reversal_of_id` = the Adjustment, `source='VOID'`) is written;
  - `get_balance` drops by 2;
  - the HR ledger API returns the row with `voided=true` and quantity 0, and no separate
    reversal row;
  - `/me/ledger` omits it;
  - the last folded `balance_after` equals `get_balance`.
- [ ] Delete an Opening (1.5) → effective 0, voided. "Set opening balance" for that type is then
      `ok` ("re-opens"). Applying it writes an `EDIT` Reversal, not a second `Opening`, and the
      row reads at the new value. The same holds through `/opening-balances/import`.
- [ ] Delete an edited Opening (1.5 edited to 2) → the VOID quantity is −2, the effective value
      at the time.
- [ ] Delete a `SCHEDULED` Accrual. Then running `leave_accrual_service.process` for that job
      and `grant_first_credits` for that date writes **no new Accrual**. Do the same for an
      `ONBOARDING` grant.
- [ ] Edit an Accrual 1.00 → 0.50: one `EDIT` Reversal (−0.5). Edit is rejected above
      `max_balance` and below 0.
- [ ] Deleting an Adjustment or Accrual that makes the balance negative succeeds and returns the
      warning. Deleting an Opening that would do so is a 422.
- [ ] 422 cases each have a test:
  - CarryForward, LapseExpiry, Encashment, system Availed or Reversal row;
  - closed leave year;
  - already voided;
  - empty reason.
- [ ] 404 for another tenant's row, and for another employee's row in the same tenant. 401
      without a token.
- [ ] 403 for a role whose LEAVE grid lacks DELETE, even with UPDATE (the HR Manager default
      grid). A role with no grid saved is refused too. `void_kind` is null for such a caller,
      while `edit_kind` is still set.
- [ ] `dry_run` writes nothing: the ledger row count is unchanged and there is no activity row.
- [ ] One `user_activity_details` row per applied void, carrying the deleted row's details.
- [ ] §5.3 hygiene: no ledger row's `is_active` / `updated_at` changes. Row count only grows.
- [ ] Encrypted round-trip test for `/void`.
- [ ] UI checks:
  - Delete appears only on Opening, Adjustment and Accrual rows in open years, and only for a
    DELETE LEAVE holder.
  - Preview → Delete hides the row.
  - "Show deleted (n)" reveals it struck through, with a "Deleted" chip and history.
  - The skeleton matches the widened column.
  - Accrual rows have Edit.
- [ ] `uv run pytest` is green for the leave test modules and `test_authz.py`. Frontend `npm run
      lint` and `tsc` are clean.

Completed: 2026-10-13
