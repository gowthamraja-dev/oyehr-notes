---
task: 263
title: Attendance import — background runner, undo, resume job, retention
status: done
depends_on: [261, 262]
---

# 263 — Attendance import — background runner, undo, resume job, retention

## Scope
`app/modules/attendance_import/runner.py` plus the job registration. No HTTP routes (264).

- `claim(db, batch_id, stale_after=180s, takeover=False)`: single compare-and-set UPDATE on `heartbeat_at` (NULL or stale) →
  returns whether this worker owns the batch. No advisory locks held across commits.
- `run_batch(batch_id)` (own `SessionLocal`): claims, then dispatches on status: Validating → `run_validation` (loop `validate_chunk`, heartbeat,
  → Staged); Running → `run_commit` then `run_recompute` → Done; Undoing → `run_undo` → Undone. Any exception: rollback, status Failed,
  `last_error` (class + message, no row data), `logger.exception`. Every chunk commits and advances `heartbeat_at`.
- `run_commit`: chunks of 500 `Valid` rows → bulk `insert(AttendancePunchDetail).on_conflict_do_nothing().returning(id)`
  (punch_source 'Import', direction IN/OUT, tenant, employee, `import_batch_id`, `raw = {import_batch_id, row, attendance_date, synthesized}`,
  created_by = batch.created_by_id) and mark the chunk's rows Imported in the same transaction; update rows_imported, punches_inserted, days_total.
- `run_recompute`: as the plan's "Recompute step". Chunks of ~25 (employee,date) groups.
- `run_undo`: `UPDATE punches SET archive=true, processed_at=NULL WHERE import_batch_id=:id AND archive=false`, then the same recompute loop with
  `force=True` on locked days; audit action `BulkImportUndone`, `reason` = the undo reason. `start_undo(db, principal, batch_id, reason)` requires a
  reason and appends "; undo: <reason>" (capped at 500) to `batch.override_reason` so the runner can read it after a crash/resume.
- `start_confirm / start_undo / start_resume / discard`: state transitions + `user_activity_details` row + schedule `run_batch` via FastAPI
  `BackgroundTasks` (router passes it in).
- Job `attendance_import_resume` in `app/services/job_defs.py` (`*/5 * * * *`, per CDP): `run_batch` for Validating/Running/Undoing batches whose
  `heartbeat_at` is stale (or NULL and `created_at` older than 3 min); then DELETE staged rows of batches Done/Undone/archived with `finished_at`/
  `archived_at` older than 30 days.

## Files
`backend/app/modules/attendance_import/runner.py`; `backend/app/services/job_defs.py`; tests (runner, resume, undo, retention, tenant scoping).

## Acceptance criteria
- [x] End to end on real shifts: stage → validate → confirm → days Present with correct first_in/last_out (with-times) and shift-hour worked minutes (without)
- [x] Re-confirming/re-uploading creates no duplicate punches; counters correct
- [x] A batch killed mid-commit and mid-recompute resumes to the same final state (tested by running chunks manually)
- [x] Locked day: refused without override; with override recomputed with force, row stays locked, audit action `LockedDayOverride` carries the reason
- [x] A punch outside the shift window counts in `days_failed` with a row error
- [x] Undo archives punches, re-settles days, batch Undone; second undo refused
- [x] Resume job only touches stale batches of the given CDP; retention deletes only old finished/archived batches' rows

Completed: 2026-10-26
Note: split into runner.py (execution), lifecycle.py (request-time transitions: start_confirm/start_undo/start_resume/discard) and jobs.py (resume + retention). A failed batch records its step as the prefix of last_error ("Running: ...") because there is no separate column. Found by the tests: a locked day that could not be touched must not get an audit row.
