# Attendance report export — plan

Goal: HR/managers download attendance as CSV or XLSX in several report layouts, built on ONE shared export engine
(the mirror of the staged import engine, `docs/file-import.md`) so the next module's export is a handler, not a new endpoint family.

## Decisions (made so the tasks can start; flag if wrong)

* **"Commonized" = one engine + one UI, not new DB tables.** Exports are stateless: generated on request, streamed back, never stored.
  So there is **no new table / migration** and the `hrms-dbml-first` gate does not apply. If async jobs (very large orgs) are wanted later,
  an `export_jobs` table is a separate, DBML-first task.
* Engine lives in `backend/app/modules/file_export/`: `ExportHandler` + registry (`_LAZY` like imports), shared `ColumnSpec`,
  CSV and XLSX writers, filename/MIME/audit handling, one `build_router(handler)`.
* Report types are handlers under `backend/app/modules/attendance_export/`; they all read the same scoped employee-day rows the
  register already uses (`dashboard_service._build_scoped_rows_for_range`) — **same scoping, same status rules, no second source of truth**.
* Auth: `ATTENDANCE` READ (what the existing `/attendance/register/export` uses). Reporting managers stay limited to their team by
  `_scoped_employees`; no new RBAC grid row, no migration. Routes are a **plain** `APIRouter` (binary body; `EncryptedRoute` cannot carry it),
  same as the existing `_export_router`.
* Limits: range ≤ 62 days; rows × columns ≤ 250,000 cells, else 422 with a message telling the user to narrow the filters.
* CSV cells beginning `= + - @` are prefixed with `'` (formula-injection guard) — one place, in the engine.
* Dates `dd-MMM-yy`; times 24h in the employee's work-location time zone (as the existing CSV does).

## Report types

| key | Layout | For |
| --- | --- | --- |
| `attendance_ledger` | **Basic.** One row per employee, one column per date, cell = status code (P / A / HD / WO / H / L / —) + totals columns | the muster-roll / attendance ledger |
| `hours_ledger` | One row per employee, one column per date, cell = worked hours (`8:45`), totals: hours, late minutes, early-exit minutes, overtime | timesheet / hours review |
| `monthly_summary` | One row per employee, no date columns: present / absent / half / week-off / holiday / leave / payable days / late count / total hours | payroll input |
| `daily_log` | One row per employee-day: in, out, worked, late, early exit, status, regularized, source | audit / detail (replaces the current register CSV) |

## Tasks (`.plans/tasks/ongoing/`)

| # | Task | depends_on |
| --- | --- | --- |
| 274 | Common export engine (backend) | — |
| 275 | Shared attendance report data layer + Attendance Ledger report | 274 |
| 276 | Hours ledger report | 275 |
| 277 | Monthly summary report | 275 |
| 278 | Daily log report + move the existing register CSV onto the engine | 275 |
| 279 | Frontend: shared `FileExportDialog` + Attendance "Export report" entry | 275 (276–278 as they land) |
| 280 | Docs, CLAUDE.md section, knowledge | 275–279 |
