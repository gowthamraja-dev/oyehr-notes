---
task: 164
title: HR Admin bulk backfill of employee_masters.leave_policy_master_id (preview + apply)
status: done
depends_on: [162, 163]
---

# 164 — Bulk backfill for existing employees (HR Admin)

## Scope
**Backend:** `POST /api/v1/leave/policy-assignments/backfill-employee-policies` (EncryptedRoute,
same router). Gate it with `RequirePermission("UPDATE", "LEAVE_POLICY")`, or the nearest existing
leave-admin cell.

Body: `{ "dry_run": true, "mode": "missing" | "recalculate" }`.
- **`missing`** (default): only employees with NULL `leave_policy_master_id`.
- **`recalculate`**: every non-archived employee in the tenant, re-resolved from the mappings. It
  **overwrites** existing pins. The UI makes that explicit.

Resolution per employee is `resolve_from_mappings` as of today (department → employee type →
corp → CDP). Use the batch helpers so the query count stays fixed.

Response: `{ dry_run, total_considered, to_set, unchanged, unresolved, by_policy: [{policy_id, name, code, count}], unresolved_sample: [{employee_id, emp_id, name}] }`.

Apply behaviour:
- One transaction.
- Tenant-scoped: only employees whose `corp_masters.care_delivery_program_master_id` = the
  caller's tenant, archived excluded (`hrms-soft-delete`).
- Writes only the rows that change.
- One `log_activity` summary row, with counts and the mode.
- INFO log.
- Safe to re-run: a second `missing` run sets 0.

**Frontend** (Policy Assignments tab, which keeps its modal per the user's 159 decision): an
**"Assign policies to employees"** button opens a small modal. It has a mode toggle (Only
employees without a policy / Recalculate everyone), a **Preview** (dry run: counts per policy +
unresolved list), and **Apply** (a `useConfirm` for `recalculate`). It shows the result counts.
Hint: "New CDP, department or employee-type assignments don't move employees who already have a
policy — run this again with Recalculate."

**Script parity** (optional): `backend/scripts/backfill_employee_leave_policy.py --cdp <id> [--apply] [--recalculate]`
for ops. It is a dry run by default and reuses the same service function.

## Expected result on hrms-dev (from 161)
- `missing` pins 977 employees across 36 CDPs to their `DEFAULT` policy.
- 83 stay unresolved (75 in 3 CDPs with a policy but no mapping, 8 in CDPs with no policy).
- Only run it on the shared DB with the user's go-ahead.

## Progress (30-Sep-26)
- **Backend:** `assignment_service.backfill_employee_policies` + `POST /leave/policy-assignments/backfill-employee-policies`
  (`RequirePermission("UPDATE", "LEAVE")`, EncryptedRoute). Schemas: `EmployeePolicyBackfillIn/Out`.
  - In `recalculate` mode it never clears a pin when nothing resolves; the employee is only
    reported as unresolved.
  - The activity row is `action_path="/leave/policy-assignments/backfill-employee-policies"`,
    with counts in `deleted_data`.
- **Frontend:** `backfillEmployeeLeavePolicies` in `api.ts`. The
  `EmployeePolicyBackfillModal` in `PolicyAssignments.tsx` is opened by an "Assign policies to
  employees" breadcrumb button (UPDATE LEAVE). It has a mode toggle, then Preview (dry run), then
  Apply (`useConfirm` for Recalculate), and shows the result counts and the unresolved sample.
- **Tests** (7, all pass): dry run matches apply and writes nothing, re-run sets 0, missing
  keeps pins while recalculate overwrites, tenant scope, archived skipped, one activity row, a
  pin never cleared, 401/403, 422 on an unknown mode, encrypted round-trip.
- **Docs:** `employee-leave-policy.md` §3 and `api-and-pages.md`.
- **Not done:**
  - the optional ops script: dropped by the user (30-Sep-26), not needed;
  - a **browser check** of the modal (left to the user; the API writes to the shared DB);
  - **running the backfill on hrms-dev**, which needs the user's go-ahead. Expect about 977 set
    and 83 unresolved.

## Acceptance criteria
- [x] The dry run writes nothing and returns counts that match a real run.
- [x] `missing` never touches pinned employees. `recalculate` overwrites them. Both are tenant-scoped
      (a test proves another tenant's employees are untouched) and skip archived employees.
- [x] A 403 for callers without the permission, and an encrypted round-trip test.
- [x] An activity row is written on apply.
- [x] The UI previews, then applies, and shows the result. tsc/lint are clean.

Browser check done by the user on 30-Sep-26.

Completed: 2026-09-30
