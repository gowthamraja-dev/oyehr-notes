---
task: 261
title: Attendance import — models and migration
status: done
depends_on: []
---

# 261 — Attendance import — models and migration

## Scope
Implement `.plans/attendance-bulk-import-schema.dbml` exactly: three new tables and one new column.
Does NOT cover any service/endpoint code (tasks 262–264).

New tables (one model file each, registered in `app/models/__init__.py`):
- `attendance_import_batches` → `attendance_import_batch.py` / `AttendanceImportBatch`: id, care_delivery_program_master_id (FK, NN),
  file_name varchar(255) NN, status varchar(12) NN default 'Validating', existing_day_policy varchar(10) NN default 'Skip',
  override_locked bool NN default false, override_reason varchar(500), row_count/rows_rejected/rows_imported/punches_inserted/
  days_total/days_recomputed/days_failed int NN default 0, last_error text, started_at/heartbeat_at/finished_at/undone_at tz,
  undone_by_id FK users, is_active NN true, archive NN false, archived_by_id bigint, archived_at, created_by_id/updated_by_id FK users,
  created_at, updated_at. Indexes `ix_attendance_import_batches_cdp_created` (cdp, created_at), `ix_attendance_import_batches_open`
  (cdp, status) WHERE status IN ('Running','Failed','Validating','Undoing').
- `attendance_import_field_mappings` → `attendance_import_field_mapping.py`: id, attendance_import_batch_id FK NN, column_name varchar(255) NN,
  target_field varchar(20) NN, created_at; unique `uq_attendance_import_field_mappings_batch_target` (batch, target_field).
- `attendance_import_rows` → `attendance_import_row.py`: id, care_delivery_program_master_id FK NN, attendance_import_batch_id FK NN,
  row_number int NN, row_data jsonb NN, employee_master_id FK null, attendance_date date null, in_at/out_at timestamptz null,
  times_from_shift bool NN default false, status varchar(10) NN default 'Pending', validation_errors jsonb null, created_at;
  unique `uq_attendance_import_rows_batch_row` (batch, row_number); `ix_attendance_import_rows_batch_status` (batch, status);
  `ix_attendance_import_rows_cdp` (cdp).
Existing: `attendance_punch_details.import_batch_id` bigint NULL FK → attendance_import_batches.id, no default; partial index
`ix_attendance_punch_details_import_batch` (import_batch_id, processed_at) WHERE import_batch_id IS NOT NULL.

## Files
- `backend/app/models/attendance_import_batch.py`, `attendance_import_field_mapping.py`, `attendance_import_row.py` (new)
- `backend/app/models/attendance_punch_detail.py` (add column + index), `backend/app/models/__init__.py`
- `backend/alembic/versions/<rev>_attendance_bulk_import.py` — hand-written, existence-guarded (the shared hrms-dev DB cannot be
  `alembic upgrade`d — CLAUDE.md); the punch FK added `NOT VALID` then `VALIDATE CONSTRAINT`.

## Acceptance criteria
- [x] Models match the DBML column-for-column (server_default on every NOT NULL default, `onupdate` on updated_at)
- [x] Migration reviewed, existence-guarded, down_revision = current head chosen deliberately (two heads exist: a4c9e2d7b350, e2a8c4f6b913)
- [x] DDL applied to the dev DB the tests use; `\d` shows the tables, indexes and the new punch column
- [x] `scripts/migrate.py heads`: b5d1f8a3c726 replaces e2a8c4f6b913 as a head, no extra head; models vs DB diff for these objects = 0 (compare_metadata)

Completed: 2026-10-26
Note: applied to the local test DB (hrms-test-pg :5433) by running the migration's guarded upgrade() directly, twice (idempotent); that DB is not alembic-upgradable. Chained onto e2a8c4f6b913, not merged with a4c9e2d7b350.
