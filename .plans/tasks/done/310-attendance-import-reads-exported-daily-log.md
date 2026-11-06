---
task: 310
title: Attendance import reads an exported daily log as-is
status: done
depends_on: []
---

# 310 — Attendance import reads an exported daily log as-is

## Scope
Make a file produced by Attendance → Export report → **Daily log** (CSV or XLSX, edited in Excel and saved) parse and map without HR
touching the layout. Paths below are relative to `workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md` gaps 1, 2, 3.
Does NOT cover the "existing day" behaviour (task 311/312), the UI (313), or the wide ledgers (315). Do **not** change any exporter —
the reader adapts to the export, and `/attendance/register/export` has byte-exact golden files.

What the daily log looks like (`attendance_export/daily_log.py`, `file_export/writers.py`):
* CSV: row 1 = header (UTF-8 BOM; meta and legend are XLSX-only). Already readable by `_parse_csv`.
* XLSX: `n_meta` lines of `label | value`, plus one `Note` legend line, then a blank row, then the header, then data. Second sheet "Legend".
* Columns: `Date` (dd-MMM-yy text), `Day` (Mon…), `Employee Name`, `Employee ID`, `Department`, `Shift`, `Work location`, `Status`,
  `Clock In` / `Clock Out` (`HH:MM:SS`, blank when none), `Worked Hours`, `Late By (min)`, `Early Exit (min)`, [`Overtime (min)`],
  `Regularized`, `Pending request`, `Source`.

## Changes
1. **Header-row detection** — `file_import/parsing.py`: `parse_file(filename, bytes, hint_headers=None)`. For `.xlsx`, scan the first 30 rows
   of the **first worksheet** (`wb.worksheets[0]`, not `wb.active`) and use the first row in which at least 2 cells normalise (lower-case,
   punctuation removed — same normaliser the mapping suggestion uses) into the handler's `header_hints`; fall back to row 1 exactly as
   today, so the plain template is untouched. CSV: same scan (a user may paste a meta block into a CSV). Return `header_row` (1-based
   sheet row). `row_number` keeps its meaning (position among the data rows after the header).
2. **Carry `header_row`** — `parse` response includes it; `stage` stores it in `import_batches.stats["header_row"]` (jsonb, no migration);
   the batch/rows API exposes it so the UI can show the real sheet row (`row_number + header_row`).
3. **Fix the `Day` collision** — `attendance_import/parsing.py` `HEADER_HINTS["date"]` contains `day`, which is the daily log's weekday
   column. Check how `file_import/router_factory.py` builds `suggested_mapping` when two headers hint the same field; make an exact match
   (`date`, `attendance date`) win and drop `day` from the hints (or make "first exact match wins, others unmapped"). `Employee Name`,
   `Department`, `Shift`, … stay unmapped (the engine stores only mapped columns).
4. **Status vocabulary** — `normalise_status` must know every label `daily_log` emits (read `dashboard_service._STATUS_DISPLAY_LABEL` and
   the `EffectiveStatus` enum — do not guess): `Present`, `Late` (if emitted), `Half day` → kind `present` (informational);
   `Absent`, `On leave`, `Week off`, `Holiday`, `Yet to check in`, `No shift` → kind `skip` with the right label. Plain-template behaviour
   for the existing words is unchanged; a genuinely unknown word is still rejected.
5. **Detection hint** — `parse` response gains `detected: {"export_type": "daily_log"} | null`, set when the headers contain `Clock In`,
   `Clock Out`, `Source` and `Worked Hours`. Pure header test, in `attendance_import/parsing.py`, exposed through a handler method
   (default `None` on the base `ImportHandler`).
6. **Cell clean-up** — strip the single leading `'` the export engine adds (`writers.guard_text`) to an Employee ID cell; `?` in a time cell
   (hours ledger marker) is treated as blank. Dates re-saved by Excel as `m/d/yyyy` are ambiguous with `d/m/yyyy` — note in the doc that the
   `.xlsx` route is preferred; do not change date precedence.

## Files
`backend/app/modules/file_import/parsing.py`, `backend/app/modules/file_import/handlers.py` (hook), `backend/app/modules/file_import/router_factory.py`,
`backend/app/modules/file_import/schemas.py`, `backend/app/modules/attendance_import/parsing.py`, `backend/app/modules/attendance_import/handler.py`
(hint list only), tests below.

## Rules
Tenant scoping is unchanged (nothing here queries data). Stdlib `logging`. No new table/column. Plain-template files must behave exactly as before.

## Acceptance criteria
- [x] A daily-log **XLSX** written by the export engine's real `to_xlsx` parses: `header_row` is the true header row (6), `Employee ID` / `Date` / `Clock In` / `Clock Out` / `Status` are pre-mapped, `Day` is not mapped to `date` (tests use the real writers with a daily-log-shaped `ExportTable`; the full builder round trip needs the DB and belongs to 314)
- [x] The same report as **CSV** parses with `header_row == 1`
- [x] The plain template still has `header_row == 1` and an unchanged suggested mapping
- [x] Every status label `daily_log` can emit is accepted (`Present`, `Absent`, `Holiday`, `On leave`, `Week off`, `Yet to check in`, `No shift`, `Half day`); an invented word is still rejected — `normalise_status` verified; the per-row staging behaviour is in the DB-backed tests below
- [x] `parse` returns `detected.export_type == "daily_log"` for an export and `null` for the template
- [x] An employee id cell starting with `'` stages with the id resolved, and `?` in Out is a single clock-in with a warning (`test_export_artifacts_in_cells_are_cleaned`; CSV-level — the XLSX staging path is covered by `test_staging_an_export_records_where_its_header_was`)
- [x] `test_attendance_import.py` and `test_file_import_engine.py` extended and green — `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_file_import_engine.py`: 134 passed; ruff clean. (Ran against the local `hrms-test-pg` container, started with approval and stopped afterwards.)

## Progress (2026-10-30)
Built in `workspace-2/hrms/backend`, NOT committed (the working copy also holds unrelated uncommitted changes in `attendance/`, `devices/`, `config.py`, the recompute service — untouched):
`file_import/parsing.py` (`normalise_header`, `parse_file_with_header` + `HEADER_SCAN_ROWS`, first worksheet; `parse_file` kept as a two-value wrapper), `file_import/service.py` (two-pass `suggest_mapping`,
`preview_file` returns `header_row` + `detected`, staging stores `stats.header_row`), `file_import/handlers.py` (`hint_texts`, `detect_source`), `file_import/schemas.py` (`PreviewOut`),
`attendance_import/parsing.py` (status vocabulary, `clean_employee_id`, `clean_time_cell`, `detect_export`), `attendance_import/handler.py` (`detect_source`, cleaned ids/times, half-day rule), tests in both test files.
Deviations from the plan above: (1) `stats.header_row` is stored **only when the header is not row 1** (absent = 1), so a plain file's `stats` stay `{}` and the engine test that asserts exact stats is unaffected;
(2) the `Day` collision is fixed by a two-pass `suggest_mapping` (a header equal to a target's own name wins first) rather than deleting the `day` hint; (3) `Half day` is a new status kind: accepted with times,
**rejected without** (it would otherwise be turned into a full shift) — the old test that used "Half Day" as its unknown-status example now uses another word.
Docs for all of this are task 314.

Completed: 2026-10-30
