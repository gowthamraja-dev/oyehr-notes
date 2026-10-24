-- Task 248 — hand-applied copy of alembic revision b83f6d1c0e47 for the SHARED hrms-dev DB
-- (stamped at the orphan revision 8012104013b3, so `alembic upgrade` can't reach it).
-- Existence-guarded and re-runnable. NOT APPLIED — run only with the owner's go-ahead.
-- Additive: no data is rewritten; every existing site gets is_remote = false.
BEGIN;
ALTER TABLE work_location_masters ADD COLUMN IF NOT EXISTS is_remote boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS ix_work_location_masters_one_remote_per_cdp
  ON work_location_masters (care_delivery_program_master_id)
  WHERE is_remote = true AND archive = false;
ALTER TABLE work_location_masters DROP CONSTRAINT IF EXISTS ck_work_location_masters_remote_not_default;
ALTER TABLE work_location_masters
  ADD CONSTRAINT ck_work_location_masters_remote_not_default CHECK (NOT (is_remote AND is_org_default));
COMMIT;

-- Roll back:
-- ALTER TABLE work_location_masters DROP CONSTRAINT IF EXISTS ck_work_location_masters_remote_not_default;
-- DROP INDEX IF EXISTS ix_work_location_masters_one_remote_per_cdp;
-- ALTER TABLE work_location_masters DROP COLUMN IF EXISTS is_remote;
