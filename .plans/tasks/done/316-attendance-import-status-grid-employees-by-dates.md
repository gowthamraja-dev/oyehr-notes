---
task: 316
title: Attendance import reads a status grid (employees × dates) with a code mapping
status: done
depends_on: []
---

# 316 — Attendance import: employees × dates status grid + code mapping

## Scope
HR (here: the marketing / field team) keeps attendance as a **grid** — one row per employee, one column per date, a letter code in each cell,
no times. Today the importer only accepts one row per employee-day, so such a file has to be converted by hand. This task lets the Import
attendance wizard read the grid directly and asks HR to map **columns** (which is the Employee ID, which are dates) and **codes** (what
`P / A / S / L / H` mean). Paths relative to `workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md`.
Does NOT cover creating leave from `L`, the `Update` policy (311/312), or the HRMS hours ledger (315 reuses this task's hook).

## The reference file — `Attendance-Oct-2026.xlsx` (marketing team, Oct 2026)
* Sheet 1 `Attendance Oct 2026`: A1 title `Field Team Attendance — 01 Oct to 27 Oct 2026`, row 2 blank, **header on row 3**:
  `Emp ID | Name | 01-Oct Thu … 27-Oct Tue | Present | Leave | Holiday/Off | Absent`. Dates have **no year** (it is in the title and sheet name),
  weekday letters are part of the header text. Last four columns are numeric totals (not formulas).
* Rows 4–29: 26 employees, ids like `NT-8`, `NT-150` (no duplicates). Then a blank row and a **5-row legend in the same columns**
  (`P = Present (report submitted)`, `A = Absent (no report)`, `L = Leave / Comp off`, `H = Holiday / Off reported`, `S = Sunday (no report, weekly off)`).
* Cells: `P` 281, `A` 285, `S` 100, `L` 15, `H` 21, no blanks. Cell fills are colour-coded (ignored). Sheet 2 `Notes` is rules text (ignored).
* A one-off conversion to the current long format already exists: `~/Downloads/Attendance-Oct-2026-import.csv` (702 rows) — the acceptance test
  below must produce the same rows from the original `.xlsx`.

## Behaviour
1. **Layout choice.** The mapping step gets "How is the file laid out?": *One row per employee-day* (today) or *Employees × dates grid*.
   Auto-selected when ≥ 3 header cells parse as dates (`01-Oct Thu`, `01-Oct`, `1`, `2026-10-01`, `01/10/2026`, real date cells). Persist as `options.layout`.
2. **Column mapping** (grid): HR picks the **Employee ID column** (pre-selected by the existing header hints: `Emp ID`); the Name column and the
   summary columns (`Present`, `Leave`, `Holiday/Off`, `Absent` — headers that are not dates) are ignored and shown as such. Date columns are
   not mapped one by one — every date-looking header is used; the screen lists "27 date columns: 01-Oct … 27-Oct" and lets HR untick any.
3. **Year / month.** Taken from, in order: a 4-digit year in the title cell (A1) or sheet name; otherwise asked ("Which year?"). A header
   with a weekday letter is checked against the calendar (`01-Oct Thu` must be a Thursday in that year) — a mismatch refuses the file with the cell named
   (catches the wrong year). Across a year boundary (`30-Dec … 02-Jan`) the year rolls over at the month wrap.
4. **Code mapping** (grid): a table seeded from the common vocabulary — `P/Present → Present`, `A/Absent → Absent`, `S/WO/Week off → Week-off`,
   `L/Leave → Leave`, `H/Holiday → Holiday` — plus every other distinct code found in the file shown as "unmapped" and required to be mapped (or set to
   *Ignore*) before "Check file". Targets are the importer's own kinds: Present, Absent, Leave, Week-off, Holiday, Ignore. Stored in `options.code_map`.
   A blank cell produces **no row** (never read as Absent).
5. **Stop at the legend.** Data rows end at the first fully blank row after the first data row; anything below (the legend) is never staged. If no blank
   row exists, a row whose Employee ID cell is itself one of the mapped codes is dropped with a note.
6. **Un-pivot before staging.** A handler hook `ImportHandler.normalise_upload(headers, rows, options) -> (headers, rows)` is called by `parse` and
   `stage`; for `layout = "grid"` it emits `Employee ID | Date | Status | Source cell` rows (`Source cell` = `D4`, an internal target field) so validation,
   commit, settle and undo are **reused unchanged** (no new tables, no new runner). Row-level errors name the cell: `NT-8, 02-Oct — cell D4: …`.
7. **What each code does** (v1 = exactly what the importer already does, nothing new is invented):
   * `Present`, no times → IN/OUT synthesised from the day's **scheduled shift** (warning on the row); needs a shift for that day, else rejected "No shift is scheduled".
   * `Absent`, `Week-off`, `Leave`, `Holiday` → row `Skipped`, nothing written; the day settles from the calendar / existing leave.
   * Under policy `Skip`, a day that already has punches is skipped (unchanged); locked days need *include locked days* + reason (HR org-wide scope);
     dates inside a processed payroll period are refused — all as in `docs/attendance-bulk-import.md`.
8. **Limits.** 5,000 rows applies **after** un-pivoting (26 × 27 = 702 here; 80 employees × 62 days would not fit) — fail early with a clear sentence, never truncate.

## Open decisions for the product owner (v1 ships the defaults above)
* `L` ("Leave / Comp off") and `H` ("Holiday / Off reported" — the sheet's own note says some are not company holidays) do **not** create leave or a holiday; the
  HRMS day stays whatever the calendar/leave says, i.e. usually **Absent**. Making `L` create leave means choosing a leave type per code
  (`POST /leave/requests/bulk-on-behalf`, `record` mode) — a follow-up task if wanted.
* `A` never removes existing punches. Correcting a day to Absent is a regularization decision.
* The sheet's `Notes` say Oct 2 and Oct 19–20 show Absent where no report exists "adjust if company holidays": HRMS decides those from its own holiday calendar, not from this file.

## Files
`backend/app/modules/file_import/handlers.py` (hook), `backend/app/modules/file_import/service.py` + `router_factory.py` (call it in `preview_file`/`stage_batch`,
accept `layout` / `code_map` / year), `backend/app/modules/file_import/schemas.py`, `backend/app/modules/attendance_import/grid.py` (new: date-header parser, year
resolution, code vocabulary, un-pivot), `backend/app/modules/attendance_import/handler.py` (`parse_options` accepts `layout`, `code_map`, `year`; target field `source_cell`),
`frontend/src/dashboards/shared/ImportAttendance.tsx` + `FileImportWizard.tsx` (layout choice, date-column list, code-mapping table, year prompt),
`frontend/src/lib/api.ts` (types), `backend/app/tests/modules/test_attendance_import.py`.

## Rules
Tenant scoping unchanged (the handler still resolves every Employee ID inside the caller's CDP, so an id that is not in the tenant is rejected and **only the
listed employees are touched** — this is what keeps a "marketing only" file from affecting anyone else). Stdlib `logging`. No migration. Tailwind only, `dd-MMM-yy`
dates, shimmer skeletons, plain `fetch` for the two multipart calls and `secureFetch` for the rest. Gate on the existing `ATTENDANCE_IMPORT` CREATE.

## Acceptance criteria
- [x] A synthetic workbook with the reference shape (title row, blank row, header on row 3, no-year date headers with weekday letters, 4 summary columns, legend below) — **not** the real names/ids — parses: grid auto-detected, header row 3, date columns, year from the title, summary columns ignored (`test_a_grid_workbook_is_recognised_and_described`)
- [x] Un-pivoting gives one row per non-blank cell with the right dates; the legend rows are never staged; blank cells yield no row (`test_unpivoting_gives_a_row_per_filled_cell_and_never_stages_the_legend`, `test_without_a_blank_row_the_legend_is_still_dropped`)
- [x] The real `Attendance-Oct-2026.xlsx` (run locally by hand from a scratchpad copy, not committed) yields the same 702 rows and statuses as `~/Downloads/Attendance-Oct-2026-import.csv`: header row 3, 27 date columns, 26 employees, year 2026 from the title, codes P 281 / A 285 / S 100 / L 15 / H 21
- [x] A header whose weekday letter contradicts the year is refused with the cell named; a missing (or doubtful, two-year) year asks for one and the answer is weekday-checked
- [x] An unmapped code blocks staging (422) until mapped or ignored; the default `P/A/S/L/H` table needs no edits
- [x] After "Check file": `P` days are Valid with the shift-time warning, `A/S/L/H` are Skipped, a day with no shift is Rejected with `Cell <ref>` in the message
- [x] Confirm writes only the `Present` days; undo removes them; another tenant's employee id is rejected
- [x] Row cap applies after un-pivoting and refuses with a sentence; the screen is told the real (un-pivoted) count
- [x] The existing one-row-per-employee-day flow is unchanged (`test_the_plain_flow_is_unchanged_by_the_grid_hooks`; all 155 earlier tests still pass)
- [x] `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_file_import_engine.py`: 172 passed; ruff clean on the changed modules and tests; `tsc --noEmit` + eslint exit 0
- [x] Checked in a browser against a running app — NOT done: no frontend server was started (needs approval). The layout choice, year box, date-column list and code table are implemented in `ImportAttendance.tsx` (`GridPanel`) but unseen — confirmed working in the browser by the user, 2026-11-02

## Progress (2026-10-30)
Built in `workspace-2/hrms`, NOT committed.
Backend: `file_import/parsing.py` (`ParsedUpload` + `parse_upload`: the cells above the header and the sheet name as `preamble`, `blank_after`; `parse_file_with_header` kept as a wrapper), `file_import/handlers.py` (new `inspect_upload` and `normalise_upload` hooks; `internal` target fields), `file_import/service.py` (`preview_file(…, options)`, `stage_batch` un-pivots through the hook and validates the effective mapping), `file_import/router_factory.py` (`/parse` takes an optional `options` form field; internal fields are not listed), `file_import/schemas.py` (`PreviewOut.inspection`),
`attendance_import/grid.py` (new: date-header parser, year resolution + weekday check, code vocabulary, legend handling, un-pivot), `attendance_import/handler.py` (options `layout` / `year` / `code_map` / `exclude_columns`, `Cell D4:` message prefix), `attendance_import/parsing.py` (internal `source_cell` field).
Frontend: `FileImportWizard.tsx` (generic optional `renderInspection`, `optionsAfterParse`, `mappableHeaders`, `requiredKeys`; `optionsProblem` also gets the preview; re-reads the file when an option changes), `ImportAttendance.tsx` (`GridPanel`), `lib/api.ts`. Docs: `docs/attendance-bulk-import.md` ("Status grid"), `docs/file-import.md` (hooks).
Deviations: (1) the hook is `normalise_upload(upload, options, mapping)` taking a `ParsedUpload` (not bare headers/rows) because the year lives in the title above the header; (2) `/parse` gained an optional `options` field so the screen can re-read the file as a grid; (3) a heading that is a bare day number is read only when the title names a month; (4) `OFF`, `PH`, `PR`, `AB`, `SUN`, `WEEKLY OFF` are also seeded as codes.
Not part of this task and still open for the product owner: whether `L` should create real leave, and what `H` means when it is not a company holiday.
Remaining: one look at the screens in a browser (together with 317 and 319), then move to `done/`.

Completed: 2026-11-02
