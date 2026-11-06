# Attendance: re-upload an exported report after edits

Goal: HR downloads an attendance report (Attendance → Export report), fixes times in Excel, and uploads the same file
through **Import attendance**. The import applies only what HR changed.

All paths are relative to `workspace-2/hrms/`. Tasks: 310–315 in `.plans/tasks/ongoing/`.

## What exists today (read before changing anything)

* Export engine `backend/app/modules/attendance_export/` — four reports. `docs/attendance-export.md`.
* Import engine `backend/app/modules/file_import/` + handler `backend/app/modules/attendance_import/handler.py`. One row = one
  employee-day. `docs/attendance-bulk-import.md`, `docs/file-import.md`. Frontend `dashboards/shared/ImportAttendance.tsx` on `FileImportWizard.tsx`.

## Why "just upload it" does not work today

| # | Gap | Where |
| --- | --- | --- |
| 1 | The XLSX export has a meta block, a legend note, a blank row and (ledgers) a group band **above** the header row; the engine reads sheet row 1 as the header. CSV exports are fine (meta/legend are XLSX-only). | `file_export/writers.py` `to_xlsx`, `file_import/parsing.py` `_parse_xlsx` |
| 2 | The daily log's `Day` column (Mon/Tue…) is a header hint for the `date` field, next to `Date`. | `attendance_import/parsing.py` `HEADER_HINTS` |
| 3 | The daily log's `Status` carries labels the importer rejects as unknown: `Half day`, `Yet to check in`, `No shift` (and possibly `Late`). Every untouched row would be a rejection. | `dashboard_service._STATUS_DISPLAY_LABEL`, `parsing.normalise_status` |
| 4 | Every exported row is an existing day, so it hits `existing_day_policy`: `Skip` skips the edit too; `Merge` **adds** a second IN/OUT pair instead of correcting. There is no way to change an existing day. | `handler.validate_rows` |
| 5 | Untouched rows on locked days / closed payroll periods would be rejected ("Day is locked"), flooding the review screen with rows HR never touched. | `handler.validate_rows` check order |
| 6 | A row with a skip Status (Absent…) plus times typed in by HR is silently skipped — HR fills in a missing punch on an Absent row and nothing happens. | `handler.validate_rows` |
| 7 | A blank-times row is "present for the scheduled shift". Harmless under `Skip`; wrong for an exported blank cell on a day that has punches. | `handler._resolve_times` |
| 8 | The dedupe index `uq_attendance_punch_details_dedupe` is keyed on `punch_at` and includes archived rows, so a corrected time equal to a previously archived punch would be silently dropped by `ON CONFLICT DO NOTHING`. | `handler.commit_rows` |
| 9 | Times are exported in `scoped.time_zone` (work-location zone, per the hours-ledger legend) but read back in `resolve_timezone(resolved_shift)`. If they differ, an untouched export is read as changed. | `daily_log._clock`, `handler._resolve_times` |

## Design

1. **Reader** (310): the importer finds the real header row, recognises the daily log's columns and labels, and tells the UI it
   looks at an export.
2. **New policy `existing_day_policy = "Update"`** (311, 312): per row, compare the file's In/Out with the day's current
   first-in / last-out (minute precision, shift zone).
   * equal → `Skipped` ("Unchanged") — this is what makes re-uploading a whole month safe;
   * different → `Valid`, "Changes 09:05–18:10 → 09:30–18:10"; on confirm the day's active punches are **archived** (soft, reversible,
     stamped with the batch id in the punch's own `raw` jsonb) and the file's punches written; the day is recomputed by the existing
     `recompute_attendance_day`. Never writes `employee_attendance_details` directly.
   * a blank In or Out means "keep the current value" — the file cannot delete a punch.
   * Undo restores the archived punches.
   * `Skip` and `Merge` are unchanged.
3. **Frontend** (313): the wizard recognises an export, preselects `Update`, and the review screen shows *Changed* (before → after),
   *Unchanged* and the rest.
4. **Docs + round-trip tests** (314).
5. **Later, optional** (315): the wide `hours_ledger` (`cell=in_out`) as input.

## Decisions taken (flag if you disagree)

* **No schema change.** The "which punches did this batch replace" link lives in `attendance_punch_details.raw` (jsonb, already used
  for `import_batch_id` / `attendance_date`). So the `hrms-dbml-first` gate is not triggered. If you would rather have a real
  `replaced_by_import_batch_id` column (indexable, FK), that is a schema change and goes through DBML approval first.
* **Archiving device/app punches is acceptable** because it is the soft-delete convention (`archive = true`), is audited per day
  (`attendance_audit_logs`, old + new snapshot, reason) and is undoable. The alternative — routing each edited day through the
  regularization flow (`_regularize_one`) — keeps its approval semantics but has no undo and is one day at a time.
* **Status edits are not imported.** Changing `Present → Absent` (or to Leave / Half day) in the sheet is reported as "not imported —
  use regularization / leave", never applied. Times drive everything.
* **Only `daily_log` as input in v1.** `attendance_ledger` has no times (status codes only), `monthly_summary` is totals, and
  `hours_ledger` is a wide grid (task 315).
* **Unchanged export = zero writes** is the invariant every task is tested against (314 holds the end-to-end test).

## Task map

| Task | Title | Depends on |
| --- | --- | --- |
| 310 | Import reads an exported daily log as-is (header row, columns, status labels) | — |
| 311 | `Update` policy — validation: diff the file against the day | — |
| 312 | `Update` policy — commit, settle and undo | 311 |
| 313 | Web: re-upload mode in the Import attendance wizard | 310, 311 |
| 314 | Round-trip tests and docs | 310, 311, 312, 313 |
| 316 | Read a status grid (employees × dates, letter codes) with a column + code mapping — the marketing team's `Attendance-Oct-2026.xlsx`; introduces the un-pivot hook | — |
| 315 | (Later) read the wide hours ledger (reuses 316's hook) | 310, 311, 312, 316 |

**Onboarding / history loads (added 30-Oct-26).** Organisations being onboarded back-fill past months from other systems (payroll runs elsewhere):

| Task | Title | Depends on |
| --- | --- | --- |
| 317 | The payroll-period refusal becomes an option, **off by default** (warning instead) | — |
| 318 | Raw device punch log (`.xls`/TSV/CSV/XLSX) with a **direction choice** (first/last, entry-only, exit-only, file state, alternate) | 316 |
| 319 | Match people by **device enrollment number** via `employee_device_mappings` (not a guess from `emp_id`) | — |

Until 318/319 ship, the pre-converted files (`~/Downloads/*-import.csv`) work in the current flow: direction fixed to first/last, ids as written in the source.

**Marketing team file (added 29-Oct-26).** `Attendance-Oct-2026.xlsx` is not an HRMS export: a title row, header on row 3, 26 employees × 27 no-year date columns,
codes `P/A/S/L/H`, no times, summary columns and a legend below. Task 316 handles that layout in the wizard. Until it ships, the file converts to the
current long format with a one-off script (`~/Downloads/Attendance-Oct-2026-import.csv`, 702 rows).
