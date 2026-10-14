---
task: 89
title: status_master_id on leave requests + tenant/audit columns on leave day details
status: done
depends_on: [42]
---

# 89 — status_master_id on leave requests + tenant/audit columns on leave day details

## Discussion

A finalized DBML schema for `leave_request_details`, `leave_request_day_details` and
`employee_leave_balance_ledgers` was cross-checked column-by-column against the live models
from [[42-leave-request-ledger-models-migration]]. `employee_leave_balance_ledgers` matches
exactly — no work needed there. Two real deltas exist, and both are designs already written
down in the docs but never carried into the models/migration when 42 shipped — not new asks:

1. **`leave_request_details.status_master_id`** — `docs/leave-and-attendance/shared/
   status-masters-and-seeding.md` §2 already *decides* this column: the free-text `status`
   column stays the write authority; `status_master_id` is a derived, nullable lookup populated
   by the service layer from an in-process cache — "must never be the source of truth." The
   column was simply never added.
2. **`leave_request_day_details`** currently has no tenant column and no audit columns at all
   (deliberate per 42's own note: "No `is_active`/`archive` — rows live and die with the parent
   request"). The finalized schema adds `care_delivery_program_master_id` (NOT NULL),
   `is_active`, `archive`, `created_by_id`, `updated_by_id`, `created_at`, `updated_at` — which
   matches `leave/domain-model.md`'s opening statement that *every* leave table carries the
   tenant column plus the house audit set. 42 built this table as a deliberate exception to that
   rule; the finalized schema reverses the exception.

**Explicitly out of scope for this task:**
- Actually populating `status_master_id` anywhere in `leave/service.py`. That needs two pieces
  of shared infra that don't exist anywhere in the repo yet: the `status_masters` seed script
  (`shared/status-masters-and-seeding.md` §4, `backend/scripts/seed_attendance_leave_masters.py`
  — confirmed not present) and the in-process `(source_activity, status_code)` lookup cache
  (§2.2 — confirmed not present). `status_masters` has zero rows and zero consumers today, and
  the identical mechanism is also needed by `attendance_request_details`/
  `employee_attendance_details`, so building it just for leave here would likely be redone —
  that's its own follow-up task. Leave `status_master_id` NULL on every row until then.
- Rebuilding day rows when a `Pending` request is edited — that flow doesn't exist in
  `leave/service.py` yet (`LeaveRequestDayDetail` is only ever constructed once, in
  `apply_for_leave`).
- Any archival logic that would actually flip the new `is_active`/`archive` columns to a
  non-default value (e.g. on cancellation). Adding the columns is schema-only; deciding what
  "archiving a day row" means is a separate product decision. Whoever picks this up should
  raise it rather than silently deciding — today's cancel flow leaves day rows untouched and
  relies on the ledger's `Reversal` rows for correction instead.

## Files

- `backend/app/models/leave_request_detail.py` — add `status_master_id: Mapped[int | None]`,
  `ForeignKey("status_masters.id")`, indexed.
- `backend/app/models/leave_request_day_detail.py` — add `care_delivery_program_master_id`
  (`ForeignKey("care_delivery_program_masters.id")`, NOT NULL, indexed — tenant), `is_active`
  (`Boolean`, `server_default=text("true")`), `archive` (`Boolean`, `server_default=text("false")`),
  `created_by_id`/`updated_by_id` (`BigInteger`, nullable), `created_at`/`updated_at`
  (`DateTime(timezone=True)`, `server_default=func.now()`, `updated_at` also
  `onupdate=func.now()`). Update the class docstring — it currently reads "One immutable
  calendar-day calculation row"; that's no longer accurate once it carries a lifecycle set.
- New Alembic revision under `backend/alembic/versions/` — generate with
  `uv run python scripts/migrate.py revision --autogenerate -m "..."` (not bare `alembic`, per
  CLAUDE.md's nhforms two-head rule), then hand-review before applying with
  `uv run python scripts/migrate.py upgrade heads`.
- `backend/app/modules/leave/service.py` — the one `LeaveRequestDayDetail(...)` construction
  site in `apply_for_leave` (~line 1251) must start passing
  `care_delivery_program_master_id=principal.tenant_id` and `created_by_id=principal.user.id`,
  mirroring how the `LeaveRequestDetail`/`LeaveRequestAudit` inserts a few lines above it
  already do — required because the new tenant column is NOT NULL.
- `backend/app/tests/modules/test_leave.py` — extend apply-flow assertions to cover the new
  day-detail columns (tenant id matches the request's, `created_by_id` matches the applying
  principal).

## Migration notes

`care_delivery_program_master_id` on `leave_request_day_details` is NOT NULL per the finalized
schema, but existing rows have nothing to autogenerate it from. The migration must, in one
file: add the column nullable → backfill (`UPDATE leave_request_day_details d SET
care_delivery_program_master_id = r.care_delivery_program_master_id FROM leave_request_details
r WHERE r.id = d.leave_request_detail_id`) → `ALTER COLUMN ... SET NOT NULL`. This is a
data-touching step inside an otherwise pure-DDL migration — call it out in the PR description.
`shared/status-masters-and-seeding.md` §4.1 records a repo-wide preference against data
migrations, but that section is about seed/reference data, not a structural backfill from a
sibling row — don't let it block this backfill, just don't reuse this migration as precedent
for seeding.

## Acceptance criteria

- [x] `LeaveRequestDetail.status_master_id` exists: nullable, FK to `status_masters.id`, indexed.
- [x] `LeaveRequestDayDetail` has `care_delivery_program_master_id` (NOT NULL, FK, indexed),
      `is_active`, `archive`, `created_by_id`, `updated_by_id`, `created_at`, `updated_at`.
- [x] Migration applies cleanly against a dev DB that already has `leave_request_day_details`
      rows, backfills them correctly (verified via a live `information_schema.columns` query,
      not `psql` directly), and `scripts/migrate.py downgrade d93cf6d767df` reverses cleanly —
      confirmed both directions round-trip. The autogenerated `op.create_foreign_key(None, ...)`
      / `op.drop_constraint(None, ...)` pattern copied from 42's migration turned out to be
      broken for downgrade with no `naming_convention` configured on `Base.metadata` (Alembic
      can't resolve an unnamed constraint to drop) — fixed by naming the two new FK constraints
      explicitly instead of passing `None`. Worth flagging: any other migration in this repo
      using that same `None`-named pattern likely has the same latent downgrade bug, undiscovered
      because downgrades are rarely exercised.
- [x] `apply_for_leave` populates the two new day-detail columns on every inserted row — covered
      by new test `test_apply_populates_day_detail_tenant_and_created_by`.
- [x] A grep for `status_master_id` in `backend/app/` outside the model/migration turns up
      nothing new — the pattern already exists identically on `attendance_request_details` /
      `employee_attendance_details` ("derived lookup only, never written in v1").
- [x] `uv run pytest app/tests/modules/test_leave.py app/tests/modules/test_attendance_recompute.py`
      — 185 passed. Also had to fix pre-existing direct `LeaveRequestDayDetail(...)` construction
      in several test helpers (both files) that predated the new NOT NULL tenant column.
      `test_job_runner.py` was run too but has 3 failures unrelated to this task — it needs the
      `nt_schedulers_job_logs` table from a separate, still-uncommitted migration
      (`f3a1c9d8e7b2`, a different head off `6aab37626856`) that was never applied to this DB;
      not touched here. `scripts/migrate.py heads` still shows the same pre-existing multiple
      heads as before this task (this one just replaced `d93cf6d767df` with `f0d3c1cf09f4` as
      the leave chain's tip) — no new conflict introduced.

Also found and fixed, as a prerequisite for running any Alembic command at all: the shared dev
DB's `alembic_version` table carried a stray row (`003_rbac_id_identity`) matching no migration
file in the repo's history, which broke `alembic current`/`revision --autogenerate`/`upgrade`
entirely. Removed after explicit user confirmation (not part of this task's original scope, but
blocking).

Completed: 2026-08-27
