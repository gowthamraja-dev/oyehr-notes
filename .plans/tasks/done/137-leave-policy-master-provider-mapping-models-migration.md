---
task: 137
title: Leave policy master + provider mapping models, exact-DBML schema, migration + backfill
status: done
depends_on: []
---

# 137 — Leave policy master + provider mapping models, exact-DBML schema, migration + backfill

Parent brief: "Implement Leave Policy, Leave Type, Accrual & Provider Mapping Changes" (pasted
2026-09-29) plus the user's DBML for the four tables, with the instruction **"replicate the exact
columns in the 4 tables, no addition"**. Split into tasks 137–149 — see the split note at the end.

## Design decisions (apply to every task 137–149)
- **Schema = the DBML, exactly.** No extra columns, no check constraints, index names as in the
  DBML. Validation that the DBML doesn't express (§28 of the brief) lives in the service layer.
- **`UNIQUE(leave_policy_master_id, leave_type_master_id)`** — one rule per leave type per policy.
  The rule is scoped to all corps (`corp_master_id` NULL) or to exactly one corp.
  - A detail is **edited in place** (no insert-a-new-row versioning any more).
  - A **new effective version** of a policy = a new policy master plus dated provider mappings
    (old mappings get `trmntn_dt`, new ones start the next day). Ledger rows keep their own
    quantity, so history never changes meaning.
  - A **per-corp variant** = its own policy mapped to that corp (`CorpMaster`) at a higher priority.
- **Nullable dates:** `effctv_dt IS NULL` = effective from the beginning, `trmntn_dt IS NULL` =
  open-ended — on masters, details, mappings and leave types alike.
- **Provider types:** `EmployeeMaster | DepartmentMaster | EmployeeTypeMaster | CorpMaster |
  CareDeliveryProgramMaster` (the last = tenant-wide fallback). Polymorphic, no FK on `provider_id`.
- **Audit without new columns:** `leave_policy_audits` keeps its original shape (detail-level rows
  only, both FKs NOT NULL). Masters and mappings are audited via `created_by_id` /
  `updated_by_id` / `archived_by_id` / `archived_at` plus `log_activity` (`user_activity_details`).
- **No manual employee balance assignment.** Balances come only from the ledger, fed by the
  resolved policy.

## Scope
Schema + the minimum code needed so the existing app and tests keep working against it.

1. Models (done, one file per table):
   - `leave_policy_master.py` — `LeavePolicyMaster` / `leave_policy_masters`: id, cdp FK, name
     String(150), code String(50), description Text, is_active, effctv_dt (nullable), trmntn_dt,
     archive, archived_by_id, archived_at, created_by_id, updated_by_id, created_at, updated_at.
     `uq_leave_policy_masters_cdp_code`.
   - `leave_policy_provider_mapping.py` — `LeavePolicyProviderMapping`: id, cdp FK, policy FK,
     provider_type String(50), provider_id, priority (default 0), effctv_dt (nullable), trmntn_dt,
     is_active, archive/archived_by_id/archived_at, created_by_id/updated_by_id, timestamps.
     Indexes `idx_leave_policy_provider_mapping_provider` (cdp, provider_type, provider_id),
     `_policy` (policy id), `_effective` (provider_type, provider_id, effctv_dt, trmntn_dt).
   - `leave_policy_detail.py` — adds `leave_policy_master_id` (NOT NULL FK), **drops
     `employee_type_master_id`** (always NULL), `accrual_frequency` default `'Yearly'`, `effctv_dt`
     nullable. `uq_leave_policy_details_policy_leave_type`, `idx_leave_policy_details_cdp_policy`.
   - `leave_type_master.py` — name String(120), code String(30), unit String(20),
     `allow_half_day` default true, gender_applicable String(20), `applicable_after_days` nullable
     (no default; NULL = no probation gate), color_code String(10), `effctv_dt` nullable.
2. Migration `3c8e5a1f7d20_leave_policy_masters_provider_mappings.py` (single revision; the user
   asked to keep and overwrite the existing revision rather than add a second one). Hand-written,
   existence-guarded (hrms-dev is stamped at orphan revision `8012104013b3`; DDL is applied
   directly). An earlier draft of this revision was already applied to hrms-dev; its extras are
   removed by guarded `_drop_*` steps that are no-ops on a fresh DB.
3. Backfill (in the migration, idempotent):
   - Per CDP with details: one `DEFAULT` master ("Default Leave Policy") + one
     `CareDeliveryProgramMaster` mapping at priority 0 → everyone resolves as before.
   - Per (CDP, leave type): the current row (live → active → already in force → newest) stays in
     DEFAULT; each older version moves to an archived, inactive, unmapped `LEGACY_V<n>` master.
     Nothing deleted or re-flagged; ledger FKs to old versions stay valid.
   - hrms-dev dry-run: 36 DEFAULT + 24 LEGACY masters, 36 mappings, 52 current rules, 12 ledger
     rows now point at legacy rows. The earlier draft archived 3 duplicate rows (3895, 4122, 4123)
     there — left as-is (they sit in LEGACY masters).
4. Bridge so the current admin UI keeps working until tasks 145/146 replace it:
   - Remove `employee_type_master_id` from `schemas.py` / `service.py` (`_policy_out`, create, update).
   - `create_policy` (per leave type) attaches the new detail to the tenant's `DEFAULT` master
     (get-or-create it with its CDP-wide mapping); 409 if DEFAULT already has a rule for that type.
   - `update_policy` edits in place (the close-and-reinsert path would now violate the unique key).
   - `effctv_dt` / `applicable_after_days` None-safe wherever compared.
   - Test fixtures that create details create/attach a master.

NOT in scope: provider-mapping resolution (138), new CRUD APIs (139/140), year close (141),
encashment (142).

## Files
- `hrms/backend/app/models/leave_policy_master.py`, `leave_policy_provider_mapping.py` (new)
- `hrms/backend/app/models/leave_policy_detail.py`, `leave_type_master.py`, `__init__.py` (edit)
- `hrms/backend/alembic/versions/3c8e5a1f7d20_leave_policy_masters_provider_mappings.py`
- `hrms/backend/app/modules/leave/service.py`, `schemas.py` (bridge)
- `hrms/backend/app/tests/modules/test_leave.py` (fixtures)

## Acceptance criteria
- [x] Models match the DBML column-for-column; app imports cleanly.
- [x] Migration dry-run on hrms-dev (rolled back) converges to the target; second run is a no-op.
- [x] Migration applied to hrms-dev (2026-09-29, user-approved): 36 DEFAULT + 24 LEGACY_V<n>
      masters, 36 tenant-wide mappings, 52 current rules, 0 duplicate (policy, type) pairs.
- [x] Bridge in place; `test_leave.py` 176/176 green (incl. new: second rule for a type → 409,
      create-after-archive moves the old rule to a LEGACY policy, edit-in-place). New
      `test_new_organization_gets_template_leave_policies` green.

## Verification notes
- 5 existing apply/preview tests had hardcoded Sept-2026 dates that became backdated on
  2026-09-29 (unrelated to this task) — switched to `_upcoming_weekday()`.
- `create_leave_type`/`update_leave_type` used to report *any* IntegrityError as "code already
  exists"; now only `uq_leave_type_masters_cdp_code` maps to 409.
- Pre-existing, unrelated failures left as-is: `test_admin_organizations.py::
  test_new_organization_gets_industry_specific_hr_attribute_defaults` and
  `..._with_corporate_or_other_type_gets_cdp0_defaults` (department HR-attribute defaults come
  back empty — `_clone_attribute_defaults`, not leave). Worth a follow-up task.
- Local API container hot-reloads (`./backend/app` bind mount + `--reload`) — no rebuild needed.

## Split note (tasks 137–149)
137 schema + bridge · 138 resolution service · 139 policy master/detail API · 140 assignment
(mapping) API + resolution explainer · 141 leave-year close (carry-forward/expiry) · 142 encashment
· 143 accrual & apply-gate acceptance hardening · 144 frontend API client · 145 Admin Leave shell +
Leave Types page · 146 Admin Leave Policies list + stepper · 147 Admin Policy Assignments + conflict
view · 148 Employee/Manager portal consumption · 149 docs.
Screens by role: **HR Admin** (`hr_admin`) owns all configuration (145–147). **HR Manager**
(`hr_manager`) and **Employee** (`employee_portal`) only consume (148). No manual
balance-assignment screen anywhere.

Completed: 2026-09-29
