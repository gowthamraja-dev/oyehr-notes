---
task: 122
title: Leave — archiving a leave type cascade-archives its policies instead of blocking
status: done
depends_on: [121]
---

# 122 — Leave — archiving a leave type cascade-archives its policies instead of blocking

## Context

Reported bug: archiving a leave type currently 409s with "This leave type has an active
policy — archive it first" (`archive_leave_type`, `backend/app/modules/leave/service.py:323-348`)
whenever any non-archived `LeavePolicyDetail` row exists under it — the admin has to manually
archive every policy row first via `DELETE /leave/policies/{id}` before the type-archive will
succeed. Desired behavior: archiving a leave type should cascade-archive all its policies
automatically instead of blocking.

`depends_on: [121]` — cascading makes task 121's bug trivially reachable (any employee with an
open approved request under a type that gets bulk-archived), so 121 must land first. Task 121's
Context section has the full numeric analysis of why; not repeated here.

## Scope

- Extract `archive_policy`'s current body (`service.py:612-639`) into a non-committing helper,
  e.g. `_archive_policy_row(db, principal, policy) -> None` (sets `archive`/`is_active`/
  `archived_by_id`/`archived_at`, writes the `LeavePolicyAudit` "ARCHIVED" row, calls
  `leave_accrual_service.sync_scheduler_job_for_policy`, no-ops if already archived) —
  everything except the final `db.commit()` and the `log_activity`/logger call, which stay with
  each caller so single-policy-archive and cascade-archive can log/commit independently.
- `archive_policy` (route-facing, single-policy) becomes a thin wrapper: fetch by id, call the
  helper, `log_activity` + `db.commit()`.
- `archive_leave_type` (`service.py:323-348`): replace the `live_policy` 409-raise with a loop —
  fetch every `LeavePolicyDetail` row for the type with `archive.is_(False)`, call
  `_archive_policy_row` on each, **then** archive the type itself, all in one transaction with a
  single `db.commit()` at the end (type + all its policies archived together, or not at all).
  Enrich the existing `log_activity` call's `deleted_data` with the cascaded policy count for
  traceability.
- **UX decision: silent cascade.** No extra confirmation step listing affected policy/request
  counts — same single confirm dialog as today on the frontend, just reworded (see below).
- Frontend (`frontend/src/dashboards/hrAdmin/Leave.tsx`): update `handleArchiveLeaveType`'s
  confirm copy (currently "Archive this leave type? It will no longer be selectable for new
  requests.") to mention its policies are archived too, since the
  409-then-manually-archive-the-policy-first dance no longer exists.

## Files

- `backend/app/modules/leave/service.py` — `archive_policy`, `archive_leave_type`.
- `backend/app/tests/modules/test_leave.py` — new tests (see below); update
  `test_archive_leave_type_with_live_policy_rejected` — currently asserts a 409; this test's
  premise no longer holds and needs to become a "cascades instead of blocking" assertion, not
  just deleted.
- `frontend/src/dashboards/hrAdmin/Leave.tsx` — `handleArchiveLeaveType` confirm copy.

## Tests

- `test_archive_leave_type_cascades_to_all_policies` — a type with 2+ non-archived policy rows
  (e.g. one all-corps, one corp-specific) → one `DELETE /leave/types/{id}` call → assert all
  policy rows now have `archive=True, is_active=False, archived_by_id` set, and the type itself
  is archived — replaces `test_archive_leave_type_with_live_policy_rejected`'s old 409
  assertion.
- `test_archive_leave_type_cascade_is_idempotent_with_already_archived_policies` — a type with
  one already-archived policy and one live one → archiving the type archives only the live one
  without erroring or double-writing an audit row for the already-archived one.
- `test_archive_leave_type_cascade_then_cancel_still_reverses_correctly` — the integration case
  this whole investigation was about: create a policy, approve a future request under it,
  archive the *type* (cascading to the policy), cancel the request → assert it still reverses
  into the correct bucket (relies on task 121's fix — this is the test that proves the
  dependency was worth it).

## Explicitly out of scope

- No fix for the balance-card-disappears-when-a-type-is-archived UX inconsistency (an archived
  type vanishes from `/leave/me/balances` while its past requests remain visible in request
  history — a known, accepted display quirk, not a data-integrity bug; separate task if wanted).
- No implementation of the year-end carry-forward job (§8, not built yet) — see task 121's
  Context for the forward-looking risk (it will need the same "resolve historically" discipline
  task 121 establishes, or must be guaranteed to run/settle every employee's balance *before* a
  policy is archived).
- No confirmation-dialog blast-radius summary (policy/open-request counts) before cascading —
  per the UX decision, the cascade is silent.
- No cleanup of the stale `employee_leave_assignment`/`leave_assignment_audit` `.pyc` files
  found in `__pycache__` during research (dead code from a fully-reverted prior design, unrelated
  to this task).

## Acceptance criteria

- [x] Archiving a leave type with any number of non-archived policies succeeds (no more 409) and
      archives every one of them in the same call
      (`test_archive_leave_type_cascades_to_all_policies`).
- [x] Already-archived policies under the type are left untouched, not re-audited
      (`test_archive_leave_type_cascade_is_idempotent_with_already_archived_policies`).
- [x] A request approved under a policy that gets cascade-archived via its type still cancels
      and reverses correctly (`test_archive_leave_type_cascade_then_cancel_still_reverses_correctly`).
- [x] Frontend confirm dialog copy updated; `npx eslint`/`tsc --noEmit` clean on the touched file.
- [x] Full `backend/app/tests/modules/test_leave.py` suite passes (171 passed / 4 pre-existing,
      unrelated date-drift failures — same as before this task).
- [x] `docs/leave-and-attendance/leave/api-and-pages.md`'s endpoint table updated to match
      (also filled in the previously-undocumented `DELETE /policies/{id}` route).

Completed: 2026-09-22
