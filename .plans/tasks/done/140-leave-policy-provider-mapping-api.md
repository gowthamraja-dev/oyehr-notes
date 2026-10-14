---
task: 140
title: Policy assignment (provider mapping) API + resolution explainer
status: done
depends_on: [138, 139]
---

# 140 — Policy assignment API + resolution explainer

## Scope
`app/modules/leave/assignment_service.py`, encrypted routes under `/leave/policy-assignments`:
- `GET /leave/policy-assignments?provider_type=&leave_policy_master_id=&include_archived=` — rows
  with `provider_label` (employee name, department name, employee-type name, corp name, "All
  employees" for `CareDeliveryProgramMaster`), policy name/code, priority, dates, status.
- `POST`, `PATCH /{id}`, `PATCH /{id}/status`, `DELETE /{id}` (archive — soft, with
  `archived_by_id`/`archived_at`).
- `GET /leave/policy-assignments/providers?provider_type=&q=` — picker options (tenant-scoped,
  non-archived; employees searchable by name/emp_id).
- `GET /leave/employees/{employee_id}/policy-resolution?as_of=` — `explain()` output: every
  candidate (policy, provider type/label, priority, dates) with the selected one flagged, plus the
  winning policy's rule per leave type (or "not covered" when winner-takes-all leaves a type
  out). `READ LEAVE`; managers only for their reports (`_require_manager_or_admin_for`).

Validation: `provider_type` in the 5 supported values; provider exists in the tenant (CDP provider
must equal the tenant id); policy active, not archived, not LEGACY (archived policies can't be
assigned); priority ≥ 0 (app-level — the DBML has no check constraint); `trmntn_dt >= effctv_dt`;
**conflict rule** — same `(provider_type, provider_id)` + same priority + overlapping dates → 409
with the conflicting mapping in the body (never silently overwrite). Different priorities are
allowed; the explainer shows which one wins.

Audit (no audit-table columns for mappings — 137): `created_by_id`/`updated_by_id`/
`archived_by_id` + `log_activity` on create/update/status/archive (assignment changes are in the
hrms-activity-logging skill's scope). Logging per convention.

## Files
- `hrms/backend/app/modules/leave/assignment_service.py` (new), `schemas.py`, `router.py`
- `hrms/backend/app/tests/modules/test_leave_policy_assignments.py` (new)

## Acceptance criteria
- [x] CRUD + archive; archived / LEGACY policy rejected for a new assignment.
- [x] Same provider + same priority + overlapping dates → 409; different priority → allowed.
- [x] Explainer for the "Dr. Ananya" fixture: Doctor (Employee Type, 50) ✓ selected, Clinical
      (Department, 30), Standard (Corp, 10).
- [x] Provider or policy from another CDP → 404/422; list isolated per tenant; manager can't
      explain a non-report.

## Verification notes
- `test_leave_policy_assignments.py` — 20 tests: create/list (priority-desc order, policy and
  provider-type filters, labels "NanoHealth" / "Doctor" / "All employees"); patch (priority,
  dates, re-point policy), date-order 422, deactivate/activate, archive (hidden, include_archived,
  read-only, idempotent); `user_activity_details` row per create/patch/archive; archived /
  inactive / LEGACY policy → 422; provider not in tenant (foreign corp/employee/department/
  employee type, archived department, other CDP id, unknown id) → 422; bad provider_type /
  negative priority / reversed dates → 422; foreign policy → 404; conflict 409 with
  `conflicting_assignment` in the body, and allowed for a different priority or non-overlapping
  dates; patching or re-activating into a conflict → 409; provider picker tenant-scoped +
  searchable; explainer: Dr. Ananya ranking Doctor(50) ✓ / Clinical(30) / Standard(10), CL covered
  vs SL "not covered" (winner takes all), `as_of` switch and notes; manager → report 200,
  non-report 403; foreign employee 404; 401 on all 7 endpoints; 403 non-admin on the 6 admin
  endpoints; other tenant's assignments invisible + 404; encrypted create round-trip.
- Full leave set + `test_authz.py`: 274 passed.

## Decisions made while building
- The explainer is the only assignment route open to managers (reports only); list / picker /
  writes are admin-only, like the rest of leave configuration.
- Inactive (not just archived) policies can't be newly assigned; re-activating an assignment
  re-checks both the policy and the conflict rule.
- An assignment's provider can be changed by PATCH (re-validated), so 147's edit modal doesn't
  need archive-and-recreate.

Completed: 2026-09-29
