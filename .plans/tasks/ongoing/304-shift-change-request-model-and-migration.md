---
task: 304
title: Shift change requests — model columns + migration
status: ongoing
depends_on: []
---

# 304 — Shift change requests: model + migration

## Scope
Implement the approved schema `.plans/my-shifts-schema.dbml` **exactly**. On `attendance_request_details` (model
`AttendanceRequestDetail`) add:
- `requested_shift_master_id` bigint NULL, `ForeignKey("shift_masters.id")` — the shift asked for.
- `current_shift_master_id` bigint NULL, `ForeignKey("shift_masters.id")` — the shift the employee was on at submit time (snapshot).
- CHECK `ck_attendance_request_details_shift_change_shifts`:
  `(request_type = 'ShiftChange') = (requested_shift_master_id IS NOT NULL AND current_shift_master_id IS NOT NULL) AND (request_type <> 'ShiftChange' OR from_date = to_date)`.
- No new index. Update the class docstring (`ShiftChange` is now a written request_type; one day; the two columns).
Existing rows: both columns NULL and request_type never `ShiftChange`, so the CHECK holds; no backfill.

Not covered: any API (305, 306).

## Files
- `backend/app/models/attendance_request_detail.py`
- `backend/alembic/versions/<rev>_shift_change_request_columns.py` — hand-written and existence-guarded (the shared hrms-dev DB is stamped at the
  orphan `8012104013b3` and cannot be `alembic upgrade`d; see CLAUDE.md "Migration workflow" and memory note on the shared hrms-dev DB).
  `down_revision` = the current HRMS head (check `uv run python scripts/migrate.py heads`).

## Acceptance criteria
- [ ] Migration matches the DBML and has been reviewed
- [ ] Applies on a fresh DB (`scripts/migrate.py upgrade heads`) and is re-runnable on a DB that already has the columns
- [ ] `alembic check` shows no drift for this table
- [x] CHECK rejects: ShiftChange with a NULL shift, ShiftChange with from_date != to_date, a non-ShiftChange row with a shift id set is allowed to be NULL only (verified by a test)
- [x] Existing Regularization / WFH rows unaffected

## Progress (2026-10-29)
Model columns + CHECK and migration `e8b3d5a1c704` written (chained after `d5e9a1c7f302`, existence-guarded). Applied by calling its `upgrade()` twice against the LOCAL `hrms-test-pg` (the second run was a no-op); the CHECK is exercised by 4 failing-insert cases in `test_my_shifts.py`. STILL OPEN: reviewing the migration against the DBML with you, applying it on a fresh DB through `scripts/migrate.py upgrade heads`, and `alembic check` (the local test DB has no `alembic_version`, so it can't run there). The shared hrms-dev DB has NOT been touched — apply the same guarded DDL there only when you ask.
Not committed.

### Shared hrms-dev DB (2026-10-29, on the user's request)
Applied `e8b3d5a1c704`'s guarded DDL by calling its `upgrade()` through `alembic.operations.Operations` in ONE transaction (`SET LOCAL lock_timeout = '5s'`); the stamp `8012104013b3` was left alone. Inspected read-only first: both columns and the CHECK were absent, 254 existing rows (240 Regularization, 14 WFH). After: both columns bigint NULL with their FKs, the CHECK present and validated, row counts unchanged. `compare_metadata` on the table shows no drift for these columns; its only differences are the older `status_master_id` index/FK (tasks 127/128), not part of this change.
