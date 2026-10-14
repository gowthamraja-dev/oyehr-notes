---
task: 228
title: Employee sees every leave type their policy grants, at 0 until the ledger is credited
status: done
depends_on: []
---

# 228 — Employee sees every leave type their policy grants, at 0 until the ledger is credited

Clone: originally planned for top-level `hrms/`; **built in `workspace-2/hrms/`** at the user's request (13-Oct-26), branch `feature/gowtham_PolicyLeaveTypesAtZero` off `origin/main`.

## Scope
Today an employee only sees a leave type once an `employee_leave_balance_ledgers` row exists
for it (`_balances_for_employee`, `backend/app/modules/leave/service.py:~1808`; the same filter
is in `list_leave_types` for the self caller, `service.py:~292`). A type that the employee's
policy grants but which hasn't been accrued or credited yet is invisible, so a new joiner sees
"No leave assigned to you yet".

Change the rule so an employee sees the union of:
1. **Types their resolved policy covers.** `resolution.resolve_policy_details(db, tenant_id,
   employee, [all active, non-archived tenant types], today)` returns a non-None
   `LeavePolicyDetail`. This is resolved through `leave_policy_provider_mappings` or the pinned
   `employee_masters.leave_policy_master_id`, in `services/leave_policy_resolution_service.py`.
2. **Types with any ledger row for them**, which is today's rule. Keep it so historic,
   opening-balance or manually credited types never disappear.

…filtered to `is_active = true AND archive = false` and the tenant (`care_delivery_program_master_id
== principal.tenant_id`). **Also drop types whose `gender_applicable` excludes the employee**
(`app.services.gender.gender_applies(lt.gender_applicable, employee.gndr)`). Don't show Maternity
to someone who can never apply for it. `applicable_after_days` does **not** hide a type: a
new joiner sees it at 0, and the apply guard still refuses until they are eligible.

A policy-covered type with no ledger rows needs no special case. `get_available_balance` /
`_used_ytd` already return 0 for it, so the card shows 0 available, 0 used and 0 accrued, with
`entitled = policy.max_balance`. As soon as an accrual, opening balance or adjustment writes a
ledger row, the real numbers show with no other change.

Where it applies (all go through these two functions, so no per-screen work):
- `GET /api/v1/leave/me/balances` is used by the My Leave cards (`frontend/src/dashboards/Employee/MyLeave.tsx`),
  the Home "Leave balance" tile (`get_paid_available_days`) and the mobile app.
- `GET /api/v1/leave/employees/{id}/balances` is the HR approval/detail balance strip. The same
  function, so HR sees the zero rows too.
- `GET /api/v1/leave/types` for a self caller is the apply form's type dropdown. A zero-balance
  type becomes selectable, and applying is still decided by `validate_balance` (refused unless
  `allow_negative_balance`). No change to the apply rules.

**Not in scope:** changing accrual, crediting a balance on assignment, or any schema change.
Admin callers of `list_leave_types` (UPDATE LEAVE grid) are unchanged.

## Implementation notes
- Factor one helper, e.g. `_visible_leave_types_for_employee(db, tenant_id, employee, today) -> list[LeaveTypeMaster]`,
  and use it from both `_balances_for_employee` and the self branch of `list_leave_types`. Keep
  ordering `display_order, name`.
- Keep the query count fixed: one query for active types, one `resolve_policy_details` call
  (batched over all ids), and one `DISTINCT leave_type_master_id` ledger query. No per-type loops
  hitting the DB beyond what `_balances_for_employee` already does.
- Update both docstrings (`_balances_for_employee`, `list_leave_types`). They currently say the
  opposite.
- `MyLeave.tsx` needs no logic change. Check that a 0.0 card renders cleanly
  (`fmtDays(0)`, the ledger drawer's "No leave credited or used yet." empty state), and that the
  "No leave assigned to you yet" empty state still shows only when the list is truly empty
  (no policy and no ledger).

## Files
- `backend/app/modules/leave/service.py` (`_balances_for_employee`, `list_leave_types`, new helper)
- `backend/app/tests/modules/test_leave.py`: rewrite
  `test_leave_types_self_only_shows_types_with_a_ledger_balance` (~1568) and
  `test_my_balances_only_shows_types_with_a_ledger_balance` (~2008) to the new rule, and add the cases below
- `frontend/src/dashboards/Employee/MyLeave.tsx` (check only. Edit only if a 0 card looks broken)

## Acceptance criteria
- [x] An employee whose policy covers CL/SL/EL, with no ledger rows, gets all three from `/me/balances`, each with `available_balance = 0`, `used = 0`, `accrued = 0` and `entitled = max_balance`.
- [x] After an accrual or opening-balance row is written for one type, that type shows its real balance and the others stay at 0.
- [x] A type with ledger rows that the current policy no longer covers still shows (union, not replace).
- [x] An inactive or archived type, another tenant's type, and a type whose `gender_applicable` excludes the employee are not returned.
- [x] An employee with no resolvable policy and no ledger rows gets `[]` (empty state unchanged).
- [x] `/leave/types` as a self caller returns the same set. Applying against a zero-balance non-negative type is still refused by `validate_balance`.
- [x] HR's `/employees/{id}/balances` returns the same set for that employee, and stays tenant-scoped (another CDP's employee gives 404/403 as today).
- [x] `uv run pytest app/tests/modules/test_leave.py` is green (on a throwaway local pg:18 with create_all; ignore the known status_masters seed failures).
- [x] My Leave smoke-tested in a browser with a fresh employee: zero cards render, and the apply dropdown lists them.

Completed: 2026-10-13
