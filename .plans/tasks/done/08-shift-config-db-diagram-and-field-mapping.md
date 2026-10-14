---
task: 08
title: Shift-configuration domain — ER diagram + column-to-schema field mapping
status: done
depends_on: []
---

# 08 — Shift-configuration domain — ER diagram + column-to-schema field mapping

## Scope

Documentation-only task. Before building the Shift Configuration admin CRUD screens (a
follow-on task, not this one), pin down the DB shape of the shift-configuration cluster in a
proper diagram and an explicit column-to-API field mapping, so the eventual frontend build
doesn't invent its own naming or miss a column.

Covers exactly the six tables that make up "shift configuration":

- `work_location_masters`
- `shift_masters`
- `shift_week_off_details`
- `holiday_calendar_masters`
- `holiday_details`
- `employee_shift_details`

Explicitly **not** in scope: the rest of the attendance/leave domain (devices, punches,
`employee_attendance_details`, `attendance_request_details`, leave tables) — those already have
prose coverage in `docs/leave-and-attendance/01-domain-model.md` §2.6+ and aren't part of the
shift-configuration screen. No application code (models, migrations, modules, frontend)
changes here — this task only touches documentation.

## What already exists (starting point, not to be re-derived from scratch)

- `docs/leave-and-attendance/01-domain-model.md` §2.1-2.5 already has prose + an ASCII sketch
  (no proper ER diagram) for these six tables.
- `.design/sql/Attendance & Leave/HRMS.sql` (lines 55-165) has the original designed
  `CREATE TABLE` statements for all six.
- `backend/app/models/{work_location_master,shift_master,shift_week_off_detail,
  holiday_calendar_master,holiday_detail,employee_shift_detail}.py` are the as-built
  SQLAlchemy models (already migrated and running).
- `backend/app/modules/attendance/schemas.py` has the Pydantic In/Patch/Out schemas exposed
  over the API today for shifts, week-offs, work locations, holiday calendars/holidays, and
  employee-shift assignment (`ShiftIn`/`ShiftPatch`/`ShiftOut`, `WeekOffRuleIn`/`WeekOffsOut`,
  `WorkLocationIn`/`Patch`/`Out`/`DetailOut`, `HolidayCalendarIn`/`Out`, `HolidayIn`/`Patch`/
  `Out`, `EmployeeShiftIn`/`Patch`/`Out`).

As of 2026-08-12, a spot-check confirmed the as-built models for `shift_masters` and
`work_location_masters` match the design SQL column-for-column (including the standard
`is_active`/`archive`/`archived_by_id`/`archived_at`/audit-column tail). Re-verify the other
four tables the same way rather than assuming — the point of this task is to produce a
document someone can trust without re-reading five files.

## Work

1. **ER diagram** — add a Mermaid `erDiagram` block to `docs/leave-and-attendance/01-domain-model.md`,
   replacing the current ASCII sketch (the block around lines 18-29), covering the six tables
   above with:
   - every FK relationship between them (e.g. `shift_masters ||--o{ shift_week_off_details`,
     `holiday_calendar_masters ||--o{ holiday_details`, `employee_shift_details` referencing
     `shift_masters`, `work_location_masters`, and `holiday_calendar_masters`)
   - the tenant FK (`care_delivery_program_master_id` → `care_delivery_program_masters`) called
     out on each entity, since every one of these six tables is CDP-scoped
   - nullability on optional FKs (e.g. `employee_shift_details.work_location_master_id` and
     `holiday_calendar_master_id` are nullable; `holiday_calendar_masters.work_location_master_id`
     nullable = "all locations")
2. **Column-to-schema mapping tables** — for each of the six entities, a Markdown table with
   columns: DB column (from the model) | type | Pydantic Out field (from `schemas.py`, or "—
   not exposed" if the column has no API surface yet) | notes (defaults, validation, FK target).
   Insert these under the relevant `01-domain-model.md` §2.x subsection for each table.
3. **Sync check** — diff each of the six as-built model files against the corresponding
   `CREATE TABLE` in `.design/sql/Attendance & Leave/HRMS.sql`. If everything matches (as it did
   for the two already spot-checked), add one line to §2's intro noting the SQL file is
   confirmed in sync with the built schema as of this task's date. If any column has drifted
   (renamed, added, different default), fix the design SQL file to match the actual built
   schema — the running database is the source of truth, never the reverse.

## Files

- `docs/leave-and-attendance/01-domain-model.md` (diagram + mapping tables + sync note)
- `.design/sql/Attendance & Leave/HRMS.sql` (only if drift is found — sync fix)

## Acceptance criteria

- [x] `01-domain-model.md` has one Mermaid `erDiagram` covering all six shift-configuration
      tables with every FK between them and to `care_delivery_program_masters`, rendering
      cleanly (verified by pasting into a Mermaid live editor or GitHub's inline renderer).
- [x] Each of the six tables has a column-to-schema mapping table listing every DB column and
      its corresponding Pydantic Out field (or "not exposed").
- [x] All six as-built model files have been diffed against `.design/sql/Attendance &
      Leave/HRMS.sql`; any drift found is either fixed in the SQL file or explicitly called out
      as a deliberate deviation with a reason. (No drift found — all six match column-for-column;
      noted inline in `01-domain-model.md` §2.0 rather than editing the SQL file.)
- [x] No files outside `docs/leave-and-attendance/01-domain-model.md` and
      `.design/sql/Attendance & Leave/HRMS.sql` are touched.

Completed: 2026-08-12
