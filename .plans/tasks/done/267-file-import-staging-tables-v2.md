---
task: 267
title: File import — type-agnostic staging tables (models + migration, replaces task 261's tables)
status: done
depends_on: []
---

# 267 — File import — type-agnostic staging tables

## Scope
Implement `.plans/attendance-bulk-import-schema-v2.dbml` exactly, **after it is approved**. Replaces the v1 tables built by task 261
(`done/261-…`, left as the record of what was built then). Does NOT touch engine/handler code (268).

Tables (one model file each, registered in `app/models/__init__.py`; v1 files deleted):
- `import_batches` → `import_batch.py` / `ImportBatch`: id, care_delivery_program_master_id FK NN, import_type varchar(30) NN (no default),
  file_name varchar(255) NN, status varchar(12) NN default 'Validating', options jsonb NN default '{}', row_count/rows_rejected/rows_imported/
  units_total/units_done/units_failed int NN default 0, stats jsonb NN default '{}', last_error text, started_at/heartbeat_at/finished_at/undone_at tz,
  undone_by_id FK users, is_active NN true, archive NN false, archived_by_id bigint, archived_at, created_by_id/updated_by_id FK users, created_at,
  updated_at (onupdate). Indexes `ix_import_batches_cdp_type_created` (cdp, import_type, created_at); `ix_import_batches_open` (cdp, status)
  WHERE status IN ('Validating','Running','Failed','Undoing').
- `import_field_mappings` → `import_field_mapping.py`: id, import_batch_id FK NN, column_name varchar(255) NN, target_field varchar(40) NN, created_at;
  unique `uq_import_field_mappings_batch_target` (import_batch_id, target_field).
- `import_rows` → `import_row.py`: id, care_delivery_program_master_id FK NN, import_batch_id FK NN, row_number int NN, row_data jsonb NN,
  reference_id bigint null (logical), dedupe_key varchar(120) null, parsed jsonb null, status varchar(10) NN default 'Pending', validation_errors jsonb null,
  created_at; unique `uq_import_rows_batch_row`; `ix_import_rows_batch_status` (batch, status); `ix_import_rows_batch_dedupe` (batch, dedupe_key)
  WHERE dedupe_key IS NOT NULL; `ix_import_rows_cdp`.
- `attendance_punch_details.import_batch_id`: FK retargeted to `import_batches.id` (added NOT VALID then VALIDATE); index
  `ix_attendance_punch_details_import_batch` unchanged.

Migration (decision Q1 in the DBML, recommended): delete `alembic/versions/b5d1f8a3c726_attendance_bulk_import.py`, drop the v1 tables and the punch
column/FK/index from the local test DB (`hrms-test-pg`, test data only), write one hand-written existence-guarded revision creating v2, and re-parent
`c3a7e1d9f402` (RBAC row) onto it. Apply the guarded `upgrade()` directly to the local DB (it is not alembic-upgradable), twice.

## Files
`backend/app/models/{import_batch,import_field_mapping,import_row}.py` (new), v1 `attendance_import_*.py` models (deleted), `attendance_punch_detail.py`,
`models/__init__.py`, `backend/alembic/versions/` (v1 revision removed, v2 revision added, `c3a7e1d9f402` re-parented).

## Acceptance criteria
- [x] Models match the DBML column-for-column (server_default on every NOT NULL default, `onupdate` on updated_at)
- [x] Migration reviewed, existence-guarded, applies twice cleanly to the local DB; `compare_metadata` shows 0 diffs for these objects
- [x] `scripts/migrate.py heads`: no new unexpected head; `c3a7e1d9f402` chains onto the new revision
- [x] No reference to `attendance_import_*` tables remains in models or migrations

Completed: 2026-10-26
Note: v1 revision b5d1f8a3c726 and its models deleted, its tables dropped from the local test DB (hrms-test-pg :5433); new revision d4e8b2a6f913 (chained on e2a8c4f6b913) created the v2 tables and was applied by running its guarded upgrade() twice. c3a7e1d9f402 (RBAC row) re-parented onto d4e8b2a6f913. heads: a4c9e2d7b350, c3a7e1d9f402, b7c1e0f4d92a (nhforms).
