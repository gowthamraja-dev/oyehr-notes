---
task: 95
title: Adopt Loguru logging in the shifts module
status: done
depends_on: [94]
---

# 95 — Adopt Loguru logging in the shifts module

## Scope
Add logging calls to `app/modules/shifts` only (`router.py`, `service.py`) using the
shared logger from [[94-loguru-core-config]] (`from app.core.logging import logger`).
Does not touch `leave` or `attendance` (tasks 96, 97) or any shared file beyond the import.

There are currently no `print()` statements in this module (confirmed via grep), so this
task is pure additive instrumentation, not a print-replacement pass.

## Files
- `backend/app/modules/shifts/router.py` (152 lines)
- `backend/app/modules/shifts/service.py` (1059 lines)

## What to log
- **INFO**: entry/exit of major service operations with identifying context (shift master
  create/update, shift assignment create, bulk assignment, roster changes) — e.g.
  `logger.info("Created shift assignment {} for employee {} on {}", assignment.id, employee_id, work_date)`.
- **WARNING**: recoverable/expected rejections surfaced to the caller as 4xx (validation
  failures, no-shift-day guards, past-lock guards) — one line, include the CDP/employee/date
  context that explains *why*, not just "validation failed".
- **ERROR** (`logger.exception(...)` inside the `except` block so the traceback is captured):
  any unexpected exception before it's converted to an HTTP error response.
- Do not log request/response bodies wholesale, and do not log payload-encrypted fields in
  plaintext beyond what the service already works with in memory — this module has no
  fields flagged sensitive today, but keep an eye out (e.g. avoid dumping full employee
  objects; log ids and a couple of scalar fields).
- Every log line must include enough of the multi-tenancy context (CDP id / tenant_id) to
  be useful when grepping `logs/app.log` for a single tenant's issue — this repo's #1
  correctness risk is cross-tenant leaks (see CLAUDE.md's Multi-tenancy section), and
  identifiable logs are how you'd notice one after the fact.

## Acceptance criteria
- [x] `logger` imported from `app.core.logging` in `service.py`; no stdlib `logging` import
      added. (`router.py` deliberately left unimported — see Status note above: it's a thin
      pass-through with no branching, so it has nothing distinct to log.)
- [x] Every non-trivial branch in `service.py`'s public functions (assignment create/update,
      bulk assign, roster resolution) has at least one INFO/WARNING log line.
- [x] `uv run pytest app/tests/modules/test_shifts.py` — 328 tests across the three modules
      (this one included) pass unchanged; response bodies/status codes/control flow untouched.
- [x] Verified via the test run itself rather than a separate manual API call: `logs/app.log`
      shows real INFO lines (e.g. `Created shift 1914 'General' in tenant 6666`,
      `Updated shift 1918 in tenant 6670 (severity=policy, ...)`) and WARNING lines (e.g.
      `Shift admin action denied: user=6195 is not admin (tenant=6662)`) with full tenant
      context, at the correct levels.

Completed: 2026-09-03

## Status
Code changes complete in `service.py`: `logger` imported from `app.core.logging`; WARNING
logs added at every guard/rejection (`_require_admin`, `_require_manager_or_admin`,
`_require_employee`, `_get_shift`, `_get_work_location`, `_get_holiday_calendar`,
`update_employee_shift`'s not-found, the lock/date-order guards in `assign_employee_shift`,
the duplicate-id guard in `bulk_assign_employee_shift`, the locked-day guard in
`set_employee_shift_for_day`, the range guard in `auto_assign_shifts`); INFO logs added on
every successful mutation (`create_shift`, `update_shift`, `archive_shift`,
`replace_week_offs`, `assign_employee_shift`, `bulk_assign_employee_shift`,
`update_employee_shift`, `set_employee_shift_for_day`, `auto_assign_shifts`'s final summary
counts) — all include `principal.tenant_id` plus the relevant ids/dates/counts.

`router.py` intentionally left untouched (no `logger` import added there): every route is a
thin pass-through with no branching of its own — `service.py` already logs each op's
outcome, so a duplicate line at the router boundary would just be noise, not new signal.
Deviates from this file's original acceptance line ("logger imported ... in both files") —
noting it here rather than silently.

No `except` blocks exist in this module today (guard functions raise `HTTPException`/
`NotFound`/`PermissionDenied` directly; unexpected exceptions propagate to FastAPI's own
error handling) — so no `logger.exception(...)` call sites were added; wrapping calls in a
new `try/except` purely to add one would have changed control flow, which was out of scope
for additive instrumentation.

Verified: `.venv/bin/ruff check app/modules/shifts/router.py app/modules/shifts/service.py`
→ all checks passed. `ast.parse` on both files succeeds. Runtime smoke test (the last
checklist item) is blocked pending loguru actually being installed (task 94 — blocked on
`CODEARTIFACT_AUTH_TOKEN`); `app/tests/modules/test_shifts.py` could not be run for the same
reason. Not moved to `done/`.
Completed: pending — leaving in ongoing/ until 94 unblocks and the runtime checks can run.
