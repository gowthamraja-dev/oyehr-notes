---
task: 21
title: Leave Policy — models & migration (leave_type_masters, leave_policy_details, leave_policy_audits)
status: done
depends_on: []
---

# 21 — Leave Policy — models & migration

## Scope

This task carves the **Leave Policies Admin Flow** out of the P2P prompt at
`.design/prompts/P2P Full-Stack Development Prompt — Leave Policies Admin Flow.md`, narrowed to
what that prompt's own §40 ("Do Not Implement These in This Task") allows: leave **type +
policy configuration** only. It explicitly does NOT cover `leave_request_details`,
`leave_request_day_details`, or `employee_leave_balance_ledgers` — those belong to the request/
approval/ledger slice already speced in `docs/leave-and-attendance/leave/ledger.md` and
`api-and-pages.md`, which is a separate, much larger effort (leave request apply/approve/reject,
the balance ledger, employee self-service) not started by this task chain.

**Important — a fuller spec already exists and supersedes the prompt file where they differ:**
`docs/leave-and-attendance/leave/` (`domain-model.md`, `admin-configuration.md`, `gaps.md`,
`api-and-pages.md`) already reconciles the same mockup/schema conflicts the prompt raises, with
explicit decisions on the open questions the prompt leaves vague. This task follows the doc's
decisions, cross-referenced below. Read `domain-model.md` §5.1–5.2 and `gaps.md` #4 and #34
before writing the model files.

Nothing under `backend/app/models/`, `backend/alembic/versions/`, or the DB currently has these
tables — confirmed via `find backend/app/models -iname "*leave*"` (nothing but a stale
`.pyc`) and `grep -rl leave backend/alembic/versions/` (no hits). This is a green-field
migration, not a rework.

This task covers **only** models + migration. Backend services/routers are task
[[22-leave-type-api]] and [[23-leave-policy-api]].

## Files

- `backend/app/models/leave_type_master.py` — new, class `LeaveTypeMaster`, table
  `leave_type_masters`
- `backend/app/models/leave_policy_detail.py` — new, class `LeavePolicyDetail`, table
  `leave_policy_details`
- `backend/app/models/leave_policy_audit.py` — new, class `LeavePolicyAudit`, table
  `leave_policy_audits`
- `backend/app/models/__init__.py` — register all three (append after the `holiday_detail`
  import, the last line currently in the file)
- `backend/alembic/versions/<new>.py` — generated via `uv run alembic revision --autogenerate`,
  then hand-reviewed

## Column specs

### `leave_type_masters`

The type's **request/application rules** (per `docs/leave-and-attendance/leave/admin-configuration.md`
§5.1). One row per tenant-defined leave type — `CL`/`SL`/`EL`/`ML`/`LOP` are seed examples, not an
enum; tenants define their own codes.

| Column | Type | Null | Default |
| --- | --- | --- | --- |
| `id` | `BigInteger` PK | — | — |
| `care_delivery_program_master_id` | `BigInteger` FK `care_delivery_program_masters.id`, indexed | NOT NULL | — |
| `name` | `String(255)` | NOT NULL | — |
| `code` | `String(20)` | NOT NULL | — |
| `is_paid` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `unit` | `String(10)` | NOT NULL | `server_default=text("'Day'")` — only `Day` is usable in v1 ([gaps.md #14](../../docs/leave-and-attendance/leave/gaps.md)); column allows `Hour` at the DB layer but no service code interprets it yet, don't build that interpretation |
| `allow_half_day` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `requires_approval` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `requires_document` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `doc_required_after_days` | `Integer` | nullable | — |
| `max_consecutive_days` | `Integer` | nullable | — |
| `min_notice_days` | `Integer` | NOT NULL | `server_default=text("0")` |
| `allow_negative_balance` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `gender_applicable` | `String(10)` | nullable | — values `Male`/`Female`/`Other`, `NULL` = no restriction. **Known gap** ([gaps.md #34](../../docs/leave-and-attendance/leave/gaps.md)): `employee_masters.gndr` (`app/models/employee_master.py:26`) is an unconstrained free `String(20)` with no seeded vocabulary anywhere in the codebase today. Do not invent enforcement here beyond validating this column's own values at the API layer — matching against `gndr` at request time is out of scope (no request flow exists yet) |
| `applicable_after_days` | `Integer` | NOT NULL | `server_default=text("0")` — probation/eligibility gate |
| `exclude_week_offs` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `exclude_holidays` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `display_order` | `Integer` | NOT NULL | `server_default=text("0")` |
| `color_code` | `String(9)` | nullable | hex, e.g. `#4C6FBF` |
| `is_active` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `effctv_dt` | `Date` | NOT NULL | — |
| `trmntn_dt` | `Date` | nullable | — |
| `archive` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `archived_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `archived_at` | `DateTime(timezone=True)` | nullable | — |
| `created_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `updated_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `created_at` | `DateTime(timezone=True)` | NOT NULL | `server_default=func.now()` |
| `updated_at` | `DateTime(timezone=True)` | NOT NULL | `server_default=func.now()`, `onupdate=func.now()` |

Constraint: `UniqueConstraint("care_delivery_program_master_id", "code", name="uq_leave_type_masters_cdp_code")`.

### `leave_policy_details`

The **entitlement/accrual** layer, split from the type because accrual varies by corp/employee
type within one leave type (`domain-model.md` §5.2). One or more rows per leave type.

| Column | Type | Null | Default |
| --- | --- | --- | --- |
| `id` | `BigInteger` PK | — | — |
| `care_delivery_program_master_id` | `BigInteger` FK `care_delivery_program_masters.id`, indexed | NOT NULL | — |
| `leave_type_master_id` | `BigInteger` FK `leave_type_masters.id`, indexed | NOT NULL | — |
| `corp_master_id` | `BigInteger` FK `corp_masters.id` | nullable | `NULL` = all corporations |
| `employee_type_master_id` | `BigInteger` (**plain, no FK** — no employee-type master table exists yet, per CLAUDE.md's rule for masters that don't exist yet) | nullable | `NULL` = all employee types. **v1 always leaves this NULL** ([gaps.md #4](../../docs/leave-and-attendance/leave/gaps.md)) — the create/update schemas in [[23-leave-policy-api]] accept it but the resolution service only branches on `corp_master_id` |
| `accrual_frequency` | `String(20)` | NOT NULL | one of `Monthly`/`Quarterly`/`Yearly`/`OnJoining`, enforced at API layer, plain column at DB layer |
| `accrual_quantity` | `Numeric(6,2)` | NOT NULL | `server_default=text("0")` — **per-period**, not annual (a "21 days/year, monthly accrual" policy stores `1.75`, not `21`, in this column — see `admin-configuration.md` §5.2's warning) |
| `max_balance` | `Numeric(6,2)` | nullable | the annual-quota cap shown as "Annual quota 21" in the mockup |
| `carry_forward` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `max_carry_forward` | `Numeric(6,2)` | nullable | must be `NULL` when `carry_forward=false` — enforced in [[23-leave-policy-api]], not a DB constraint |
| `encashable` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `max_encashment` | `Numeric(6,2)` | nullable | must be `NULL` when `encashable=false` — enforced in [[23-leave-policy-api]] |
| `prorate_on_joining` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `reset_month` | `Integer` | nullable | `1`–`12`, enforced at API layer |
| `is_active` | `Boolean` | NOT NULL | `server_default=text("true")` |
| `effctv_dt` | `Date` | NOT NULL | — |
| `trmntn_dt` | `Date` | nullable | must be `>= effctv_dt` when set — enforced in [[23-leave-policy-api]] |
| `archive` | `Boolean` | NOT NULL | `server_default=text("false")` |
| `archived_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `archived_at` | `DateTime(timezone=True)` | nullable | — |
| `created_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `updated_by_id` | `BigInteger` FK `users.id` | nullable | — |
| `created_at` | `DateTime(timezone=True)` | NOT NULL | `server_default=func.now()` |
| `updated_at` | `DateTime(timezone=True)` | NOT NULL | `server_default=func.now()`, `onupdate=func.now()` |

No DB-level overlap constraint (Postgres can't easily express the corp-specificity precedence
rule as a constraint) — overlap validation is entirely service-layer, in
[[23-leave-policy-api]].

### `leave_policy_audits` — append-only

Mirrors the existing `shift_assignment_audits` pattern (`backend/app/models/shift_assignment_audit.py`)
— one row per successful policy mutation, per the prompt's §26 and no generic audit table exists
in this codebase to reuse (confirmed: no `audit` hits under `backend/app/` outside per-feature
tables like this one).

| Column | Type | Null | Default |
| --- | --- | --- | --- |
| `id` | `BigInteger` PK | — | — |
| `care_delivery_program_master_id` | `BigInteger` FK `care_delivery_program_masters.id`, indexed | NOT NULL | — |
| `leave_policy_detail_id` | `BigInteger` FK `leave_policy_details.id`, indexed | NOT NULL | — |
| `leave_type_master_id` | `BigInteger` FK `leave_type_masters.id`, indexed | NOT NULL | denormalized for cheap "audit for this leave type" queries without a join |
| `action` | `String(20)` | NOT NULL | `CREATED` \| `UPDATED` \| `ACTIVATED` \| `DEACTIVATED` |
| `changes` | `String(2000)` | nullable | human-readable diff summary, e.g. `"accrual_quantity: 1.5 -> 1.75"` — plain text, **not JSONB** (CLAUDE.md §41 bans JSONB for policy config; this is an audit trail, not config, but keep it consistent and simple) |
| `performed_by_id` | `BigInteger` FK `users.id` | NOT NULL | — |
| `created_at` | `DateTime(timezone=True)` | NOT NULL | `server_default=func.now()` |

No `updated_at`, no archive columns — append-only, never edited after insert, same as
`ShiftAssignmentAudit`.

## Acceptance criteria

- [ ] All three model files exist, one class per file, registered in `backend/app/models/__init__.py`
- [ ] `uv run alembic revision --autogenerate -m "add leave policy tables"` produces a migration
      containing exactly these three `CREATE TABLE`s (plus their indexes/FKs/unique constraint) —
      review the generated file before applying; it must not touch any other table
- [ ] `uv run alembic upgrade head` applies cleanly against the dev DB
- [ ] `uq_leave_type_masters_cdp_code` unique index exists on `(care_delivery_program_master_id, code)`
- [ ] No column uses JSONB
- [ ] `docker compose up --build -d api` starts cleanly with the new models importable

Completed: 2026-08-17
