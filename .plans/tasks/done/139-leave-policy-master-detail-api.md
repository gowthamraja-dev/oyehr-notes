---
task: 139
title: Leave policy master + detail CRUD API (LeavePolicyService)
status: done
depends_on: [137, 138]
---

# 139 — Leave policy master + detail CRUD API

## Scope
Encrypted router (existing `/api/v1/leave` `router`, `RequirePermission(<ACTION>, "LEAVE")` like
the existing type endpoints). New `app/modules/leave/policy_service.py` so `service.py` (2200
lines) stops growing.

Endpoints:
- `GET /leave/policies?include_archived=` — masters in the tenant (archived — incl. `LEGACY_V<n>`
  — hidden by default), each with `leave_types` (codes, in `display_order`), scope summary
  ("All corps" or the corp names found on its details), status, dates, `updated_at`, and
  `assignment_count`.
- `GET /leave/policies/{id}` — master + its details (one per leave type).
- `POST /leave/policies` — master **with** details in one transaction:
  `{name, code, description, is_active, effctv_dt, trmntn_dt, details: [{leave_type_master_id,
  corp_master_id|null, accrual_frequency, accrual_quantity, max_balance, carry_forward,
  max_carry_forward, encashable, max_encashment, prorate_on_joining, reset_month, is_active,
  effctv_dt, trmntn_dt}]}`.
- `PATCH /leave/policies/{id}` (header), `PATCH /leave/policies/{id}/status`,
  `DELETE /leave/policies/{id}` = archive (soft: `archive`, `is_active=false`, `archived_by_id`,
  `archived_at`; its mappings stop resolving; ledger untouched).
- `POST /leave/policies/{id}/details`, `PATCH /leave/policy-details/{detail_id}`,
  `PATCH /leave/policy-details/{detail_id}/status`, `DELETE /leave/policy-details/{detail_id}`
  (archive). **Edits are in place** (unique per policy + type).
- `POST /leave/policies/{id}/new-version` `{name, code, effctv_dt, move_assignments: bool}` — the
  way to change rules without touching history: copies the master + all details to a new master
  effective `effctv_dt`; with `move_assignments`, sets `trmntn_dt = effctv_dt - 1` on the old
  master's active mappings and clones them onto the new master from `effctv_dt` (same provider,
  same priority). One transaction.
- Retire the per-type bridge endpoints from 137 (`/leave/types/{id}/policies`, `/leave/policies/
  {policy_id}` detail routes) once 145/146 no longer call them.

Validation, 422 unless noted:
- duplicate master code in the CDP → 409; second detail for the same leave type in a policy → 409;
- `trmntn_dt < effctv_dt` (master and detail); negative `accrual_quantity`; `accrual_frequency`
  not in Monthly|Quarterly|Yearly|OnJoining; `reset_month` not 1–12;
- `max_carry_forward` without `carry_forward` → reject; `max_encashment` without `encashable` →
  reject (the current code silently nulls them — change to reject);
- leave type / corp must belong to the tenant and not be archived; can't add details to or edit an
  archived master (incl. LEGACY);
- every lookup by id also filters `care_delivery_program_master_id` (no RLS).

Audit: `leave_policy_audits` row per detail create/update/activate/deactivate/archive (its original
shape — detail + leave type ids). Master-level actions: `created_by_id`/`updated_by_id`/
`archived_by_id` + `log_activity` on archive and on new-version (hrms-activity-logging skill).
INFO log on success, WARNING at each guard. `sync_scheduler_job_for_policy` on every detail
mutation; master deactivate/archive deactivates its details' scheduler jobs.

## Files
- `hrms/backend/app/modules/leave/policy_service.py` (new), `schemas.py`, `router.py`, `service.py`
- `hrms/backend/app/tests/modules/test_leave_policy_masters.py` (new, incl. encrypted round-trip)

## Acceptance criteria
- [x] Create "Standard Employee Leave Policy" with CL/SL/EL in one call; list shows 3 leave types.
- [x] Every validation above has a test; duplicate (policy, type) → 409.
- [x] Editing a detail updates it in place; existing ledger rows unchanged.
- [x] New-version with `move_assignments`: as of the day before → old policy resolves; as of
      `effctv_dt` → new policy resolves.
- [x] 401 / 403 (no LEAVE permission) / cross-tenant 404 on every endpoint; LEGACY hidden by default.

## Verification notes
- `test_leave_policy_masters.py` — 30 tests: create with CL/SL/EL + list summary (leave types,
  scope, assignment count); corp-name scope; whole-policy rejection when one rule is invalid; every
  validation (duplicate code 409, same type twice in payload 409, second rule for a type 409,
  master/rule date order, negative quantity, bad frequency, reset month 0/13, caps without their
  flag, foreign leave type 404, archived leave type 422, foreign corp 422); in-place rule edit
  keeps the id, the ledger row and writes CREATED→UPDATED audit; header patch + code conflict;
  deactivate/activate pauses/resumes the rule's accrual SchedulerJob; archived policy hidden +
  read-only (incl. new-version); LEGACY hidden by default; new-version with/without moving
  assignments (resolves old on 30-Jun, new on 1-Jul; a not-yet-started assignment is re-pointed);
  401 / 403 non-admin / 403 grid READ-only / cross-tenant 404 on all 11 endpoints; encrypted
  create round-trip. All green; `test_leave.py`, `test_leave_policy_resolution.py`,
  `test_authz.py` green alongside.

## Decisions made while building
- **Route paths:** masters at `/leave/policies[/{id}]`; one leave type's rule at
  `/leave/policy-details/{id}` (PATCH, `/status`, DELETE). The 137 bridge had used
  `/leave/policies/{id}` for rules — moved (the only caller, `frontend/src/lib/api.ts`, was
  repointed in the same change; the mobile app doesn't use them). `POST
  /leave/types/{id}/policies` (bridge create into DEFAULT) stays until 146, now sharing
  `policy_service.insert_rule`, which also added the missing corp-belongs-to-tenant check.
- **Caps without their flag:** an explicit combination (`carry_forward=false` +
  `max_carry_forward`, same for encashment) is rejected with 422 on create and patch. Turning
  `carry_forward`/`encashable` off in a patch that doesn't mention the cap still clears the stored
  cap — rejecting that would force every "switch off" to also send `max_*: null`.
- `create_policy` validates every rule before inserting anything (no manual `db.rollback()` —
  that would discard the caller's whole unit of work).
- Frontend `LeavePolicy` type: dropped `employee_type_master_id`, added `leave_policy_master_id`
  (`tsc --noEmit` clean).

Completed: 2026-09-29
