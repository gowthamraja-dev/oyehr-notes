---
task: 318
title: Attendance import reads a raw device punch log, with a direction choice
status: done
depends_on: [316]
---

# 318 — Raw device punch log + "which punch is in / out" choice

## Scope
Let HR upload a biometric terminal's **raw log** (one row per punch) and choose, on screen, how the punches become clock-in / clock-out. Today the importer needs
one row per employee-day with both times, so a device log has to be aggregated by hand (done once offline for May 2026). Paths relative to `workspace-2/hrms/`.
Design: `.plans/attendance-export-reupload-plan.md`. Builds on task 316's `ImportHandler.normalise_upload` hook and `options.layout` — if this is built first it
introduces them and 316 reuses them. Does NOT cover matching device numbers to employees (task 319) or the existing-day policies (311).

## The reference file — `DeviceLogs (1).xls`
* Despite the name it is **tab-separated text** (CRLF), not a workbook: `Download Date | UserId | User Name | Log Date | Device Name | Serial Number | Att State | Verify Mode | GPS`.
* 3,240 punches, 1–31 May 2026, 46 users, one terminal (`ENTRY`, serial `UUC2251400071`), `Att State` **blank on every row** (no direction), face verification, `Log Date` like `31 May 2026 18:22:24`.
* Per user-day: 1 punch on 100 days, 2 on 170, up to 8+ on others — re-scans seconds apart are common.
* `UserId` is the terminal's enrollment number, **not** the HRMS `emp_id` (see task 319).

## Behaviour
1. **File reading** (`file_import/parsing.py`): accept `.xls`, `.tsv`, `.txt` **when the content is delimited text** — sniff: not an OLE/zip signature, a tab (or `;`/`,`) in the first
   line — and parse with that delimiter (UTF-8 with or without BOM, then cp1252). A genuine binary `.xls` (OLE header `D0 CF 11 E0`) is refused with "Save it as .xlsx or .csv".
   Raw punches are counted against a separate cap (200,000 rows, still 10 MB) because they collapse into employee-days; the 5,000-row cap applies **after** aggregation.
2. **Layout** `punch_log` (auto-selected when headers contain a log-date/time column and a user id, e.g. `Log Date` + `UserId`): extra target fields `punch_at` (date-time, required),
   `direction` (optional), `device_serial` (optional, used in 319). Header hints: `log date`, `punch time`, `date time`, `datetime`, `timestamp`; **`Download Date` must never be hinted as the
   punch time** (it is when the file was pulled — earlier than/after the punch). `UserId`, `User Id`, `Enrollment No`, `Employee Code` → `employee_id`. Date-time parsing: `31 May 2026 18:22:24`,
   ISO `2026-05-31 18:22:24`, `31/05/2026 18:22`, and Excel date-time cells.
3. **Direction choice** — new option `direction`, a radio group on the options step, explained in plain words:
   | Value | Label | What it writes per employee-day |
   | --- | --- | --- |
   | `first_last` (default) | "This device records both in and out — first punch of the day is the clock-in, last is the clock-out" | In = first, Out = last |
   | `all_in` | "Entry device — every punch is a clock-in (the clock-out is in another file)" | In = first punch only; later scans ignored |
   | `all_out` | "Exit device — every punch is a clock-out (the clock-in is in another file)" | Out = last punch only |
   | `file_state` | "Use the file's In/Out column" | In = first punch whose state is In, Out = last whose state is Out. Offered only when a `direction` column is mapped; the screen lists the distinct values found (`I`, `Check-In`, `0`…) so HR assigns each to In / Out / Ignore (same code-mapping table as task 316) |
   | `alternate` | "Alternate: 1st in, 2nd out, 3rd in…" | Out = the last even-numbered punch; an odd trailing punch is a stray in |
   Choosing `all_in` or `all_out` **pre-selects `existing_day_policy = Merge`** and shows "Upload the other terminal's log next, also with Merge, to complete the days" (the second file adds its half
   to days that already have punches; nothing is replaced). Re-uploading the same file adds nothing (dedupe index).
4. **Other options on the same step:** *Ignore repeat scans within* `N` minutes (default 1; punches closer than the importer's 60-second debounce are one scan — never fewer than 1) and *A day starts at* `HH:MM`
   (default `00:00`; set `04:00` so a night shift's 02:00 punch belongs to the previous day). Times are read in the employee's shift time zone, as everywhere in this importer.
5. **Aggregation** (`attendance_import/punch_log.py`, new): group by (employee id, business date), apply the direction rule, drop a pair less than 60 s apart to a single punch, and emit
   `Employee ID | Date | In Time | Out Time | Source` rows into the existing staging, so validation, commit, settle and undo are unchanged. The staged row's message lists the raw punches:
   `4 punches: 09:12, 09:12, 13:05, 18:20 → In 09:12, Out 18:20` so HR can check the choice. A day with a single in-only punch carries the existing "missing clock-out" warning.
6. **Review summary** (reuse 313's generic groups if present): "743 days from 3,240 punches · 190 with a clock-in only · 7 with in/out under 30 minutes apart".

## Files
`backend/app/modules/file_import/parsing.py` (sniffing, delimiter, raw cap), `backend/app/modules/file_import/handlers.py` + `service.py` + `router_factory.py` (hook already from 316),
`backend/app/modules/attendance_import/punch_log.py` (new), `backend/app/modules/attendance_import/parsing.py` (target fields, hints, date-time parser),
`backend/app/modules/attendance_import/handler.py` (`parse_options`: `direction`, `repeat_scan_minutes`, `day_starts_at`, `direction_map`), `frontend/src/dashboards/shared/ImportAttendance.tsx` /
`FileImportWizard.tsx` (layout choice, direction radios, direction-value table, summary line), `frontend/src/lib/api.ts` (types), `backend/app/tests/modules/test_attendance_import.py`, docs.

## Rules
Tenant scoping unchanged (every Employee ID is still resolved inside the caller's CDP; punches for unknown ids are rejected). Never write `employee_attendance_details` — punches only, `punch_source = 'Import'`.
Stdlib `logging`, no raw rows or names in logs. No migration. Tailwind only; `dd-MMM-yy` dates; shimmer skeletons; plain `fetch` for multipart. Gate on `ATTENDANCE_IMPORT` CREATE.

## Acceptance criteria
- [x] A synthetic file with the reference shape (TSV named `.xls`, CRLF, `Download Date` first) parses, auto-selects the punch-log layout and maps `UserId` / `Log Date`; `Download Date` is not mapped (`test_a_terminal_log_saved_as_xls_is_read_as_a_punch_log`)
- [x] A real binary `.xls` (and an `.xlsx` renamed `.xls`) is refused with the "save it as .xlsx or .csv" sentence; `.csv`, `.xlsx`, `.tsv`, `.txt`, semicolon and cp1252 logs also work
- [x] `first_last`: 1 punch → In only; 2+ punches → first/last; two punches 30 s apart → In only; a pair 31 minutes apart is kept
- [x] `all_in` writes only the first punch as In, `all_out` only the last as Out; uploading the two files in turn (both Merge) yields days with In and Out, nothing doubled, and re-uploading adds 0 punches (`test_an_entry_file_and_an_exit_file_complete_each_others_days_and_a_reupload_adds_nothing`). The "pre-select Merge" part is UI (see last item)
- [x] `file_state` is offered only when a direction column is mapped (server: refused otherwise) and refuses to stage until every distinct value is assigned or ignored
- [x] `alternate` gives Out = last even-numbered punch; `day_starts_at = 04:00` puts a 02:00 punch on the previous date and keeps a next-morning clock-out's date
- [x] The row message lists the raw punches and the chosen In/Out; the stats (`raw_punches`, `punch_days`, `punch_in_only_days`, `punch_short_days`) match the file
- [x] Rows over the 5,000-day cap are refused with a sentence (tested with a lowered cap); the raw-line cap is separate
- [x] The old one-row-per-employee-day flow and task 316's grid flow are unchanged (all earlier tests pass)
- [x] The real `DeviceLogs (1).xls` (run by hand from a scratchpad copy, not committed): auto-detected as a punch log, 3,240 punches → 743 days, 46 users, 190 clock-in only, 7 under 30 minutes apart, serial `UUC2251400071` found — the same days and times as the earlier offline conversion `DeviceLogs-May-2026-import.csv` (0 differences)
- [x] `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_file_import_engine.py`: 189 passed; ruff clean on the changed modules and tests; `tsc --noEmit` + eslint exit 0
- [x] Checked in a browser against a running app — NOT done (no frontend server approved). Unseen: the three-way layout choice, the direction radios (and Merge pre-select for `all_in` / `all_out`), the In/Out value table, the repeat-scan / day-start inputs, the summary line, the terminal pre-selection — confirmed working in the browser by the user, 2026-11-02

## Progress (2026-10-30)
Built in `workspace-2/hrms`, NOT committed. Builds on 316's hooks.
Backend: `file_import/parsing.py` (delimited-text sniffing for `.xls` / `.tsv` / `.txt`, OLE / zip signatures refused, `RAW_MAX_ROWS` = 200,000 read-cap, `ParsedUpload.stats`), `file_import/service.py` + `router_factory.py` (`/parse` also takes the current `mapping`; `stats` merged into the batch), `file_import/schemas.py` (`TargetField.layout`), `attendance_import/punch_log.py` (new: options, clustering of repeat scans, the five direction rules, day boundary, notes, inspection), `attendance_import/parsing.py` (target fields `punch_at` / `direction` / `device_serial` — offered only for the layout — and internal `source_note`; hints; `parse_punch_datetime`), `attendance_import/handler.py` (layout `punch_log`, its options, stray layout-specific mappings refused in the other layouts, the day's raw punches shown as a warning).
Frontend: `FileImportWizard.tsx` (target fields filtered by layout, the mapping is sent when the file is re-read, `renderOptions` gets the preview, `describeStats`), `ImportAttendance.tsx` (three-way layout choice, `PunchLogControls`, auto-selects the log layout + device-number matching, pre-selects the terminal the file names when it is registered), `lib/api.ts`. Docs: `docs/attendance-bulk-import.md` ("Raw device punch log"), `docs/file-import.md`.
Deviations: (1) a repeat-scan cluster contributes its FIRST scan as the clock-in and its LAST as the clock-out (the task said only "closer than the debounce are one scan"); (2) a punch with no id / an unreadable time becomes its own rejected row (its Date cell says "[unreadable punch time] …") so it can never be read as "present for the shift"; (3) the review summary reads `batch.stats` through a new `describeStats` hook (task 313's generic groups do not exist yet); (4) the direction controls live in the layout card, not the options card; (5) auto-selecting the terminal from the file's serial column (deferred from 319) is done in `MatchBy` and only when that serial is registered.
Remaining: one look at the screens in a browser (together with 316, 317 and 319), then move to `done/`.

Completed: 2026-11-02
