---
task: 163
title: Fill employee_masters.leave_policy_master_id on create (every path) + admin edit
status: done
depends_on: [162]
---

# 163 — Fill the pin when an employee is created, and let HR change it

## Scope
Every code path that inserts an `employee_masters` row sets `leave_policy_master_id` to
`resolution.resolve_from_mappings(...)` (department → employee type → corp → CDP, as of the
employee's `joining_date`, or today). It stays NULL when nothing resolves. The three paths:
1. **Registration form (nhforms)**: `app/modules/forms/subscribers.py` raw
   `INSERT INTO employee_masters … RETURNING id` (~L132). Set the pin right after the insert, in
   the same transaction. The department/type answers are already written by then. This path is
   async; run the sync helper the way the subscriber already does its other sync work.
2. **Bulk import**: `app/modules/employee_import/service.py` (~L326 `EmployeeMaster(...)`). The
   import usually has no department or type, so this is normally the CDP policy. Resolve per row
   after flush.
3. **Org creation HR admin employee**: `app/modules/admin_organizations/service.py` (~L987). The
   new CDP's template policy + tenant-wide mapping are cloned **before** this, so it gets
   `DEFAULT`. Check the order.

One shared helper, e.g. `leave_policy_resolution_service.pin_default_policy(db, tenant_id, employee) -> int | None`.
It sets the column, logs INFO, and never overwrites an existing pin.

**Admin edit:**
- `EmployeePatch.leave_policy_master_id: int | None`. It must be a live, non-archived policy in
  the caller's tenant; otherwise 422. Explicit `null` unpins.
- Gate it on `UPDATE EMPLOYEE`.
- Log it with `log_activity` (an ownership/assignment change, per the `hrms-activity-logging` skill).
- `EmployeeDetailOut` gets `leave_policy_master_id` + `leave_policy_name`.
- Frontend: the Edit Employee modal gets a "Leave policy" select (tenant policies from
  `listLeavePolicyMasters`, plus "Follow assignments (auto)" = null). The employee profile shows the
  policy name.

**Out of scope:** bulk backfill of existing rows (164).

## What was built (30-Sep-26)
- `resolution.pin_default_policies(db, tenant_id, employees, as_of=None)`: never overwrites a
  pin, retries a future joining date, flushes, and logs INFO.
- **Registration:** the pin is set in `subscribers._credit_onboarding_leave_accrual_sync`
  (post-commit, own sync session, separate commit), just before `process_onboarding`. That is
  the first point where the replayed department mappings exist, and it means the first credit
  already resolves through the pin.
- **Bulk import:** `pin_default_policies` runs on every created employee, in the import's own
  transaction, before commit.
- **Org creation:** a flush, then the pin, right after `_clone_shift_and_leave_defaults`. The HR
  admin's employee row is made earlier, by `_provision_admin`. The session doesn't autoflush, so
  without the flush the pin never saw that row.
- **Admin edit:** `EmployeePatch.leave_policy_master_id` → `_set_employee_leave_policy`. It gives
  422 unless the policy is live and in the tenant; null unpins. It writes an activity row
  (`/employees/{id}/leave-policy`). `EmployeeDetailOut` gains `leave_policy_master_id` and
  `leave_policy_name`.
- **Frontend:** the Edit Employee modal gets a "Leave policy" select ("Follow assignments (auto)"
  = null). It is sent only when changed, and hidden if leave policies can't be read. The profile
  view and detail drawer show "Leave policy".
- **Tests:** a new `test_employee_leave_policy.py` (helper ×4, the Registration hook, PATCH
  set/clear/activity, dead or foreign pin ×4),
  `test_employee_import.py::test_commit_pins_each_new_employee_to_their_leave_policy`, and an
  extension to `test_new_organization_gets_template_leave_policies`. That test asserts "what the
  new tenant's assignments give", because the shared DB's own CDP-0 template carries a `DEFAULT`
  that ties.
- **Test run:** 118 passed. The 4 failures are all pre-existing:
  `test_employee_import::{test_target_fields_direct_mode, test_commit_creates_employees_when_all_rows_valid, test_commit_provisions_a_real_login_for_each_imported_employee}`
  and `test_forms::test_subscriber_creates_reporting_mapping_when_team_lead_selected`, all on
  the 158 baseline list.
- **tsc** is clean. The only eslint errors in the touched files were already there:
  `setState`-in-effect and conditional `usePermission`.

## Acceptance criteria
- [x] An employee created through each of the 3 paths gets the resolved policy (tests per path),
      or NULL when the tenant has none.
- [x] An explicit pin set by an admin is never overwritten by creation-time logic.
- [x] PATCH with a foreign-tenant, archived or inactive policy returns 422. `null` unpins, and an
      activity row is written.
- [x] tsc/lint are clean, and the leave + employees + import + forms tests are green (known
      pre-existing failures excepted).

Completed: 2026-09-30
