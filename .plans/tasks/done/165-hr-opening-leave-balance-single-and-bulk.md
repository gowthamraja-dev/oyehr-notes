---
task: 165
title: HR opening leave balance (single + bulk upload, with an accrual double-count guard)
status: done
depends_on: []
---

# 165 — Opening leave balances (single, bulk, double-count guard)

Work in the **top-level `hrms/`** clone on `feature/gowtham_LeaveMasters`, like the rest of the
leave-policy work (tasks 140–164), not in `workspace-2/`.

## Why
HR has no screen for entering an opening leave balance. When a company moves onto HRMS, HR
usually has a spreadsheet of each employee's remaining balance from the old system. There is
no way to load it today.

**What exists (API only):**
- `POST /api/v1/leave/employees/{employee_id}/ledger/adjust`
  (`backend/app/modules/leave/router.py:398`, `service.py:2206 adjust_employee_ledger`).
  - It needs `UPDATE LEAVE` plus `_require_admin`, and it sits on an EncryptedRoute.
  - Body (`LeaveLedgerAdjustIn`, `schemas.py:699`):
    `{leave_type_master_id, leave_year, quantity (signed), effective_date?, remarks}`.
  - It writes one signed `Adjustment` row through `ledger_service.write_ledger_entry`.
  - It covers one employee and one leave type per call.
  - Nothing in the frontend calls it (`docs/leave-and-attendance/leave/gaps.md` #9, "Still open").

**What's missing:**
1. **The `Opening` txn_type is never written.**
   - The ledger vocabulary has it.
   - The partial unique index `uq_leave_ledger_system_txn` covers it, keyed on
     `(cdp, employee, leave_type, leave_year, txn_type, effective_date)`
     (`models/employee_leave_balance_ledger.py:50`).
   - `ledger.md` §event table says `Opening` is `+` quantity, with
     `effective_date = max(leave-year start, joining_date)`.
   - Using Adjustment works, but the history then labels the balance "Adjustment".
2. **There is no screen and no bulk path.**
3. **Accrual can count the same months twice.**
   - `leave_accrual_service._schedule_from` starts a rule at `rule.effctv_dt`. If that is empty,
     it uses `policy.effctv_dt`, and failing that, today.
   - The scheduled job then catches up period by period (`_MAX_CATCHUP_PERIODS = 24`).
   - If the rule's start date is before go-live, accrual credits the pre-go-live months itself.
     An opening balance loaded on top counts those months twice.
   - The opening balance must be the as-of-go-live figure, and rules should accrue only from
     go-live.

## Scope

### Backend: `ledger_service`/`service.py` + leave router (EncryptedRoute)
Use **one service function** for both entry points. It is gated by
`RequirePermission("UPDATE", "LEAVE")`, the same cell as adjust.

Input is a list of rows: `{employee_master_id | emp_id, leave_type_master_id | leave_type_code,
balance (≥ 0), as_of_date, remarks?}`. Add a flag `dry_run: bool` and a flag
`acknowledge_accrual_overlap: bool`.

**Per-row resolution and validation.** Collect errors for each row and never fail the whole
batch on one bad row.
- Resolve the employee by id or `emp_id`, tenant-scoped through
  `corp_masters.care_delivery_program_master_id`. Exclude archived and inactive employees
  (`hrms-soft-delete`).
- Resolve the leave type by id or `code` within the tenant. It must be active and not archived.
- **Resolve the employee's governing rule** (`LeavePolicyDetail`) for that type, as of
  `as_of_date`, through the policy-resolution service. Batch it with
  `resolve_details_for_employees`, the same call `leave_year_close_service` uses.
  - **Reject** the row when no rule covers the type ("winner takes all": the type is
    `covered: false` for this employee).
  - The balance would be unusable, because apply fails with `no_policy`.
  - Year close would also never settle it. `close_due_years` logs "no rule governs … left open"
    and skips the series.
  - Store the rule's id in `leave_policy_detail_id` on the Opening row. Year close's fallback
    `_last_accruing_rule` reads it.
- **`leave_year` comes from that rule's `reset_month`.** Use
  `service.resolve_leave_year(rule, as_of_date)` (`modules/leave/service.py:773`), not a
  hardcoded month.
  - `leave_year` is the calendar year the leave year *starts* in. With April as the reset month,
    2026-03-15 is `leave_year=2025`.
  - A rule that resets in January puts the same date in 2026.
  - Getting this wrong lands the balance in a year that year close settles at the wrong time.
- `effective_date = max(as_of_date, leave-year start, joining_date)`. Take the leave-year start
  from the same `reset_month`.
- **Only the employee's current leave year.** Reject an `as_of_date` that falls in a past leave
  year, or in a year that already has a year-close `LapseExpiry` row for that
  (employee, type, year). An Opening written into a closed year is stranded: it never lapses
  and never carries forward.
- **Reject** these rows:
  - `balance < 0`;
  - `balance` above the rule's `max_balance` (`leave_policy_detail.max_balance`, the balance
    cap; it is NULL when uncapped);
  - a leave type that is unpaid (`is_paid = false`, e.g. LOP), since there is no balance to open;
  - a type whose `gender_applicable` doesn't match the employee (see task 160);
  - a duplicate (employee, type) inside the same upload.

**An `Opening` row that already exists for (employee, type, leave_year):**
- If the quantity is the same, it is a no-op, reported as `unchanged`. A re-upload is safe.
- If the quantity differs, it is a **row conflict**. Don't overwrite it. HR corrects it with an
  `Adjustment` from the Leave tab.
- Don't Reverse the old row and insert a new one. The new row collides on the unique index when
  the `effective_date` is the same.

**The double-count guard.** Run it for each (employee, type).
- Resolve the employee's live rule for the type (`resolve_from_mappings` / policy resolution).
- Warn when `_schedule_from(rule) < effective_date`. Accrual will credit periods before the
  opening date unless the rule's `effctv_dt` is moved to go-live.
- Also warn when `Accrual`/`CarryForward` rows already exist in that leave_year with
  `effective_date <= effective_date` of the opening row. Those rows would be counted twice.
- Return the warnings in the response, each with the rule/policy id and its effective date.
- Apply refuses a row with an overlap warning unless `acknowledge_accrual_overlap` is true.

**Write.** Write one `Opening` row per valid row through `ledger_service.write_ledger_entry`
(it takes the advisory lock; respect it), with `created_by_id` and `remarks`.
- Bulk writes happen in one transaction. A dry run writes nothing and returns the same counts as
  a real run would.
- Use batch lookups for employees, types and rules, so the query count doesn't grow with the
  number of rows.

**Response:** `{dry_run, total, to_create, unchanged, conflicts, errors, warnings,
rows: [{row_no, employee_id, emp_id, name, leave_type_code, leave_year, effective_date,
balance, status, message}]}`.

**Endpoints:**
- `POST /leave/employees/{employee_id}/ledger/opening` handles a single row (dry_run is
  optional; the default is false).
- `POST /leave/opening-balances/import` takes a JSON `rows[]` and `dry_run`.
  - The **frontend parses the CSV** and posts JSON.
  - This keeps the request on EncryptedRoute. Balances count as sensitive, and EncryptedRoute
    doesn't support multipart, so don't copy the plain-router holiday CSV import.
  - Cap it at a sensible size, such as 5,000 rows, and return a 422 above that.

**Logging:**
- INFO on apply.
- WARNING at each guard, with the failing values.
- One `log_activity` summary row on a bulk apply, with counts in `deleted_data`, following
  task 164's precedent.

Also add a ledger-row label for `Opening` ("Opening balance") wherever the typed labels live,
so history rows read correctly.

### Frontend
**`api.ts`:**
- Add `setOpeningBalance` and `importOpeningBalances` (both `secureFetch`).
- Add `adjustEmployeeLedger` too. It closes the rest of gaps.md #9.

**Employee Leave tab (`dashboards/shared/EmployeeLeaveTab.tsx`):**
- Add a **"Set opening balance"** action, visible only with `UPDATE LEAVE`. It opens a modal
  (`px-5 py-4` chrome) with leave type, as-of date (`DateField`), balance and remarks.
- The modal shows a dry-run preview first, including the overlap warning, then Apply.
- Add an **"Adjust balance"** action in the same place for the existing adjust endpoint, which
  takes signed quantities.

**Bulk upload (HR Admin → Leave, next to "Assign policies to employees" in
`hrAdmin/Leave_components/PolicyAssignments.tsx` or the nearest leave-admin breadcrumb):**
1. A **"Import opening balances"** modal.
2. A downloadable CSV template: `emp_id,leave_type_code,balance,as_of_date,remarks`.
3. File pick, parsed client-side.
4. **Preview** (dry run): a table of every row with status, error and warning text, and summary
   counts.
5. An "I've checked the accrual start dates" acknowledgement that appears only when warnings
   exist.
6. **Apply**, behind a `useConfirm`, then the result counts.

Follow the house rules: dates display as dd-MMM-yy, shimmer skeletons, Tailwind only, 10px
spacing.

### Not in scope
- Changing how the accrual job schedules. The guard only **warns**. HR or ops move the rule's
  `effctv_dt` to go-live with the existing policy screens.
- Editing or deleting an existing `Opening` row. Corrections go through `Adjustment`.
- XLSX parsing. CSV only, for now.

## Files
- `hrms/backend/app/modules/leave/{service.py,router.py,schemas.py}` (or a new
  `opening_balance_service.py` beside `assignment_service.py` if `service.py` gets too big)
- `hrms/backend/app/services/ledger_service.py` (`write_ledger_entry`; the leave year comes from `service.resolve_leave_year`; no schema change
  expected, since `Opening` is already allowed)
- `hrms/backend/app/tests/modules/test_leave_opening_balance.py` (new)
- `hrms/frontend/src/lib/api.ts`
- `hrms/frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`
- `hrms/frontend/src/dashboards/hrAdmin/Leave_components/` (new `OpeningBalanceImportModal.tsx`
  plus the trigger)
- Docs:
  - `docs/leave-and-attendance/leave/ledger.md`: the opening-balance flow and the go-live rule.
  - `gaps.md` #9: mark the adjust UI and Opening as resolved.
  - `api-and-pages.md`: the new endpoints.

## Progress (01-Oct-26)
- **Backend:**
  - `modules/leave/opening_balance_service.py`, one pipeline for both entry points:
    `POST /leave/employees/{id}/ledger/opening` and `POST /leave/opening-balances/import`
    (≤ 5,000 rows). Both are on EncryptedRoute and gated by `UPDATE LEAVE` plus `_require_admin`.
  - Every outcome is a per-row `status`: `ready`, `created`, `unchanged`, `conflict`, `blocked`
    or `error`. Bad rows are reported, never raised.
  - Opening rows carry `leave_policy_detail_id` and `source='OPENING'`.
- **The guard uses the job's real cursor**, not `_schedule_from`. `sync_scheduler_job_for_policy`
  only moves `next_run_at` on a frequency change, so editing a rule's `effctv_dt` leaves the
  cursor where it is.
  - It is still the right fix, because `_eligible_employees` credits a period only while the rule
    is live on that period's resolve date.
  - The guard warns on the period straddling the opening date, or else the one just before it,
    when that period is unprocessed and the rule is live then.
  - The message names the fix that applies: move the rule's start date, open on a period
    boundary, or (Yearly up-front) leave this year's entitlement out.
  - Public `period_containing`/`is_up_front` were added to `leave_accrual_service`.
- **Frontend:**
  - `api.ts`: `adjustEmployeeLedger`, `setOpeningBalance`, `importOpeningBalances`.
  - `lib/openingBalanceCsv.ts`: the CSV parser and template. It reads YYYY-MM-DD, DD-MM-YYYY and
    dd-MMM-yy dates, and sends a bad cell as null so it's reported against its row.
  - `shared/LeaveBalanceActions.tsx`: the Set opening balance and Adjust balance modals, plus the
    status pill and row notes.
  - The Leave tab's ledger header shows both actions to holders of `UPDATE LEAVE`. Opening and
    Adjustment rows now read "label · remarks".
  - `hrAdmin/Leave_components/OpeningBalanceImportModal.tsx` is opened by an "Import opening
    balances" button in the Policy Assignments breadcrumb.
- **Tests:** `test_leave_opening_balance.py`, 14, all pass. The leave, employee-leave-policy and
  authz regression suites pass (382 tests).
  - One task-164 test counted backfill activity rows across all tenants, so the real runs on
    hrms-dev (30-Sep, 01-Oct) broke it. It is now scoped to its own tenant.
- **Docs:** ledger.md §10 and the event-table row, gaps.md #9, api-and-pages.md.
- **Browser check:** done by the user on 01-Oct-26 (the three modals; the API writes to
  the shared DB).

## Acceptance criteria
- [x] The single and bulk endpoints write `txn_type='Opening'` rows with
      `effective_date = max(as_of, leave-year start, joining_date)` and the right `leave_year`.
      The balance and history show the row as "Opening balance".
- [x] A dry run writes nothing, and its counts match a real run. A re-upload of the same file
      creates 0 rows (`unchanged`). A different quantity for an existing Opening is a
      `conflict`, not an overwrite.
- [x] Bad rows are reported per row without blocking the valid ones: an unknown emp_id or type
      code, a negative balance, a balance above the rule's `max_balance`, a type with no
      covering rule, an unpaid or gender-mismatched type, a past or already-closed leave year,
      an in-file duplicate, and an archived employee.
- [x] `leave_year` follows the governing rule's `reset_month`. A test uses a January-reset rule
      and an April-reset rule with the same as-of date. The Opening row carries
      `leave_policy_detail_id`, and a later `close_due_years` settles it (LapseExpiry and
      CarryForward).
- [x] The overlap guard warns when the rule's accrual start (`_schedule_from`) is before the
      opening date, or when Accrual/CarryForward rows already exist on or before it. Apply
      refuses those rows unless `acknowledge_accrual_overlap=true`.
- [x] Tenant scope: a test proves that another tenant's employee or leave type can't be targeted
      by id or by code.
- [x] Tests also cover 401/403 without `UPDATE LEAVE`, a 422 above the row cap, and an encrypted
      round-trip. There is one activity row on a bulk apply.
- [x] Frontend: the Leave-tab "Set opening balance" and "Adjust balance" modals, and the bulk
      import modal (template → preview → acknowledge → apply). tsc is clean; lint is clean on the new files (`EmployeeLeaveTab.tsx` keeps one `set-state-in-effect` error that predates this task).
- [x] The docs are updated (ledger.md, gaps.md #9, api-and-pages.md).

Browser check done by the user on 01-Oct-26.

Completed: 2026-10-01
