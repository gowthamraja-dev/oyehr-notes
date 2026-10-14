---
task: 97
title: Adopt Loguru logging in the attendance module
status: done
depends_on: [94]
---

# 97 — Adopt Loguru logging in the attendance module

## Scope
Add logging calls to `app/modules/attendance` only (`router.py`, `service.py`,
`dashboard_service.py`) using the shared logger from [[94-loguru-core-config]]
(`from app.core.logging import logger`). Does not touch `shifts` or `leave` (tasks 95, 96)
or any shared file beyond the import.

No `print()` statements exist in this module today — additive instrumentation only.

## Files
- `backend/app/modules/attendance/router.py` (383 lines)
- `backend/app/modules/attendance/service.py` (1518 lines — clock in/out, day resolution,
  regularization)
- `backend/app/modules/attendance/dashboard_service.py` (611 lines — manager summary,
  register, exceptions, period analytics, export)

## What to log
- **INFO**: clock-in/clock-out events, day-resolver runs and their resolved status,
  regularization request submit/approve/reject, register export triggered (who, date
  range, row count).
- **WARNING**: expected rejections (duplicate punch, no-shift-day guard, past-lock guard,
  regularization outside window) with the specific guard name and context that triggered it
  — this module already has known edge cases around these guards (see the "no shift day
  closed" and "no past lock guard" work in `.plans/tasks/done/86-*` and `92-*`), so a clear
  WARNING line is what will make the next edge case fast to diagnose instead of another
  multi-session debug.
- **ERROR** (`logger.exception(...)`): unexpected exceptions in day resolution, clock
  processing, or dashboard aggregation queries.
- Dashboard/export endpoints run aggregate queries — log query parameters (CDP, date range,
  filters) and result row counts on INFO, not the full result payload.
- Always include the CDP/tenant id and employee id, same as [[95-shifts-module-logging]]
  and [[96-leave-module-logging]].

## Acceptance criteria
- [x] `logger` imported from `app.core.logging` in all three files; no stdlib `logging`
      import added.
- [x] Clock in/out, day resolution, and regularization approve/reject each produce at least
      one log line; dashboard/export endpoints log their query params + row count.
- [x] `uv run pytest app/tests/modules/test_attendance.py` — passes unchanged (part of the
      328-test run across all three modules).
- [x] Verified via the test run: `logs/app.log` shows real clock/holiday-import lines at the
      correct levels with tenant context, e.g.
      `Clocked in: tenant=6901 employee=7275 punch=530 ... late_by_minutes=138`,
      `Clock-in rejected: tenant=6902 employee=7276 already clocked in at ...`, and
      `Holiday CSV import rejected: tenant=6896 calendar=191 1 row error(s)`.

Completed: 2026-09-03

## Status
Code changes complete in all three files: `logger` imported from `app.core.logging` in
`service.py`, `dashboard_service.py`, and `router.py`.

- `service.py`: WARNING at every clock-in/clock-out guard (already-clocked-in, no
  active clock-in, locked day, no shift scheduled), the holiday CSV import guards
  (bad encoding, row-level errors), and every `submit_regularization`/`cancel_my_request`/
  `approve_request`/`reject_request` rejection (window/monthly-cap/duplicate/locked/no-approver,
  already-actioned, missing rejection reason). ERROR (`logger.error`, no live traceback to
  capture since these are explicit invariant checks, not caught exceptions) on the two
  defensive 500 checks in `approve_request` where a materialized punch isn't attributed to
  the recomputed day. INFO on every success: `clock_in`, `clock_out`, `import_holidays_csv`,
  `submit_regularization`, `cancel_my_request`, `approve_request`, `reject_request`.
- `dashboard_service.py`: INFO on `get_manager_analytics`, `get_manager_register`,
  `get_exceptions` (both the summary-only and filtered-by-type paths), `get_employee_analytics`,
  and `export_register_csv` — each logs its query params (tenant, date, filters) and the
  resulting row/headcount, never the row payload itself.
- `router.py`: one WARNING added at the multipart content-type guard in `import_holidays`
  (the one guard that lives at the router layer, not in `service.py`).
- No `except` blocks exist around unexpected failures in this module today (`_validate_time_zone`'s
  `except ZoneInfoNotFoundError` and the CSV loop's `except ValueError` are both expected-input
  validation, already covered by the WARNING logs above, and out of this task's stated
  clock/day-resolver/regularization/dashboard scope) — so no `logger.exception(...)` call sites
  were needed; nothing was wrapped in a new `try/except` just to add one.
- Admin-config CRUD (work locations, holiday calendars/holidays outside the CSV import path)
  was left uninstrumented — not mentioned in this task file's "What to log" section, and adding
  it would have gone beyond additive instrumentation into scope not asked for.

Verified: `python3 -m ast` parses all three files; `uv run ruff check app/modules/attendance/router.py
app/modules/attendance/service.py app/modules/attendance/dashboard_service.py` → all checks passed.
Runtime smoke test (the last checklist item) and the existing test suite are blocked pending
loguru actually being installed (task 94 — blocked on `CODEARTIFACT_AUTH_TOKEN`). Not moved to
`done/`.
Completed: pending — leaving in ongoing/ until 94 unblocks and the runtime checks can run.
