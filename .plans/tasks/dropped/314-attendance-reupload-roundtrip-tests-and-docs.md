---
task: 314
title: Attendance export → edit → re-upload: end-to-end tests and docs
status: dropped
depends_on: [310, 311, 312, 313]
---

# 314 — Round-trip tests and docs

## Scope
Per-task tests already ship with 310–312. This task adds the **cross-module end-to-end** guarantees and the documentation the project
requires for a non-obvious flow. Paths relative to `workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md`.

## Tests — `backend/app/tests/modules/test_attendance_reupload.py` (new)
Built from the real exporter output (`attendance_export` builders → `file_export.writers.to_csv` / `to_xlsx`), never hand-written fixtures:
- [ ] **Unchanged export is a no-op**: seed a week of mixed days (present with in/out, absent, week off, holiday, leave, half day, night shift, locked day, day inside a processed payroll period, not-employed days); export `daily_log` as XLSX and as CSV; stage under `Update` → every row `Skipped`; confirm writes zero punches and zero audit rows
- [ ] **Edit → apply → re-export equals edit**: change In/Out on three days, stage, confirm, re-export `daily_log`; the new file shows the edited times and a second upload is again all-Unchanged
- [ ] **Undo round trip**: after the above, undo → the original punches are active and the re-exported log equals the first export
- [ ] Both file formats (CSV via Excel-style re-save with different quoting/BOM, XLSX with the meta block) behave identically
- [ ] **Scoping**: tenant A's export uploaded in tenant B changes nothing (every employee id unresolved → rejected)
- [ ] **Scope inside a tenant**: a manager's export (direct reports only) uploaded by HR works; an HR export edited to include an employee who left the sheet is irrelevant (rows only for those present)
- [ ] 401 / 403: no token, and a role without `ATTENDANCE_IMPORT` CREATE, are refused on `parse` / `stage` with the new fields
- [ ] Encrypted round trip still passes for the JSON endpoints (`test_encryption.py` pattern)

## Docs
- [ ] `docs/attendance-bulk-import.md`: new section "Re-uploading an exported report" — what the reader recognises, the `Update` policy table (unchanged / changed / blank / skip-status-with-times), what is **not** imported (status edits, deleting a punch), locked-day and payroll rules, undo behaviour, the `raw` stamps (`replaced_by_import_batch_id`, `revived_by_import_batch_id`) and the audit action `BulkImportCorrected`; update the "Options" and "Troubleshooting" tables
- [ ] `docs/attendance-export.md`: a short "Editing and re-uploading" note under `daily_log` (which columns are read, that Clock In/Out are in the employee's zone, prefer `.xlsx` over a re-saved CSV because Excel rewrites dates)
- [ ] `docs/file-import.md`: header-row detection and `header_row`, the `detected` hook on `ImportHandler`
- [ ] `CLAUDE.md` (workspace-2 and the root copy): one sentence under "Attendance bulk import" pointing at the new section
- [ ] `docs/attendance-export.md` and `docs/attendance-bulk-import.md` cross-link each other (the latter already links the export doc — keep the "opposite direction" line accurate)

## Acceptance criteria
- [ ] `uv run pytest app/tests/modules/test_attendance_reupload.py app/tests/modules/test_attendance_import.py app/tests/modules/test_attendance_export.py app/tests/modules/test_file_import_engine.py app/tests/modules/test_file_export_engine.py` green, including the golden files for `/attendance/register/export` (unchanged)
- [ ] Docs reviewed against the final behaviour (not the plan)

Dropped: 2026-11-02 — not started; shelved by the user ("leave it for now"). Moved out of `ongoing/` rather than deleted; move it back to restart. Design: `.plans/attendance-export-reupload-plan.md`.
