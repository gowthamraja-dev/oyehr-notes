---
task: 138
title: Provider-mapping policy resolution service + cut over every resolve_leave_policy caller
status: done
depends_on: [137]
---

# 138 — Provider-mapping policy resolution service

## Scope
New `hrms/backend/app/services/leave_policy_resolution_service.py` — in `services/` with no
dependency on `app.modules.leave`, so `ledger_service` and `leave_accrual_service` can import it
without the current deferred-import workaround. Nothing is stored per employee: the policy is
computed on demand for `(employee, as_of)`.

### Shared filter helper (removes the repeated boilerplate)
`live(model, tenant_id, as_of) -> list[ColumnElement]` — the standard "usable row" filter for any
table with the common lifecycle columns (the four DBML tables all have them):
`care_delivery_program_master_id = tenant`, `is_active`, `NOT archive`,
`(effctv_dt IS NULL OR effctv_dt <= as_of)`, `(trmntn_dt IS NULL OR trmntn_dt >= as_of)`.
NULL dates = open (137's decision). Replace the hand-written copies of these filters in
`resolve_leave_policy`, `ledger_service._resolve_reset_month`, `process_onboarding` and
`_leave_type_in_force` — those compare `effctv_dt <= as_of` directly, which silently drops rows
with a NULL `effctv_dt` now that the column is nullable.

### Provider keys for the employee (as of `as_of`)
| provider_type | provider_id matched against |
|---|---|
| `EmployeeMaster` | `employee_masters.id` |
| `DepartmentMaster` | **every** department from `employee_department_mappings` live on `as_of` (see below) |
| `EmployeeTypeMaster` | `employee_masters.employee_type_master_id` (skip when NULL) |
| `CorpMaster` | `employee_masters.corp_master_id` |
| `CareDeliveryProgramMaster` | the tenant id ("All employees") |

**Departments — user decision (2026-09-29): use all dated department mappings.**
`department_ids(db, tenant_id, employee_id, as_of)` =
`employee_department_mappings.department_master_id` where `employee_master_id = employee`,
`is_active`, `(effective_date IS NULL OR effective_date <= as_of)`,
`(terminatn_date IS NULL OR terminatn_date >= as_of)`, joined to `department_masters` with
`care_delivery_program_master_id = tenant`, `is_active`, `NOT archive` (that table has no tenant or
archive column of its own, and uses `effective_date`/`terminatn_date`, so it can't use `live()`).
- An employee in several departments matches every one of them; priority (then the tie-break
  below) decides between their policies.
- `employee_masters.department_master_id` (the "primary" department) is **not** used for
  resolution — it has no dates, so it can't answer "which department on date D". Because it is
  dated, a department change moves future lookups to the new department's policy while past
  lookups (year close, accrual catch-up) still see the old one.

### Functions
- `applicable_mappings(db, tenant_id, employee, as_of) -> list[MappingCandidate]` —
  `live(LeavePolicyProviderMapping) AND live(LeavePolicyMaster) AND provider_match(keys)`.
  Ordered `priority DESC`, then provider specificity (Employee > EmployeeType > Department > Corp >
  All employees), then `effctv_dt DESC NULLS LAST`, then `id DESC` — deterministic, never "first
  row wins". LEGACY masters never match (archived, unmapped).
- `resolve_policy_master(db, tenant_id, employee, as_of)` — head of that list, or None.
  **Winner takes all**: a leave type missing from the winning policy is NOT taken from a
  lower-priority policy (brief §13 steps 7–8).
- `resolve_policy_detail(db, tenant_id, employee, leave_type_id, as_of)` — the winning master's
  single detail for that type (unique per policy + type), only if `live(LeavePolicyDetail)` and its
  `corp_master_id` is NULL or equals `employee.corp_master_id`. Otherwise None — another corp's
  rule is never used.
- `explain(db, tenant_id, employee, as_of)` — every candidate with a `selected` flag (a department
  candidate names which department matched), plus the winner's per-type details / "not covered",
  for task 140's conflict view.

### Cut over callers
They currently call `resolve_leave_policy(db, tenant, type, corp_id, as_of)`:
`app/modules/leave/service.py` (apply gates, preview, balances, ledger views, `_default_policy_summary`,
`get_leave_type_with_policy`), `ledger_service._resolve_reset_month`,
`leave_accrual_service._eligible_employees` / `process_onboarding` / `_policy_is_schedulable`
(a detail whose master is inactive/archived/out of date is not schedulable). Remove
`resolve_leave_policy` once nothing calls it. Accrual resolves per employee as of the period end,
so it needs the department keys batched per period (one query for all candidates' live department
mappings), not one query per employee.

Leave-type list "default summary": from the detail for that type in the tenant's CDP-wide
(priority-0) policy, if any.

### Known data gap (not fixed here)
`employee_masters.employee_type_master_id` is NULL for all 948 employees on hrms-dev, so
`EmployeeTypeMaster` assignments match nobody until that field is populated. `explain()` should
say "employee type not set" rather than silently skip it.

## Files
- `hrms/backend/app/services/leave_policy_resolution_service.py` (new)
- `hrms/backend/app/modules/leave/service.py`, `app/services/ledger_service.py`,
  `app/services/leave_accrual_service.py` (edit)
- `hrms/backend/app/tests/modules/test_leave_policy_resolution.py` (new)

## Acceptance criteria
- [x] Scenario 7: corp 10 / department 30 / employee-type 50 → employee-type policy wins.
- [x] Multi-department: employee in Cardiology (policy priority 30) and Research (priority 20) →
      Cardiology's policy; each department candidate appears in `explain()`.
- [x] Department change: mapping to A ends 2026-06-30, mapping to B starts 2026-07-01 → resolves A's
      policy as of 2026-06-15 and B's as of 2026-07-15.
- [x] Inactive department mapping, archived department, or a department from another CDP never
      matches; the undated primary `department_master_id` alone never matches.
- [x] Scenario 8: employee mapping priority 100 overrides every broader mapping.
- [x] Scenario 9: a policy mapped to corp X at higher priority wins for X's employees only; a
      detail scoped to corp Y never applies to a corp-X employee (resolves to None for that type).
- [x] Scenario 10: archived / inactive / out-of-date master or mapping is skipped; LEGACY masters
      never resolve.
- [x] Effective dating: Standard (mapping → 2026-06-30) vs New (mapping 2026-07-01 →) resolves by
      `as_of`; NULL dates treated as open (`live()` unit-tested on a NULL `effctv_dt` row).
- [x] Winner takes all: type absent from the winning policy → None, even if a lower policy has it.
- [x] Equal-priority tie resolves deterministically by specificity.
- [x] Cross-tenant: a mapping/policy in CDP B never resolves for an employee in CDP A.
- [x] Full existing leave + accrual suites green.

## Verification notes
- `test_leave_policy_resolution.py` — 17 tests, one per acceptance item above plus batch-vs-single
  parity, `explain()` ranking/notes and `ledger_service._resolve_reset_month`. All green.
- `test_leave.py` 176/176 green on the new resolver (fixtures: the test `_master()` gives
  DEFAULT its tenant-wide assignment; corp-specific rules now live in a corp-assigned policy).
- `resolve_leave_policy` removed; every caller uses `leave_policy_resolution_service`
  (apply/preview/approve/manager detail/balances, `get_leave_type_with_policy` via
  `ProviderKeys(corp_id=...)`, leave-type summary via `ProviderKeys()`, ledger reset month,
  accrual `_eligible_employees` (batched) / `process_onboarding` (all types in one resolve)).
  `_policy_is_schedulable` now also requires the rule's policy master to be live.
- Pre-existing, unrelated failures seen in neighbouring suites (left as-is):
  `test_admin_organizations.py` ×2 (department HR-attribute defaults empty) and
  `test_forms.py::test_subscriber_creates_reporting_mapping_when_team_lead_selected` (stale: the
  subscriber it calls no longer handles EMPTL — moved to target-logic replay).
- Observation: `test_leave.py` wall time went 165s → 355s on the remote hrms-dev DB (resolution is
  3 queries per call; apply paths resolve 2–3×). Fine for now; revisit with a per-request cache if
  it shows up in API latency.

Completed: 2026-09-29
