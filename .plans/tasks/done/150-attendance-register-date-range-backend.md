---
task: 150
title: Attendance date-range filter — range contract + register/exceptions over a range (backend)
status: done
depends_on: []
---

# 150 — Register & exceptions accept a date range (backend)

> Requirement "4. Attendance Date Range Filters — the attendance module should provide a
> date-range filter." Scope decision (user, 29-Sep-26): **Manager/Admin register only**
> (HR Manager Attendance page + HR Admin Insights register, incl. CSV export), and a
> multi-day range shows **one row per employee-day** (flat log, paginated).
> Work in **`workspace-2/hrms/`**; paths below are relative to it. Run `uv sync` in
> `backend/` first (no `.venv` there yet).

## Scope

Today `GET /api/v1/attendance/register` and `GET /api/v1/attendance/exceptions` take a single
required `date`; every row is built by `_build_scoped_rows(db, principal, target_date, …)` in
`backend/app/modules/attendance/dashboard_service.py`, which resolves one shift per employee
(`_resolved_shifts_for`), loads that day's `EmployeeAttendanceDetail` rows or synthesizes a
transient row for a never-punched day (`_attendance_rows_for_date`), and flags pending
regularizations (`_pending_regularization_employee_ids`). This task makes both endpoints accept
a range and return one row per `(employee, date)`.

**Not in this task:** `/analytics` and `/register/export` → task 151. Frontend → 152-154.
Docs → 155. Employee "My Attendance", the employee-profile tab and the regularization inboxes
are out of scope for this requirement (user decision).

### Query contract (shared by `/register`, `/exceptions`, and — task 151 — `/analytics`, `/register/export`)
- `date` becomes optional; new `from` (`Query(alias="from")`, same as `/me/daily`) and `to`.
- Resolution, in one shared router dependency (e.g. `_resolve_date_range` →
  `tuple[date, date]`) so all four routes agree:
  - only `date` → `from = to = date` (**existing callers unchanged**).
  - `from` + `to`, no `date` → the range.
  - any other combination (none; `date` + `from`; only one of `from`/`to`) → `422`
    `"Provide either date, or both from and to"`.
  - `from > to` → `422`.
  - span `(to - from).days + 1 > MAX_REGISTER_RANGE_DAYS` (`31`, module constant) → `422`
    naming the limit.
  - `logger.warning(...)` with the offending values before each 422 (logging convention).
- Future dates: no new backend restriction (the single-date path has none today); the UI caps
  at today.

### Row shape — additive
`RegisterRowOut` (`backend/app/modules/attendance/schemas.py`) gains
`attendance_date: date` and `day_label: str` (weekday name, reuse `service._WEEKDAY_NAMES`).
Populated for single-date calls too — additive, no existing field changes.
`ExceptionsOut` gains `from`/`to` (use `Field(alias="from")` like `EmployeeAnalyticsOut.from_`);
`date` stays and equals `from`.

### Range semantics
- Rows = every scoped employee × every date in `[from, to]`, real row if it exists else the
  same read-time synthesized row `_attendance_rows_for_date` builds today (so Absent/WeekOff/
  Holiday/YetToCheckIn resolve exactly as in the single-date view — never re-derived differently).
- `shift_id` filter applies **per employee-day**, against that date's resolved shift.
- `search` is per employee (unchanged); `status` filter per row (unchanged).
- `has_pending_regularization` per employee-day: a Pending, non-archived request whose
  `from_date <= d <= to_date`.
- Exceptions: `counts` = number of matching **employee-days** across the range, per type;
  `stale_open_session` therefore counts each later day the forgotten session drags into
  (consistent with the single-date meaning).
- Sort: new sort key `date` (add to `_RegisterSort` Literal and `_sort_key`) → date desc, then
  status priority, then name. Every other sort key tie-breaks on date desc, then name. Backend
  default stays `status` (the frontend sends `sort=date` in range mode, task 153).

### Building rows efficiently
Refactor rather than loop `_build_scoped_rows` per day (that would re-query per date):
- New `_build_scoped_rows_for_range(db, principal, from_, to, department, shift_id)`;
  `_build_scoped_rows(target_date)` becomes the `from == to` case of it (single code path).
- Prefetch once per request: scoped employees; all `EmployeeAttendanceDetail` rows in range
  (**keep the `care_delivery_program_master_id == principal.tenant_id` filter** — no RLS);
  `_open_punch_map`; pending requests overlapping `[from, to]` (tenant-filtered), bucketed by
  date in Python.
- Split `_attendance_rows_for_date` so the per-day loop takes the prefetched rows/open
  punches instead of querying.
- Shift resolution is the hot spot (`resolve_effective_shift` ≈ 3 queries per employee-date,
  plus `resolve_day_type` for every synthesized row). For real rows, use the row's stored
  `shift_master_id` for name/filter where possible. **Measure** a 200-employee × 31-day register
  on the dev DB; if it exceeds ~2 s, add a batched
  `resolve_effective_shifts_for_range(db, tenant_id, employee_ids, from_, to)` in
  `backend/app/services/calendar_resolver_service.py` that loads standing assignments/rosters
  for the range in bulk, and use it here. Record the measured timing in this file's
  "What shipped" when done.
- Pagination stays post-filter/post-sort in Python (existing pattern), `limit` ≤ 200.

## Files
- `backend/app/modules/attendance/router.py` — `_resolve_date_range` dependency, `from`/`to`
  params on `/register` and `/exceptions`, `_RegisterSort` gains `"date"`.
- `backend/app/modules/attendance/dashboard_service.py` — range builder, split
  `_attendance_rows_for_date`, date-aware sort/pending lookup, `get_manager_register` /
  `get_exceptions` take `from_`/`to`.
- `backend/app/modules/attendance/schemas.py` — `RegisterRowOut.attendance_date/day_label`,
  `ExceptionsOut.from_/to`.
- `backend/app/services/calendar_resolver_service.py` — batched resolver (only if the measurement
  says so).
- `backend/app/tests/modules/test_attendance_dashboard.py` — new tests.

## Acceptance criteria
- [x] `?date=X` responses are byte-for-byte the same as before apart from the two new row
      fields (existing `test_attendance_dashboard.py` tests pass unchanged).
- [x] `?from=A&to=B` returns `employees × days` rows with correct `attendance_date`, incl.
      synthesized Absent / WeekOff / Holiday days and a real Present day.
- [x] 422 for: no params; `date`+`from`; only `from`; `from > to`; 32-day span.
- [x] Tenant scoping: attendance rows and pending requests from another CDP on the same dates
      never appear (neither in rows nor in exception counts).
- [x] Manager scope: only direct reports across the whole range; admin sees the whole CDP.
- [x] `shift_id` filter applied per day when an employee's shift changes mid-range.
- [x] `has_pending_regularization` true only on the dates the request covers.
- [x] Exceptions `counts` are employee-day totals across the range; `type=` rows carry dates.
- [x] `sort=date` orders date desc → status → name; pagination `total` equals all employee-days
      after filters.
- [x] 401 without a token, 403 for a role without `READ ATTENDANCE` (existing gate), on range
      calls too.
- [x] Performance measured and recorded; batched resolver added if over budget.
- [x] `uv run pytest app/tests/modules/test_attendance_dashboard.py app/tests/modules/test_attendance.py` green.

## What shipped
Branch `feature/gowtham_AttendanceDateRange` in `workspace-2/hrms/`.

- `router.py`: `_date_range` dependency (`_DateRange`) resolves `date` | `from`+`to` and
  returns 422 for a missing/mixed pair, `from > to`, or a span over 31 days, each with a
  `logger.warning`. `/register` and `/exceptions` use it. `_RegisterSort` gains `date`.
  `/analytics` and `/register/export` still take `date` (task 151).
- `dashboard_service.py`: `MAX_REGISTER_RANGE_DAYS = 31`. `_build_scoped_rows_for_range` is
  now the single builder (`_build_scoped_rows(date)` is its one-day case).
  `_attendance_rows_for_date` is a thin wrapper over the new `_attendance_rows_for_pairs`, which
  prefetches stored rows / open punches / open-punch business dates once.
  `_pending_regularization_pairs` makes one query for the range. `_sort_key` tie-breaks on newest
  day, then name. `_sort_rows` handles `date` (days in `direction`, status → name within a day).
  Range exceptions list newest day first; a single date keeps status → name.
- `schemas.py`: `RegisterRowOut.attendance_date` / `day_label`, `ExceptionsOut.from` / `to`
  (`date` = `from`).
- `calendar_resolver_service.py`: batched `resolve_effective_shifts_for_range` and
  `resolve_day_types_for_pairs`, rule-for-rule equivalents of `resolve_effective_shift` /
  `resolve_day_type`. They were needed: the per-pair path made **2,236 queries / 16.5 s for 20
  employees × 31 days** (≈3.6 queries per employee-day, ~7–9 ms round-trip to the dev DB).
  Batched: **8 queries**, 20×31 = 0.11 s, **200×31 (6,200 rows) = 0.29 s**, 200×1 = 0.12 s.
  Measured inside a rolled-back transaction on the dev DB.
- Tests: 26 new in `test_attendance_dashboard.py` (single-date row fields, employee-day rows,
  admin/manager scope, 422 matrix × both endpoints, 31-day boundary, cross-CDP rows + requests,
  per-day shift filter, pending flag per covered day, date sort both directions, pagination
  total, exception employee-day counts + order, 401/403). 5 new in
  `test_calendar_resolver_batch.py` compare batch against single across the fallback chains
  (default weekend, mid-range shift change / termination / late start, foreign-tenant shift,
  assignment → location → all-locations holiday calendar incl. Restricted/archived, week-off
  full / half / Nth Saturday / inactive, work-location time zone).

Verification: `test_attendance_dashboard.py` 93 passed (67 pre-existing unchanged + 26 new),
`test_calendar_resolver_batch.py` 5 passed, attendance/recompute/assembler/authz 294 passed.
The wider `-k "attendance or shift or leave or calendar or authz or payroll"` run had 85 failures,
all `UndefinedColumn employee_type_master_id`: the shared dev DB is on revision `8012104013b3`
(migrated from other branches, e.g. task 137's leave-policy rework), which `main`'s leave model
predates. That's pre-existing schema drift, unrelated to this task.

Completed: 2026-09-29
