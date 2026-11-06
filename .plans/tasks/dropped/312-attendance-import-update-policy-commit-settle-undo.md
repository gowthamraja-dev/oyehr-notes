---
task: 312
title: Attendance import "Update" policy — commit, settle and undo
status: dropped
depends_on: [311]
---

# 312 — Attendance import `Update` policy: commit, settle and undo

## Scope
Apply the rows task 311 staged as `update: true`: replace the day's punches with the file's, recompute, audit, and make it undoable.
Paths relative to `workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md`. No schema change — the link between a batch and
the punches it replaced lives in `attendance_punch_details.raw` (jsonb). If that proves too slow or fragile, stop and raise a DBML proposal
(`hrms-dbml-first`) for a real `replaced_by_import_batch_id` column instead of improvising one.

## Behaviour
**Commit** (`commit_rows`), per `update` row, inside the chunk's transaction:
1. **Stale check.** Re-read the day's active punches; if their `first_in` / `last_out` no longer equal `parsed.expected` (someone punched or
   regularized after "Check file"), do **not** apply: leave the row's punches unwritten, count `units_failed`, add a row problem
   `The day changed after the file was checked — re-upload`. The row is still marked Imported by the engine unless the handler can mark
   it otherwise — check `file_import/service.py` and surface it under "Needs attention" the way `_note_row_problem` does.
2. **Archive** every active punch attached to the day (any source: Import / app / device / Regularized), setting `archive = true`,
   `processed_at = NULL` and `raw.replaced_by_import_batch_id = <batch id>` (merge into the existing `raw`, do not overwrite it). Soft delete
   only — see `hrms-soft-delete`. Verify how regularized days store their punches (`service._apply_approved_regularization`) and that they are
   caught.
3. **Insert** the file's IN / OUT punches (`punch_source='Import'`, `import_batch_id`, `raw.attendance_date`, `raw.updated_existing=true`).
   **Dedupe-index trap:** `uq_attendance_punch_details_dedupe` (tenant, employee, device, enrollment_no, `punch_at`, nulls not distinct)
   includes archived rows, so `ON CONFLICT DO NOTHING` would drop a corrected time equal to an earlier archived punch. Before inserting,
   look up an existing row with that key: if it is archived, **revive** it (`archive=false`, `processed_at=NULL`, `raw.revived_by_import_batch_id`)
   instead of inserting; if it is active and on this day, nothing to do.
4. `stats["days_updated"]`, `stats["punches_archived"]`, `stats["punches_revived"]` incremented.

**Settle**: `settle_chunk` already recomputes each (employee, day) of the batch's `processed_at IS NULL` punches and writes one audit row. Make
sure a day whose punches were *all* revived (nothing newly inserted) is still in the queue (revived rows must carry the batch id in the query
— see Undo). Audit action for an updated day: **`BulkImportCorrected`** (old = snapshot before, new = snapshot after, reason `Bulk import #id: <file>`);
locked override stays `LockedDayOverride`. Grep for where audit actions are enumerated or labelled (backend schemas, frontend audit labels) and add the new one.

**Undo** (`prepare_undo` + `settle_chunk(undo=True)`): in addition to archiving the batch's own punches, **un-archive** punches with
`raw.replaced_by_import_batch_id = <batch id>` and re-archive punches revived by the batch, all set `processed_at = NULL`. The settle queue
today is `import_batch_id = batch.id AND processed_at IS NULL`, which will not see a restored device/app punch (it belongs to no batch):
extend it to also match the stamped ones. Narrow the jsonb predicate with `employee_master_id IN (the batch's employees, from import_rows.reference_id)`
and the tenant so it never scans the whole table. Idempotent on resume (matches only rows still in the pre-undo state). `can_undo` rules unchanged
(org-wide ATTENDANCE scope + reason; locked days forced and stay locked).

**Activity log** (`hrms-activity-logging`): the existing one-row-per-confirm / per-undo `user_activity_details` entry gets the counts
(`days_updated`, `punches_archived`) in its detail.

## Files
`backend/app/modules/attendance_import/handler.py` (`commit_rows`, `settle_chunk`, `prepare_undo`, `_settle_day`, `_punch_day`),
`backend/app/modules/file_import/service.py` (only if the stale-check outcome needs an engine hook), audit-action label sites found by grep,
`backend/app/tests/modules/test_attendance_import.py`.

## Rules
Tenant filter on every query (`batch.care_delivery_program_master_id`); never touch `employee_attendance_details` directly; stdlib `logging`
(INFO on state change with batch/employee/date ids, no times in logs beyond ids — no PII). Same recompute window rules as a normal import
(a punch outside shift ± 4 h is reported under "Needs attention" and the batch still finishes).

## Acceptance criteria
- [ ] Editing the OUT of a day that has app punches: the original punches are archived (`raw.replaced_by_import_batch_id` set), new Import punches exist, `employee_attendance_details` shows the new last-out, and one `BulkImportCorrected` audit row has old + new snapshots
- [ ] Editing only the IN keeps the existing OUT; a blank cell never deletes a punch
- [ ] Re-uploading the same corrected file is a no-op (every row Unchanged)
- [ ] A corrected time equal to a previously archived punch is revived, not dropped by the index
- [ ] A day changed between "Check file" and "Confirm" is not overwritten and shows under "Needs attention"
- [ ] A locked day is changed only with `override_locked` + reason (audit `LockedDayOverride`) and stays locked
- [ ] **Undo** restores the original punches (active again), archives the import's punches, recomputes to the pre-import values, audit `BulkImportUndone`; undo twice / after a crash mid-undo is safe
- [ ] Another tenant's punches are never archived or restored (test with two CDPs)
- [ ] Crash + resume mid-commit does not double-archive or double-insert
- [ ] `uv run pytest app/tests/modules/test_attendance_import.py` green

Dropped: 2026-11-02 — not started; shelved by the user ("leave it for now"). Moved out of `ongoing/` rather than deleted; move it back to restart. Design: `.plans/attendance-export-reupload-plan.md`.
