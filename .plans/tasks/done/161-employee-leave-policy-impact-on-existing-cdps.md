---
task: 161
title: Impact on existing CDPs of an employee-level leave policy (employee_masters.leave_policy_master_id)
status: done
depends_on: []
---

# 161 — Impact on existing CDPs of `employee_masters.leave_policy_master_id`

**Where:** top-level `hrms/` (`feature/gowtham_LeaveMasters`). This task is analysis and a doc
only. The build is in tasks 162–164.

## The change being assessed (user request, 30-Sep-26)
- Add `employee_masters.leave_policy_master_id`.
- **Fill it whenever an employee is created.**
- Give HR Admin a **bulk backfill** for existing employees.
- Resolve an employee's policy in this order:
  1. `employee_masters.leave_policy_master_id`
  2. the employee's **department**'s policy
  3. the **employee type**'s policy
  4. the **CDP**'s (tenant-wide) policy

Today, resolution ranks every live provider mapping by `priority` first. Provider specificity
(Employee 5 > Employee Type 4 > Department 3 > Corp 2 > All 1) only breaks ties
(`leave_policy_resolution_service._rank_key`). The new order is a **fixed level order**, and it
puts Department **above** Employee Type, which is the reverse of today's tie-break.

## Design decisions (taken to unblock 162–164; the user can overturn any of them)
- **D1. The column pins the employee's policy.** It is filled at creation from levels 2→4
  (resolved as of the employee's joining date, or today). After that it wins until someone
  changes it. A later department or type change does **not** move the employee by itself. An
  admin re-runs the backfill with "recalculate" or edits the employee. If the pinned policy isn't
  live (archived, inactive, or out of its dates), resolution falls through to levels 2→4.
- **D2. Fixed levels, with priority only inside a level.** `priority` (then newest `effctv_dt`,
  then id) only breaks ties **within** a level, e.g. an employee in two departments. It no
  longer lets a CDP-wide mapping beat a department one.
- **D3. `EmployeeMaster` provider mappings are retired.** The column replaces them. None are live
  today. Resolution still honours any that exist, just below the column. The assignment screen
  stops offering "Employee" and points to the employee's own policy field instead.
- **D4. Corp stays** as a level between Employee Type and CDP, where it is today. The request
  didn't mention it, and none are live. Remove it later if the user wants.
- **D5. The column is undated.** A back-dated accrual catch-up for an earlier period uses the
  current pin. Dated history stays on the provider mappings (levels 2–4).

## Findings: shared hrms-dev DB, 30-Sep-26 (read-only)
| Bucket | CDPs | Employees (non-archived) | What 162–164 does to them |
|---|---:|---:|---|
| One live **tenant-wide** (`CareDeliveryProgramMaster`) mapping, all to the `DEFAULT` policy | 36 | 977 | Backfill pins every employee to their CDP's `DEFAULT`, the same policy they resolve to today. **No change in balances, accrual or apply** |
| Has a policy but **no live mapping** (100240 *NEXTENTI* 74, 96657 *tejass* 1, 96658 *tejak* 0) | 3 | 75 | Nothing resolves today and nothing resolves after. Backfill leaves them NULL and **reports** them, so HR can assign a policy first |
| No leave policy at all | 11 | 8 | Unchanged (NULL) |

- **Live mappings by provider type:** `CareDeliveryProgramMaster` ×36 (one per CDP, all
  priority 0). **Zero** `DepartmentMaster`, `EmployeeTypeMaster`, `EmployeeMaster` or `CorpMaster`
  mappings exist, so the level reorder (D2) changes **nobody's** policy today.
- Only 23 employees have `employee_type_master_id`, and 138 have a live
  `employee_department_mappings` row. Those only matter once department or type assignments are
  created.
- `employee_masters.leave_policy_master_id` doesn't exist yet. Adding it as a **nullable** FK is
  additive, so `main`/`workspace-2` code, which doesn't map it, keeps working.
- Next Life (19571, NT42's tenant): 19 employees, one CDP mapping to `DEFAULT`. They get pinned
  to `DEFAULT`, with no change.

## Behaviour changes to call out to HR
- **After the backfill, new CDP-level assignments no longer move pinned employees.** Assigning a
  new tenant-wide policy won't change anyone already pinned, so HR must re-run the backfill with
  "recalculate". The same goes for new department and type assignments. Surface this in the
  backfill UI (164) and in the Policy Assignments hint.
- **Department beats Employee Type** (the old tie-break was the reverse). Nothing depends on this
  today, because no such mappings exist.
- **The explainer changes.** `/leave/employees/{id}/policy-resolution` and `/leave/me/policy`
  show the pinned policy as the winning candidate, labelled "Employee's own policy".

## Files
- New doc `hrms/docs/leave-and-attendance/leave/employee-leave-policy.md`. It covers the column,
  the resolution order, fill-on-create, the backfill, this impact table and the queries below. It
  is linked from `domain-model.md` §5.2.3 and `ledger.md` §7.1.

## Reproducible queries (read-only)
```sql
-- live mappings by provider type
SELECT m.provider_type, count(*), count(DISTINCT m.care_delivery_program_master_id)
FROM leave_policy_provider_mappings m JOIN leave_policy_masters p ON p.id = m.leave_policy_master_id
WHERE m.archive = false AND m.is_active AND p.archive = false AND p.is_active GROUP BY 1;
-- CDPs with a policy but no live mapping (backfill leaves their employees NULL)
SELECT p.care_delivery_program_master_id, count(DISTINCT p.id) FROM leave_policy_masters p
WHERE p.archive = false AND NOT EXISTS (SELECT 1 FROM leave_policy_provider_mappings m
  WHERE m.care_delivery_program_master_id = p.care_delivery_program_master_id AND m.archive = false AND m.is_active)
GROUP BY 1;
```

## Acceptance criteria
- [x] The doc exists (`hrms/docs/leave-and-attendance/leave/employee-leave-policy.md`), is linked from `domain-model.md` §5.2.3 and `ledger.md` §7.1, and states D1–D5 and the impact table.
- [x] The user has been told the D1–D5 defaults and the "pinned employees don't follow new CDP
      assignments" consequence.

Completed: 2026-09-30
