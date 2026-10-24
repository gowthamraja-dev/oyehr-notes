---
task: 248
title: Work location "remote" flag — model, migration, work-location API rules
status: done
depends_on: []
---

# 248 — Work location "remote" flag — model, migration, work-location API rules

First task of `.plans/shift-wfh-plan.md`. Implements the approved `.plans/shift-wfh-schema.dbml` **exactly**.

## Contract (restated from the approved DBML)
`work_location_masters` gains:
- `is_remote boolean NOT NULL DEFAULT false` — HR-set; the tenant's remote / work-from-home site.
- partial unique index `ix_work_location_masters_one_remote_per_cdp` on `(care_delivery_program_master_id)`
  `WHERE is_remote = true AND archive = false` — also the lookup path for "this tenant's remote site".
- CHECK `ck_work_location_masters_remote_not_default`: `NOT (is_remote AND is_org_default)`.
No other table changes. No backfill (default false).

## Rules (decided 24-Oct-26)
- At most one live remote site per tenant. Setting `is_remote = true` while another live site holds it → **409**
  naming that site; the DB index is the race backstop (map the IntegrityError to the same 409).
- The org-default site can't be remote → 422 (the CHECK is the backstop).
- A remote site must have `mobile_punch_check_mode = 'NoCheck'`, so employees can clock in from home. Also
  `web_punch_check_mode = 'NoCheck'` whenever `web_punch_enabled` is true (plan §7 — confirm). Enforced in the
  service, not as a DB CHECK. While a site is remote, changing either mode away from NoCheck is refused (422).
- Archiving the remote site stays allowed (frees the unique-index slot).
- `organizations.service._sync_default_work_location` never sets or clears the flag; its default-site lookup is unchanged.
- Every lookup of the remote site filters `care_delivery_program_master_id = principal.tenant_id`,
  `is_remote`, `NOT archive`, `is_active`. Expose one helper, e.g. `get_remote_work_location(db, tenant_id)`
  in `attendance/service.py`, for task 247 to call.

## Files
- `backend/app/models/work_location_master.py` — column, index in `__table_args__`, CheckConstraint.
- `backend/alembic/versions/<new>_work_location_is_remote.py` — upgrade/downgrade (downgrade drops index,
  constraint, column). Review the autogenerate output: it also proposes unrelated DROPs/renames — keep only this change.
- `backend/app/modules/attendance/schemas.py` — `is_remote` on `WorkLocationIn` (default False), `WorkLocationPatch`
  (optional), `WorkLocationOut` (`is_remote: bool = False`).
- `backend/app/modules/attendance/service.py` — create/update rules above, `_work_location_out` carries the field, the helper.
- `backend/app/tests/modules/test_attendance_work_locations*.py` (follow the existing work-location tests).
- Docs: `docs/leave-and-attendance/attendance/` api-and-pages (work-location rows) and the model/domain doc that
  lists `work_location_masters` columns.
- **hrms-dev DB:** a hand-written, existence-guarded copy of the DDL (add column `IF NOT EXISTS`, create the
  index and constraint only if missing) for the shared dev DB, which can't be `alembic upgrade`d (stamped at
  `8012104013b3`; see CLAUDE.md). **Applying it to the shared DB is outward-facing — do it only after the
  user says so; until then run everything against the local `hrms-test-pg` container.**

## Tests
Happy path (create + patch to remote; `Out` returns it); second live remote → 409 naming the first; archive the
first then another succeeds; archived site doesn't count; org-default → 422; non-NoCheck mobile mode → 422; web
enabled with Geofence → 422; changing the mode away on a remote site → 422; non-remote sites unaffected;
**cross-tenant** (two tenants each hold a remote site; patching the other tenant's site → 404); 401 / 403 with a
configured read-only grid; DB-level: raw insert of a second live remote row fails the index, raw
`is_remote AND is_org_default` fails the CHECK; the helper returns None when the tenant has none / only archived.

## Acceptance criteria
- [x] Model + migration match the approved DBML; migration reviewed (only this change), downgrade works
- [x] Migration applies on a fresh DB (`scripts/migrate.py upgrade heads`; on a fresh DB the seed revision needs
      `upgrade b7c1e0f4d92a` first, then `heads`) and `alembic check` is clean for this change
- [x] Work-location API accepts/returns `is_remote` with every rule above, tenant-scoped
- [x] Tests above pass; existing work-location / attendance tests still pass
- [x] Docs updated
- [x] Guarded hrms-dev DDL written and ready; **not applied** without the user's go-ahead

## Implementation notes (24-Oct-26)
- Model: `is_remote` + `ix_work_location_masters_one_remote_per_cdp` + CHECK in `work_location_master.py`.
- Migration `alembic/versions/b83f6d1c0e47_work_location_is_remote.py` (down_revision `9c1d4e7a2b36`), hand-written and
  existence-guarded like `e5b2c8a14f70`. Verified on the local `hrms-test-pg` with `scripts/migrate.py`: upgrade,
  downgrade (column, index and constraint all gone), upgrade again, and re-running the upgrade over objects that already
  exist. `migrate.py` has no `check`, so drift was checked by autogenerating a throw-away revision: nothing on
  `work_location_masters` (only unrelated pre-existing drift, e.g. `work_location_network_details`); the file was deleted.
- API: `is_remote` on `WorkLocationIn` (default false) / `Patch` (optional; an explicit null means "leave it") / `Out`.
  `attendance.service`: `get_remote_work_location`, `_assert_remote_site_rules` (org default 422, app mode 422, web mode
  422 when web is on, second holder 409 naming it), `_flush_or_remote_conflict` (a race on the index → the same 409). The
  rules run after the assignments so one PATCH can flip the flag and switch the modes together. A refused PATCH calls
  `db.expire(loc)` so the row shows its stored values — the shared test session otherwise made it look applied.
- Plan §7 extension applied: the same `NoCheck` rule covers web clock-in while `web_punch_enabled` is true (to confirm).
- Not covered by a test: `organizations._sync_default_work_location` leaving a remote site alone. Read, not run — it selects
  only `is_org_default` rows and never writes `is_remote`; the CHECK stops one row being both.
- Tests: 14 new (16 cases) in `test_attendance.py` (defaults, create/patch, same-request No check, null patch, second holder 409,
  archive frees the slot, org default, app modes × 3, web mode, mode can't leave NoCheck, per-tenant isolation +
  cross-tenant PATCH 404, 401/403, DB backstops for the index and the CHECK, race → 409). Run: attendance +
  shifts + encryption all pass. `test_organizations.py` has 9 failures that expect empty settings and see rows from the
  seeded local DB — unrelated to this change.
- Docs: `attendance/domain-model.md` §2.1 (field table + remote-site rules), `attendance/api-and-pages.md` (POST/PATCH rows).
- hrms-dev: `.plans/shift-wfh-hrms-dev.sql` written (guarded, re-runnable, with rollback lines) and run on the LOCAL
  container only. **Not applied to the shared dev DB.**
