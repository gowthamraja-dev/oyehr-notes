# Attendance bulk import — plan

Schema: `.plans/attendance-bulk-import-schema-v2.dbml` (**draft v2, awaiting approval** — makes the staging tables
type-agnostic so other file imports can reuse them). v1, `.plans/attendance-bulk-import-schema.dbml`, was approved
2026-10-26 and is now **superseded**; its Project note still holds the why and the 12 attendance decisions (with-or-
without times, skip-invalid, locked days with a reason, undo, …) and none of them change. This plan does not restate
either file. All HRMS code goes in `workspace-2/hrms/`.

## v2: one engine, many import types (supersedes the attendance-only layout below where they differ)
The staging pattern (stage → validate → review → confirm → settle → undo, resumable, 30-day scratch rows) is not
attendance-specific, so it is built once:

- **Tables** (schema v2): `import_batches` (+`import_type`, `options`, `stats`, generic `units_*`), `import_field_mappings`,
  `import_rows` (+`reference_id`, `dedupe_key`, `parsed`). `attendance_punch_details.import_batch_id` points at `import_batches`.
- **Engine** `app/modules/file_import/`: `parsing.py` (csv/xlsx, date cells), `service.py` (preview, stage, reads,
  serializers), `runner.py` (claim / heartbeat / failure / phase dispatch), `lifecycle.py` (confirm / discard / resume / undo),
  `jobs.py` (resume + retention for every type), `schemas.py`, `router_factory.py`, and `handlers.py` — the
  `ImportHandler` protocol plus a registry keyed by `import_type`.
- **Handler contract** (what a type supplies): `import_type`, `resource` (its RBAC grid row), `prefix`, `target_fields`;
  `parse_options(db, principal, raw) -> dict` (validate options + scope checks, e.g. locked-day override);
  `validate_chunk(db, batch, rows, columns)`; `commit_chunk(db, batch, rows)` (turn `Valid` rows into the real records and mark
  them `Imported` in the same transaction); `settle_chunk(db, batch, undo) -> bool` (post-commit work such as recompute;
  returns whether more remains); `prepare_undo(db, batch)`; `can_undo(db, principal)`; `supports_undo`.
- **Attendance handler** `app/modules/attendance_import/handler.py` is the first one: it holds everything attendance-specific that
  exists today (target fields, row validation rules, punch commit, per-day recompute + audit, undo, locked-day scope checks).
- **Router factory**: `build_routers(handler)` returns the encrypted JSON router and the plain multipart router with the
  handler's prefix and grid resource; `attendance_import/router.py` is `build_routers(attendance_handler)`. URLs stay
  `/api/v1/attendance-import/...`. `stage` takes the handler's options as one `options` JSON form field.
- A new import type later = one handler + one RBAC row + one frontend config; no new tables, runner or job. The existing
  `employee_import` is NOT moved onto the engine in this work.
- Every engine read filters on the caller's tenant AND the handler's `import_type`.

## What the move re-does vs keeps (state at the pause)
Built and verified on the v1 attendance-only layout: parsing, staging, 56 validation tests, runner / lifecycle / undo /
resume job / retention (84 tests), RBAC row `ATTENDANCE_IMPORT` (grid, defaults, roles tests, data migration written),
router + schemas written (28 API tests green, 7 failing only because of a test-fixture mix-up, not the app). All of that
logic is kept; the v2 work moves it behind the handler seam, renames the tables/columns per the DBML's mapping table, and
re-runs the same tests against the new names. Tasks 267–268 do that; 264–266 are re-scoped on top.

## Scope
HR uploads one CSV/XLSX covering many employees and many days. The system stages and validates
every row, HR reviews, confirms, and the valid rows become raw punches; the touched days are
recomputed by the existing `recompute_attendance_day`. Imports can be undone.

**In scope**
- One row = one employee-day. Columns (mapped by HR): `employee_id` (required, matches
  `employee_masters.emp_id`), `date` (required), `in_time`, `out_time`, `status` (all optional).
- Rows WITH times → IN/OUT punches at those times (employee's shift time zone; a night-shift OUT earlier
  than IN rolls to next day). Only one of the two → single punch + warning.
- Rows WITHOUT times → "Present for the scheduled shift": IN = shift start, OUT = shift end,
  `punch.raw.synthesized = true`, staged row `times_from_shift = true`, warning shown in review.
- `status` is honoured only to skip: Absent / Leave / Week-off / Holiday → row `Skipped`.
- Skip-invalid import, existing-day policy Skip|Merge, locked-day opt-in with reason, payroll-period guard,
  history, undo, crash-resume, 30-day staged-row retention, new `ATTENDANCE_IMPORT` RBAC resource.

**Out of scope (v1):** raw swipe-per-row punch logs, half-day / partial statuses, replacing existing punches,
changing leave balances, re-running payroll, server-side error CSV (the UI builds it from the rows API),
refactoring `employee_import` onto the new shared parser.

## Flow
```
POST /attendance-import/parse        multipart  → headers, sample rows, row_count, suggested mapping
POST /attendance-import/stage        multipart  → batch (Validating) + mappings + Pending rows      [CREATE]
   └ background: runner.validate     chunks of 200 rows, heartbeat → every row Valid|Rejected|Skipped → batch Staged
GET  /attendance-import/batches/{id}             poll: status, counters, progress
GET  /attendance-import/batches/{id}/rows        review: ?status=Rejected&limit&offset
POST /attendance-import/batches/{id}/confirm     Staged → Running                                    [CREATE]
   └ background: runner.commit       chunks of 500 Valid rows → punches (+ rows Imported) in ONE txn per chunk
   └ background: runner.recompute    chunks of ~25 days: recompute_attendance_day + audit row → Done
POST /attendance-import/batches/{id}/discard     Staged → archived
POST /attendance-import/batches/{id}/undo        Done → Undoing → Undone (needs reason + org-wide scope)
POST /attendance-import/batches/{id}/resume      Failed/stale → continue
GET  /attendance-import/batches                  history, newest first
```
Scheduled job `attendance_import_resume` (every 5 min, per CDP) continues batches in
Validating/Running/Undoing whose `heartbeat_at` is stale (> 3 min), and purges staged rows of
Done/Undone/archived batches older than 30 days.

## Backend (`app/modules/attendance_import/`)
- `models` (task 261): three new files + `import_batch_id` on `attendance_punch_details`, migration, guarded
  hrms-dev DDL.
- `parsing.py`: csv/xlsx parse (preserves time-of-day cells), date/time parsing, status normalisation.
- `service.py`: `parse_file`, `stage_batch` (insert batch + mappings + Pending rows, 5,000-row cap, tenant check
  of override scope), `validate_chunk`, history/detail/rows reads.
- `runner.py`: `claim` (compare-and-set on `heartbeat_at`, no locks held across commits — pooled connections
  make session advisory locks unsafe), `run_validation`, `run_commit`, `run_recompute`, `run_undo`, `run_batch`
  dispatching on status; each chunk commits and advances `heartbeat_at`; every step is resumable from row/punch
  state alone.
- `router.py`: encrypted router for JSON, plain router for the two multipart endpoints (same split as
  `employee_import`). Gates: `RequirePermission("READ"|"CREATE", "ATTENDANCE_IMPORT")`; `override_locked` and
  undo additionally `sees_whole_org(db, principal, "ATTENDANCE")`.
- `app/services/job_defs.py`: register `attendance_import_resume`.
- RBAC: `ATTENDANCE_IMPORT` (READ, CREATE) in `roles/permissions.py`, default grids in `roles/defaults.py`
  (Admin and HR Admin yes; HR Manager and Employee no — grant on Roles & Permissions), plus a migration inserting it into existing tenants' default
  grids the same way `e2a8c4f6b913` (feed permission row) did.

### Validation rules (per row, in `validate_chunk`)
Reject: missing employee id / date; unknown or ambiguous (two employees) employee id in the tenant; unparseable
date or time; date in the future; date before `joining_date` or after `relieving_date`; second row for the same
(employee, date) in the file; no shift scheduled that day (`resolve_effective_shift` is None); IN/OUT gap under
60 s, or OUT ≤ IN on a non-night shift; date inside a processed/approved/locked `payroll_periods` row; day locked
(`employee_attendance_details.is_locked`) unless the batch has `override_locked`.
Skip: status column says Absent/Leave/Week-off/Holiday; day already has punches (`punch_count > 0`) and
`existing_day_policy = Skip`.
Warn (row stays Valid): times_from_shift; single punch; day already has punches under Merge; locked day under override. (A "week-off/holiday — OT will be created" warning was dropped: it needs the day-type resolver, ~2 more queries per row.)

### Recompute step (`run_recompute`)
Per (employee, `raw.attendance_date`) group of the batch's unprocessed punches: snapshot the old row, call
`recompute_attendance_day(..., force=<day is locked and batch.override_locked>)`, then check each punch got
`employee_attendance_detail_id == row.id` — a punch that did not (outside every shift window, or the day locked
meanwhile) counts in `days_failed` and adds an error to its staged row. Stamp `processed_at`, write one
`attendance_audit_logs` row (`BulkImported`, or `LockedDayOverride` with the reason), bump `days_recomputed`.
One `user_activity_details` row per batch at confirm and at undo.

## Frontend (`frontend/src/dashboards/shared/`)
`ImportAttendance.tsx`, mirroring `ImportEmployees.tsx` (upload → map columns → options → review → result)
with the `useConfirm()` dialog for confirm/discard/undo, `DateField` for any date, shimmer skeletons, dd-MMM-yy
dates. Review step polls the batch while `Validating`, then shows counters and a Rejected/Skipped/Warnings table
with a "Download errors (CSV)" button built client-side. A History tab lists batches with progress, Undo and
Resume. Entry point: an "Import attendance" button on the HR attendance screen, shown only with
`usePermission("CREATE", "ATTENDANCE_IMPORT")`. API client functions in `src/lib/api.ts` (multipart = plain
`fetch`, JSON = `secureFetch`).

## Tests (`app/tests/modules/test_attendance_import.py`)
Parse (csv, xlsx incl. time cells); each validation rule; with-times vs without-times punches; stage → validate →
confirm → recompute end to end against real shifts; idempotent re-confirm / re-upload; resume from a half-done
batch; locked day with and without override (and override without whole-org scope → 403); payroll-period guard;
undo; tenant scoping (another tenant's batch id → 404, another tenant's `emp_id` never resolves); 401/403; encrypted
round trip for the JSON router (see `test_encryption.py`).

## Docs
`docs/attendance-bulk-import.md` (file layout, statuses, the runner/resume model, locked-day and undo rules,
how to apply the migration on hrms-dev), linked from the Attendance section of `CLAUDE.md`.

## Open decisions
None blocking. Two to revisit after v1: stage cap (5,000 rows) and chunk sizes once timed on the shared DB;
whether `employee_import` should adopt `parsing.py`.


## Status (2026-10-27)
Done and verified: tasks 261 (v1 tables, superseded by 267), 262, 263 (logic now in the engine), 264, 267, 268 — backend, engine, RBAC, 116 import
tests + authz/roles cases, and a real-commit smoke of the runner against the local test DB (own sessions, per-chunk commits, undo, failure path).
Task 266 (docs): `docs/file-import.md`, `docs/attendance-bulk-import.md`, linked from both CLAUDE.md files.
Task 265 (frontend): written, typechecks, lints clean — **not yet driven in a browser**; that is the one open item.
Not done, by decision: moving `employee_import` onto the engine; a server-side error CSV (the wizard builds it in the browser).
