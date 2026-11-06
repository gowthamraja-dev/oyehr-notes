---
task: 323
title: Device punch direction — model and migration
status: done
depends_on: []
---

# 323 — Device punch direction: model + migration

## Scope
Add the one approved column to the `attendance_device_masters` model and migrate it. Contract: `.plans/device-punch-direction-schema.dbml` (approved 2026-11-02), plan `.plans/device-punch-direction-plan.md`.
Does NOT cover API, ingest or UI (tasks 324, 325). Paths relative to `workspace-2/hrms/`.

Column on `attendance_device_masters` (`AttendanceDeviceMaster`):
`punch_direction` — `String(10)`, NOT NULL, `server_default text("'Auto'")`, CHECK `ck_attendance_device_masters_punch_direction` = `punch_direction IN ('Auto','In','Out')`.
`In` = entry terminal, `Out` = exit terminal, `Auto` = today's behaviour. No new table, no index, no backfill (the default covers every existing row).

## Files
- `backend/app/models/attendance_device_master.py` — the column (with a comment saying what the three values mean) and the CHECK in `__table_args__`.
- `backend/alembic/versions/<new>_device_punch_direction.py` — generated, then reviewed.

## Rules
- No other model file; `app/models/__init__.py` already imports `AttendanceDeviceMaster`.
- Never hand-edit an applied migration. Check the file for unrelated drift that autogenerate picked up and remove it from this revision.
- Run through `uv run python scripts/migrate.py upgrade heads` (two heads: nhforms branch), not bare `alembic upgrade head`.
- `workspace-2/hrms/backend` has no `.venv` yet: `uv sync` first (CodeArtifact token needed for nhforms, see CLAUDE.md).
- Do not touch the shared hrms-dev DB without reading memory `reference-shared-hrms-dev-db.md`; prefer a scratch DB.

## Acceptance criteria
- [x] The model has the column and the CHECK exactly as above (`attendance_device_master.py`; confirmed from the loaded metadata: `VARCHAR(10)`, NOT NULL, default `'Auto'`, constraint `ck_attendance_device_masters_punch_direction`)
- [x] The migration `f4a8c2e6b913_device_punch_direction.py` (chained off `e8b3d5a1c704`, hand-written and existence-guarded like `a9e2d7f4b613`) contains only this column and CHECK and matches the DBML; ruff clean
- [ ] It applies on a fresh DB — NOT met as worded. `scripts/migrate.py upgrade heads` on an empty Postgres 18 stops at the earlier, unrelated migration `f2a9d4c7b180_seed_reference_data` (`field_type_masters: data set rows have no id — cannot sync`) before reaching this one. Verified instead on a scratch DB built from the models: column removed, a pre-existing device row inserted, then this migration's `upgrade()` run through Alembic — the old row reads `Auto`; a second run is a no-op
- [x] Downgrade drops the CHECK and the column cleanly; a second downgrade is a no-op; re-upgrade works
- [ ] `alembic check` is clean — NOT run as worded (needs a DB stamped at head, which the fresh-chain failure above prevents). Substituted: `compare_metadata` (compare_type + server defaults) on the scratch DB after `upgrade()` reports no drift for `attendance_device_masters`
- [x] The CHECK rejects `'Sideways'`, `'in'` and `''` and accepts `Auto` / `In` / `Out`; NULL is rejected by NOT NULL. Checked by a throwaway script, not a committed test; the committed tests are task 324's

## Verification notes (2026-11-02)
Scratch Postgres 18 container `hrms-ws2-scratch-pg` on 127.0.0.1:55432, started with the user's approval and removed afterwards; `DATABASE_URL` was overridden in the environment and the script refused to run unless the host/port/db were the scratch ones. The shared hrms-dev DB, the `hrms-api-1` container and the `.env` files were not touched at that point. Nothing is committed.

## Applied to the shared hrms-dev DB (2026-11-02)
At the user's explicit request. The shared DB (`hrms_dev`) is stamped at the orphan revision `8012104013b3`, so `alembic upgrade` cannot run there; the migration's own existence-guarded `upgrade()` was run through `alembic.operations.Operations` in ONE transaction with `lock_timeout = 5s`, and the stamp was left alone (still `8012104013b3`).
- Read-only check first: table present with 10 rows; neither the column nor the CHECK existed.
- After: `punch_direction` is `VARCHAR(10)`, NOT NULL, default `'Auto'`; CHECK `ck_attendance_device_masters_punch_direction` allows `Auto` / `In` / `Out`; all 10 existing rows read `Auto`.
- Not done there: no `compare_metadata` run against the shared DB, and no backup_user grant change (an existing gap, unrelated to this column, since the table is old).
- The two criteria above marked NOT met as worded (fresh-DB `upgrade heads`, `alembic check`) stay unmet; they were verified by the substitutes described there. The `f2a9d4c7b180_seed_reference_data` fresh-chain failure is unrelated to this task and still open.

Completed: 2026-11-02
