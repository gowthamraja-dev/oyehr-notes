---
task: 268
title: File import — generic engine, ImportHandler seam, attendance handler (refactor of tasks 262/263)
status: done
depends_on: [267]
---

# 268 — File import — generic engine and attendance handler

## Scope
Move the code built in 262/263 (and the service/router drafted for 264) behind a handler seam on the v2 tables. Behaviour does not change; the
existing attendance tests are the safety net and must pass against the new names. Does NOT add a second import type.

- `app/modules/file_import/handlers.py`: `ImportHandler` protocol (see the plan's "Handler contract") + `register()/get()` registry keyed by `import_type`.
- `file_import/parsing.py`: csv/xlsx reading, `_cell_to_str`, `parse_date`, `MAX_ROWS` (generic). Time/status parsing stays with the attendance handler.
- `file_import/service.py`: `preview_file` (handler target fields + suggested mapping), `stage_batch(db, principal, handler, filename, bytes, mapping, options_raw)`
  (handler.parse_options → batch.options; mapping validated against `handler.target_fields`; rows staged `Pending`), reads (`get_batch`, `list_batches`,
  `list_rows`, `row_status_counts`) filtered by tenant AND import_type, `to_batch_out`/`to_row_out`.
- `file_import/runner.py`: `claim`, `_beat`, `_fail` (phase-prefixed `last_error`), `run_batch(batch_id, db=None, max_seconds=None)` dispatching on status;
  Validating → loop `handler.validate_chunk`; Running → loop `handler.commit_chunk` then loop `handler.settle_chunk(undo=False)`; Undoing →
  `handler.prepare_undo` then `settle_chunk(undo=True)`. Chunk sizes come from the handler.
- `file_import/lifecycle.py`: `start_confirm`, `start_undo` (handler.can_undo + reason), `start_resume`, `discard`, `failed_phase`.
- `file_import/jobs.py`: `run_file_import_resume` (job name stays `attendance_import_resume`? — rename to `file_import_resume` in `job_defs`; all types),
  retention purge of staged rows.
- `file_import/router_factory.py`: `build_routers(handler)` → (encrypted JSON router, plain upload router); gates via
  `require_grid_permission(db, principal, action, handler.resource)`; `stage` takes `options` as a JSON form field.
- `attendance_import/handler.py`: `AttendanceImportHandler`: target fields; `parse_options` (existing_day_policy, override_locked + reason + `sees_whole_org`);
  `validate_chunk` (today's `_validate_rows`, writing `reference_id`, `dedupe_key`, `parsed`); `commit_chunk` (punch insert from `parsed`);
  `settle_chunk` (recompute + audit + orphan/lock handling); `prepare_undo`; `can_undo`. `attendance_import/router.py` = `build_routers(handler)`;
  `attendance_import/{service,runner,lifecycle,jobs}.py` are removed (moved).
- Counter mapping: days_* → `units_*`; `punches_inserted` → `batch.stats`; override fields → `batch.options`.

## Files
`backend/app/modules/file_import/*` (new), `backend/app/modules/attendance_import/{handler,router,parsing}.py`, `backend/app/services/job_defs.py`,
`backend/app/api/router.py`, tests: `backend/app/tests/modules/test_file_import_engine.py` (engine behaviour against a tiny fake handler: claim/heartbeat,
crash + resume, phase prefix, tenant + import_type scoping, retention across types, router factory gating) and `test_attendance_import.py` (the existing 84+
attendance tests, updated for the new names, unchanged in intent).

## Acceptance criteria
- [x] Every existing attendance test passes against the v2 tables with only renames in the assertions
- [x] A fake second handler registered in tests runs stage → validate → confirm → settle → Done through the same engine and routes, and cannot see or act on an
      attendance batch (and vice versa) — proving the tables and engine are type-agnostic
- [x] No attendance-specific name, column or rule remains inside `file_import/`
- [x] ruff clean; neighbouring suites (attendance, recompute, assembler, employee_import, roles, authz) still green

Completed: 2026-10-26
Note: 116 tests across test_file_import_engine.py (15, engine + a fake second type + isolation + registry + job + router factory) and test_attendance_import.py (101). The engine mentions attendance only in doc comments and in handlers._LAZY (the one line that lets the runner find a handler in a process that never imported its router). Pre-existing, unrelated failures found while running neighbours, identical on a pristine HEAD export: test_attendance.py::test_employee_daily_pagination_matches_my_daily_shape and three in test_attendance_dashboard.py (login for H74MGR2 returns no access_token; headcount; yesterday-never-punched).
