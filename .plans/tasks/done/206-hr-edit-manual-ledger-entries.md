---
task: 206
title: HR edits a manual leave-ledger entry (Opening / Adjustment) + opening balance once per leave type
status: done
depends_on: []
---

# 206 — Edit a manual ledger entry (Opening / Adjustment) + one opening balance per leave type

Work in the **top-level `hrms/`** clone, not `workspace-2/`. Today that clone is on
`feature/gowtham_HrmsDevConfig`, which already has tasks 165 and 197 (`d4bf1f7`, `0e668b7`).
Run `git -C hrms status -sb` first and cut a feature branch from wherever the 165/197 work lives.
Paths below are relative to `hrms/`.

## Why
HR Manager → Employee profile → **Leave** tab → **Ledger** card
(`frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`, mounted by `EmployeeProfileView.tsx`)
has three write actions: **Set opening balance**, **Adjust balance** and **Record leave taken**.
None of them can change a row that is already there.

For example, HR sets the CL opening balance to **1.5** when it should be **2**.
- They can't edit the row.
- They can't re-run "Set opening balance" for the same year: `opening_balance_service._check_ledger`
  reports a different quantity as a `conflict`.
- The only fix is a separate "+0.5 Adjustment". The ledger then reads "Opening 1.5" plus an
  unexplained adjustment, not "Opening 2".

This task adds an **Edit** action to each row **HR entered by hand**. Rows written by the
system never get one.

| Row | `txn_type` | How to recognise it | Editable here? |
| --- | --- | --- | --- |
| Opening balance | `Opening` | `source = 'OPENING'` | **Yes**: the balance |
| Manual adjustment | `Adjustment` | `leave_request_detail_id IS NULL` | **Yes**: the signed quantity |
| Record leave taken | `Availed` | request recorded by HR (task 197) | **Task 207** (it also changes the request and attendance) |
| Accrual / CarryForward / LapseExpiry | system | — | **Never** |
| Availed / Reversal from apply, approve or cancel | system | — | **Never** |
| Encashment | `Encashment` | — | Not in scope (it ties into payroll) |

## Design: an edit is a correction row, never an UPDATE
`employee_leave_balance_ledgers` is **append-only** (`docs/leave-and-attendance/leave/ledger.md`
top and §5.3). Corrections are new `Reversal` rows that point at `reversal_of_id`, and
`is_active`/`updated_at` are never touched. So the edit stays append-only too:

- Write **one** `Reversal` row through `ledger_service.write_ledger_entry`:
  - `reversal_of_id = <edited row id>`;
  - `quantity = new_value − current_effective_value` (signed; partial reversals already exist
    for a mid-leave cancel);
  - same `leave_type_master_id`, `leave_year`, `effective_date` and `leave_policy_detail_id` as
    the original;
  - `leave_request_detail_id = NULL`, **`source = 'EDIT'`** (this tells an edit apart from a
    cancel reversal, which always carries `leave_request_detail_id`);
  - `remarks` = HR's reason, which is required, and `created_by_id`.
- **current_effective_value** = `original.quantity + Σ quantity of its EDIT reversals`. A
  second edit works off the value the first one produced.
- **No migration and no new vocabulary.** `Reversal` is not in `uq_leave_ledger_system_txn`, so
  nothing collides. Re-inserting an `Opening` would collide, which is why task 165 refused to.

### Read side: fold edits into the row they correct
`service._ledger_for_employee` serves both `GET /leave/employees/{id}/ledger` and `GET /leave/me/ledger`.
- **Leave EDIT reversals out of the list.**
- **Show each edited row at its effective value**, in its original position.
- **Recompute `balance_after` for display** as a running sum over the folded rows, per
  `(leave_type, leave_year)` in `id` order. The last row of each series must still equal
  `ledger_service.get_balance` (assert this in a test).
- A row whose effective value is 0 still shows, with an "Edited" chip.

Add these fields to `LeaveLedgerRowOut` (`backend/app/modules/leave/schemas.py:701`):
- `edit_kind: Literal["opening", "adjustment"] | None`. It is non-null only on the employee
  endpoint (never on `/me/ledger`) and only when the row is editable now.
  - Task 207 adds `"recorded_leave"`.
  - Compute it on the server, so the frontend never re-implements the rules.
- `original_quantity: Decimal`, plus `edited: bool`.
- `edits: list[LedgerEditOut]`, each `{quantity_before, quantity_after, remarks, edited_by_name, created_at}`.
- `remarks`: the latest edit's reason when the row was edited. Otherwise the original's, as today.

## Backend: `POST /api/v1/leave/employees/{employee_id}/ledger/{ledger_id}/edit`
- Put it on the existing leave **EncryptedRoute** router (`router.py`, next to
  `/ledger/adjust` at ~427).
- Gate it with `dependencies=[_UPDATE]` plus `_require_admin(db, principal)`, the same tier as
  adjust and opening. A reporting manager gets no edit.
- **Body** `LeaveLedgerEditIn`: `{quantity: Decimal, remarks: str (min_length=1), dry_run: bool = False}`.
  `quantity` is the **new value of the row**, not a delta.
- **Response** `LeaveLedgerEditResultOut`: `{dry_run, ledger_id, txn_type, leave_type_master_id,
  leave_year, quantity_before, quantity_after, delta, balance_before, balance_after, warnings: list[str]}`.
- **Service** goes in a new `modules/leave/ledger_edit_service.py`, since `service.py` is already
  ~2.4k lines. Expose `edit_ledger_entry(db, principal, employee_id, ledger_id, payload)` and
  `editable_kind(row, ...)`. The read path's `edit_kind` reuses `editable_kind`, so the two can't
  drift.

**Steps:**
1. `target = _get_employee_in_tenant(...)`, which raises NotFound cross-tenant. Load the row with
   `care_delivery_program_master_id == principal.tenant_id`, `employee_master_id == target.id`
   and `id == ledger_id`. Another tenant's or employee's row is a **404**.
2. `ledger_service.lock_ledger(tenant, employee, type, leave_year)` **before** reading any
   balance.
3. **Guards.** Each one raises 422 and logs a WARNING with the values that failed it.
   - The row must be editable: `Opening` with `source='OPENING'`, or `Adjustment` with
     `leave_request_detail_id IS NULL`. Everything else gets "This entry is system-generated and
     can't be edited".
   - **The leave year must be open.** If a year-close `LapseExpiry` row exists for
     (employee, type, leave_year), reject: "Leave year 2025–26 is closed". This mirrors task 165's
     rule for Opening, since a correction in a closed year never lapses or carries forward.
   - `quantity == current_effective_value` → 422 "No change".
   - **Opening:**
     - `quantity ≥ 0`.
     - `quantity ≤` the rule's `max_balance` when it is capped. Take the rule from the row's
       `leave_policy_detail_id`, falling back to policy resolution as of `effective_date`.
       Reuse `opening_balance_service._validate_values` and the max-balance check, and don't copy
       them.
     - **Refuse if the resulting ledger balance goes below 0.** That means the employee has
       already used more than the corrected opening allows. Tell HR to record an Adjustment
       instead.
   - **Adjustment:**
     - `quantity != 0`. To undo an adjustment fully, HR adds an opposite Adjustment.
     - A negative resulting balance is allowed, because adjust already allows it. Return it in
       `warnings`.
4. `dry_run` → return the result and write nothing (`balance_after` = current + delta).
5. Write the Reversal. `db.commit()`, then log INFO: "Ledger row %s (%s) edited %s -> %s for
   employee %s type %s year %s (tenant %s, by %s)".

## Opening balance: once per employee per leave type, ever
An opening balance is a **one-time migration event**. It is the figure an employee brings in
from the old system on the day their leave starts being tracked in HRMS. After that day, HRMS
moves the balance itself: accrual, availed leave, year-close carry-forward or lapse, and HR's
Adjustments. There is nothing left to "open" again.

**So an employee has at most one Opening per leave type, for life.** The number of Openings an
employee can have equals the number of paid leave types their policy covers. For example,
CL + SL + EL means at most 3 Openings.

**What the code allows today.** `opening_balance_service` limits Openings only **per leave
year**:
- `_check_ledger` checks for an existing Opening in the same `(employee, type, leave_year)`.
- `_place_in_leave_year` only allows the current leave year.
- The DB index `uq_leave_ledger_system_txn` includes `leave_year` and `effective_date`.

So once the year rolls over (say April 2027), "Set opening balance" for CL is accepted again. A
second Opening then stacks on top of the CarryForward and the new year's accruals, which counts
the balance twice. The `carry_forward` check is only an acknowledgeable *warning*, and it never
fires at all when the policy carries forward nothing.

**New rules** (in `opening_balance_service`, shared by the single and bulk paths):
1. **An Opening already exists for (employee, type) in any leave year** → the row is
   `conflict`, or `unchanged` when the effective value is equal.
   - The message names it and points to Edit: "Opening balance of 1.50 already set on 01-Apr-26
     (2026–27). Use Edit on that ledger entry."
   - Compare against the **effective** value (original plus EDIT reversals, per the design
     above), so re-importing the corrected figure reads `unchanged`.
   - If that year is closed, the message says to use **Adjust balance** instead, because Edit
     refuses closed years.
2. **The balance is already tracked in HRMS** → `error`. This means (employee, type) already has
   any ledger row in an **earlier** leave year (Accrual, Availed, CarryForward, Adjustment,
   anything).
   - Message: "CL is already tracked in HRMS since 2025–26. Use Adjust balance to correct it."
   - This catches a joiner who started after go-live, whose balance came from onboarding accrual
     and has nothing to migrate.
   - The existing current-year `accrual_credited` and `carry_forward` warnings stay as they are.
     They cover the go-live year itself.
3. **Within one upload:** the existing duplicate-(employee, type) check now ignores
   `leave_year`. It already effectively does, because only one leave year is allowed.

**Database backstop.** Add a migration with a new partial unique index:
- `uq_leave_ledger_opening_once` on `(care_delivery_program_master_id, employee_master_id,
  leave_type_master_id) WHERE txn_type = 'Opening'`.
- Declare it in `models/employee_leave_balance_ledger.py`'s `__table_args__`, then autogenerate
  and review the migration. Run it through `scripts/migrate.py upgrade heads`.
- This works with the edit design: an edit adds a `Reversal`, so the Opening stays a single row.
- **Before applying,** run a read-only check for existing duplicates:
  `SELECT employee_master_id, leave_type_master_id, count(*) FROM employee_leave_balance_ledgers
  WHERE txn_type='Opening' GROUP BY 1,2 HAVING count(*) > 1`.
- If there are any, stop and ask. Never hand-delete ledger rows.

**Logging:** WARNING on each new rejection, with the employee, type, existing Opening id and year.

## Frontend
- **`lib/api.ts`:**
  - Add the `LeaveLedgerRow` fields above.
  - Add `editLedgerEntry(employeeId, ledgerId, {quantity, remarks, dry_run})` through
    `secureFetch`.
- **`EmployeeLeaveTab.tsx`: Ledger card redesign.** Today the three HR actions are teal
  text links (`text-teal-800 hover:underline`), squeezed into the tiny uppercase
  `SectionHeader` strip. They read as highlighted text, not as things to click, and are easy
  to miss. Replace them with real buttons:

  ```
  ┌───────────────────────────────────────────────────────────────────────────────┐
  │ Ledger                         [＋ Opening balance] [± Adjust] [▣ Record leave] │  ← toolbar row
  │ Balance changes for this employee                                              │
  ├────────┬───────────┬──────────────────────────┬───────┬───────┬───────┬────────┤
  │ DATE   │ LEAVE TYPE│ DESCRIPTION              │ CREDIT│ DEBIT │BALANCE│        │
  ├────────┼───────────┼──────────────────────────┼───────┼───────┼───────┼────────┤
  │01-Apr-26│ Casual   │ Opening balance [Edited] │ +2.00 │   —   │  2.00 │[✎ Edit]│
  │01-May-26│ Casual   │ Monthly accrual          │ +1.00 │   —   │  3.00 │        │
  │12-May-26│ Casual   │ Adjustment · migration   │ +0.50 │   —   │  3.50 │[✎ Edit]│
  └────────┴───────────┴──────────────────────────┴───────┴───────┴───────┴────────┘
  ```

  - **Card header becomes a toolbar row:**
    - On the left, the title "Ledger" (`text-[14px] font-bold text-ink-900`), with a one-line
      subtitle (`text-[11.5px] text-ink-500`).
    - On the right, a button group (`flex flex-wrap gap-2`), visible only with `canUpdate`.
    - The header uses `px-5 py-[10px]` and `border-b border-border-soft`.
    - Keep the plain uppercase `SectionHeader` for the other cards. Add a `variant`/`actions`
      prop or a small `LedgerToolbar`, and don't restyle every card.
  - **Each action is a secondary button with an icon:**
    - Use the app's existing secondary style, compacted:
      `inline-flex items-center gap-1.5 bg-white border border-border text-ink-700 text-[12.5px]
      font-semibold px-3 py-[7px] rounded-[9px] hover:bg-ink-100 hover:border-ink-200
      cursor-pointer disabled:opacity-60`.
    - Draw icons as inline SVG at 14px. The repo has no icon library.
    - Labels are short: "Opening balance", "Adjust balance", "Record leave".
  - **Responsive:** below `NARROW_BREAKPOINT`, from `useIsNarrow()`, the button group wraps under
    the title at full width. It must never overflow the card.
  - **Row "Edit":**
    - Add a trailing narrow column (no header text, `w-[84px]`) holding a visible
      **outlined button**, `[✎ Edit]`: the same secondary style at a smaller size
      (`text-[12px] px-2.5 py-[5px]`).
    - It is **always visible** on editable rows, not hover-only and not a bare icon, so HR can
      find it at a glance. It shows only when `canUpdate && row.edit_kind`. Other rows leave the
      cell empty.
    - Give it `aria-label="Edit entry"`.
  - Add the new column to `LedgerSkeleton`, with a `ShimmerButton` in the toolbar and in the row
    cells, so the header and grid still match (house shimmer rule).
  - **Edited rows** get a small "Edited" chip in the Description cell
    (`bg-ink-100 text-ink-600 text-[10.5px] font-semibold rounded-full px-2 py-0.5`).
  - Clicking or hovering the chip opens a popover listing `edits[]`: "1.50 → 2.00 · reason ·
    by <name> · 09-Oct-26". Format dates with `formatDDMMMYY`.
- **"Opening balance" follows the once-per-type rule** so HR never hits the error by surprise:
  - **Work out "already set" from the ledger the tab already loads**, which covers every year:
    any `txn_type === "Opening"` row for that leave type.
    - Do the same check for "already tracked": any row for that type in an earlier leave year.
  - **In `SetOpeningBalanceModal`, a type that is already set stays in the dropdown but is
    disabled.** It reads "Casual Leave — set (1.50 on 01-Apr-26)".
    - Below the dropdown, an inline "Edit it →" link opens `EditLedgerEntryModal` on that row.
      If that year is closed, the link points at Adjust balance instead.
    - A type that is already tracked is disabled with the reason "tracked in HRMS since
      2025–26".
  - **When every covered type is set or tracked, the toolbar's "Opening balance" button is
    disabled.** Its tooltip reads "Opening balances are set for all leave types — use Edit on a
    ledger entry". Don't hide the button: a missing button reads as "no permission".
  - The server rules above stay authoritative. This only stops HR from walking into them.
- **`EditLedgerEntryModal`**, in `LeaveBalanceActions.tsx`, reusing `ModalShell` (`px-5 py-4` chrome):
  - **Read-only summary:** leave type, entry type ("Opening balance" or "Adjustment"), date,
    current value.
  - **Inputs:** "New balance" (Opening, ≥ 0) or "New quantity" (Adjustment, signed, with the
    same helper text as AdjustBalanceModal), and "Reason for edit" (required).
  - **Preview** calls the dry run and shows `quantity_before → quantity_after` (Δ) and the
    resulting balance, plus any warnings. **Save** then applies, reloads the tab and closes.
  - Disable Save until a preview has succeeded for the current inputs. Changing any input
    clears the preview, the same pattern as `SetOpeningBalanceModal`.
  - Errors show inline. The server's 422 messages are written for HR to read.
- Follow the house rules: Tailwind only, `DateField` / dd-MMM-yy, no native `confirm()`, 10px
  page spacing. Modal internals keep the modal convention.

## Not in scope
- **Editing a row's date, leave type or leave year.** Editing changes the number and the reason
  only. To move an entry, HR adds an opposite Adjustment and enters a new one.
- **Deleting a manual entry.** Setting an Adjustment to its opposite isn't allowed (`quantity != 0`).
  Setting an Opening to 0 is allowed, and that is the effective "remove".
- Editing recorded leave → **task 207**. Encashment, accrual and other system rows → never.
- Bulk edit.

## Files
- `backend/app/modules/leave/ledger_edit_service.py` (new)
- `backend/app/modules/leave/{router.py,schemas.py,service.py}` (`_ledger_for_employee` folding,
  new fields on `LeaveLedgerRowOut`)
- `backend/app/modules/leave/opening_balance_service.py` (the once-per-type and already-tracked
  rules, the effective-value comparison, the conflict text)
- `backend/app/models/employee_leave_balance_ledger.py` plus a new Alembic migration for
  `uq_leave_ledger_opening_once`
- `backend/app/tests/modules/test_leave_opening_balance.py` (extend)
- `backend/app/tests/modules/test_leave_ledger_edit.py` (new)
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`, `LeaveBalanceActions.tsx`
- Docs:
  - `docs/leave-and-attendance/leave/ledger.md`: a new subsection, "Editing a manual entry". It
    covers the EDIT-reversal shape, the folding on read, and which rows qualify.
  - `api-and-pages.md`: the endpoint.
  - `gaps.md`, if it lists "no way to correct an opening balance".

## Progress (09-Oct-26)
- Branch `feature/gowtham_LedgerEdit` in `hrms/`, cut from `origin/main` @ `8565492`. Not
  committed yet.
- **Backend done:**
  - `modules/leave/ledger_edit_service.py` holds the edit and the folded read. Both ledger
    endpoints now go through `ledger_rows`.
  - `opening_balance_service._type_history` adds the once-per-type and already-tracked rules.
  - The index `uq_leave_ledger_opening_once` is in the model, and migration `d8a3f5c2b941` is
    hand-written and existence-guarded.
- **Tests:** `test_leave_ledger_edit.py` (new) and `test_leave_opening_balance.py` (4 new cases)
  give 42/42 on a throwaway pg:18.
  - The wider leave and authz suites give 428 passed and 15 failed.
  - The same 15 fail on untouched `origin/main` (environment), so there are no regressions.
- **Frontend done:**
  - Ledger toolbar buttons, the row `[✎ Edit]` button, the "Edited" chip with its history popover,
    `EditLedgerEntryModal`, and the opening-modal blocked types with "Edit it →" / "Adjust
    balance →".
  - `tsc` is clean. ESLint reports one pre-existing `set-state-in-effect` in the tab's load effect,
    which this task didn't change.
  - Responsive wrapping uses Tailwind `max-[1000px]:` modifiers rather than `useIsNarrow()`.
- **hrms-dev:** `uq_leave_ledger_opening_once` was applied directly on 09-Oct-26 with the user's
  go-ahead, after a duplicate re-check came back empty. Prod and other databases get it from
  migration `d8a3f5c2b941`.
- **Remaining:** a manual UI pass in the browser, then commit.

## Acceptance criteria
- [ ] Opening 1.5 → edit to 2: one `Reversal` row (+0.5, `reversal_of_id` = the Opening,
      `source='EDIT'`) is written. The ledger API returns the Opening row at 2.00 with
      `edited=true` and one entry in `edits`, and no separate reversal row. `get_balance` goes up
      by 0.5.
- [ ] A second edit (2 → 1) writes −1.0 against the same original. The effective value is 1.00
      and `edits` has two entries.
- [ ] Folded `balance_after` is a correct running sum. The last row of each (type, year) equals
      `ledger_service.get_balance`.
- [ ] An Adjustment edit (+1 → −0.5) works. A negative resulting balance comes back as a warning,
      not an error.
- [ ] 422 cases each have a test:
  - an Accrual, CarryForward, LapseExpiry, Encashment or system Availed/Reversal row;
  - a closed leave year;
  - no change;
  - an Opening below 0, or above `max_balance`;
  - an Opening edit that would make the balance negative;
  - an Adjustment edit to 0;
  - an empty reason.
- [ ] 404 for another tenant's ledger row, and for another employee's row in the same tenant.
      401 without a token. 403 without `UPDATE LEAVE` / not admin (`test_authz.py`-style).
- [ ] `dry_run` writes nothing: the row count is unchanged.
- [ ] `/me/ledger` folds edits the same way but never returns `edit_kind`.
- [ ] Re-importing the corrected opening figure through `/opening-balances/import` gives
      `unchanged`, not `conflict`.
- [ ] **Once per type, ever.** Opening CL in 2026–27; then, with the clock moved into 2027–28,
      "Set opening balance" for CL → `conflict`. The message names the existing row and says to
      use Edit, or Adjust when 2026–27 is closed.
  - Same result through the bulk import.
  - SL for the same employee is still accepted.
- [ ] An employee with CL Accrual rows in 2025–26 and no Opening → an Opening for CL in 2026–27
      is `error` ("already tracked in HRMS").
- [ ] The migration applies cleanly after the duplicate check returns no rows. A raw second
      `Opening` insert for the same (cdp, employee, type) in another year violates
      `uq_leave_ledger_opening_once`.
- [ ] Encrypted round-trip test for the new endpoint.
- [ ] §5.3 hygiene still holds: no ledger row's `is_active`/`updated_at` changes.
- [ ] UI checks:
  - The three Ledger actions are real bordered buttons with icons in a toolbar row, not text
    links. They wrap cleanly below 1000px.
  - In the Opening modal, already-set types are disabled with an "Edit it →" link. The toolbar
    button is disabled, with a tooltip, once every covered type is set or tracked.
  - The visible `[✎ Edit]` button appears only on Opening and manual Adjustment rows, and only
    for HR with `UPDATE LEAVE`.
  - Preview → Save updates the row in place with an "Edited" chip and history popover.
  - The skeleton has the new column.
- [ ] `uv run pytest app/tests/modules/test_leave_ledger_edit.py
      app/tests/modules/test_leave_opening_balance.py` is green. Frontend `npm run lint` and
      `tsc` are clean.

Completed: 2026-10-13
