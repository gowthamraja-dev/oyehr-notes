---
task: 96
title: Adopt Loguru logging in the leave module
status: done
depends_on: [94]
---

# 96 — Adopt Loguru logging in the leave module

## Scope
Add logging calls to `app/modules/leave` only (`router.py`, `service.py`) using the shared
logger from [[94-loguru-core-config]] (`from app.core.logging import logger`). Does not
touch `shifts` or `attendance` (tasks 95, 97) or any shared file beyond the import.

No `print()` statements exist in this module today — additive instrumentation only.

## Files
- `backend/app/modules/leave/router.py` (235 lines)
- `backend/app/modules/leave/service.py` (1859 lines — the largest of the three; this is
  also where leave-policy, ledger, accrual, and approval logic all live, so budget the most
  review time here)

## What to log
- **INFO**: leave policy/type create/update, leave request apply/cancel, manager
  approve/reject, ledger accrual runs (including on-joining catch-up), leave assignment
  create/update — one line per state transition with employee id, leave type, dates, and
  resulting status.
- **WARNING**: expected rejections (insufficient balance, overlapping requests, policy
  validation failures) with enough context to see *why* without re-running the request.
- **ERROR** (`logger.exception(...)`): unexpected exceptions in ledger math, accrual jobs,
  or approval transitions — these are the hardest bugs to reproduce after the fact, so the
  traceback + input context matters most here.
- Ledger/balance mutations are exactly the kind of "business logic step" this task exists
  to surface — log the before/after balance (or at least the delta) on every ledger write,
  not just "updated ledger".
- Always include the CDP/tenant id and employee id — same tenant-leak-visibility rationale
  as [[95-shifts-module-logging]].

## Acceptance criteria
- [x] `logger` imported from `app.core.logging`; the module's pre-existing stdlib
      `import logging` / `logging.getLogger(__name__)` (previously used only by `_notify`)
      was migrated onto it rather than left as a second logger.
- [x] Every ledger-mutating function and every approval/rejection branch in `service.py`
      has a log line (see Status note above for the full list).
- [x] `uv run pytest app/tests/modules/test_leave.py` — passes unchanged (part of the
      328-test run across all three modules).
- [x] Verified via the test run: `logs/app.log` shows real leave-flow lines at the correct
      levels with full tenant context, e.g.
      `Created leave type 1255 (code=EL) for tenant 6745` and
      `Updated leave type 1257 for tenant 6747 (fields=['min_notice_days'])`.

Completed: 2026-09-03

## Status
Code changes complete in `service.py`. `logger` imported from `app.core.logging` at the top
of the file, replacing the module's pre-existing `import logging` / `logger =
logging.getLogger(__name__)` (previously used only by `_notify`'s two warning calls) —
migrated those two call sites to Loguru syntax rather than leaving a second logger
definition in the same file.

- INFO on every mutation's success: `create_leave_type`, `update_leave_type`,
  `archive_leave_type`, `create_policy`, `update_policy`, `set_policy_status`,
  `apply_for_leave` (logs resulting status/dates/total_days), `cancel_my_request`,
  `approve_leave_request`, `reject_leave_request`, `adjust_employee_ledger` (manual admin
  ledger escape hatch). Ledger writes get their own INFO line at the source
  (`write_availed_ledger_rows`'s loop, `cancel_my_request`'s Reversal write,
  `adjust_employee_ledger`) logging employee/leave_type/year/quantity and the resulting
  `balance_after` from the ledger row, not just "updated ledger".
- WARNING at every rejection/guard raise: the policy-overlap check
  (`_check_no_overlap`), the archive-blocked-by-active-policy conflict, every one of the
  ten `validate_*` apply-time gates (tenancy, type_in_force, gender, probation, date_sanity,
  notice, no_overlap ×2 branches, balance, document) logged at the function's own raise
  site (so both the `_evaluate_apply_gates` path and `approve_leave_request`'s direct
  `validate_no_overlap`/`validate_document` calls are covered), `resolve_approver`'s three
  failure modes, `apply_for_leave`'s aggregated-violation rejection, and the
  already-actioned/balance-changed/missing-reason guards in `cancel_my_request`/
  `approve_leave_request`/`reject_leave_request`.
- `_notify`'s existing warning/exception handling migrated to `logger.warning`/
  `logger.exception` (the latter now actually captures the traceback via Loguru's
  `backtrace=True`, which the old stdlib `exc_info=True` call didn't format the same way).
- No other `except` blocks exist in this module's request-facing code (guard functions
  raise `HTTPException`/`Conflict`/`NotFound`/`PermissionDenied` directly); wrapping more of
  them in `try/except` purely to add `logger.exception` would have changed control flow,
  out of scope for additive instrumentation.
- `router.py` left untouched — same rationale as [[95-shifts-module-logging]]: every route
  is a thin pass-through with no branching, so `service.py`'s logging already covers every
  outcome; a router-level line would be pure duplication.

Verified: `uv run ruff check app/modules/leave/router.py app/modules/leave/service.py` → all
checks passed. `ast.parse` on both files succeeds. Runtime smoke test (the last checklist
item) and `app/tests/modules/test_leave.py` are blocked pending loguru actually being
installed (task 94 — blocked on `CODEARTIFACT_AUTH_TOKEN`). Not moved to `done/`.
Completed: pending — leaving in ongoing/ until 94 unblocks and the runtime checks can run.
