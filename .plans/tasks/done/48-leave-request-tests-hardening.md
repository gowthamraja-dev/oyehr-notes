---
task: 48
title: Leave request/approval backend — full test coverage audit
status: done
depends_on: [42, 43, 44, 45, 46, 47]
---

## As-built notes

Most of this checklist was already satisfied incidentally by the tests written alongside
[[42]]–[[47]] (CLAUDE.md's "add tests in the same change as the feature" rule) — `test_leave.py`
carries 110 test functions covering the ledger primitives, apply/preview, self-service cancel,
manager queue/approve/reject, and notification dispatch. This task's actual work was auditing
that coverage against the checklist below and closing the gaps found:

- **No `.update()`/raw `UPDATE`** touches `employee_leave_balance_ledgers` anywhere in
  `ledger_service.py` or `leave/service.py` — confirmed by grep, none exist. Append-only holds.
- **`is_active`/`updated_at == created_at` on every ledger-writing path** — Availed (approve) and
  Reversal (cancel) were already asserted incidentally by the new full-lifecycle test below;
  Adjustment (admin endpoint) was **not** asserted — added two lines to
  `test_adjust_ledger_writes_one_row_signed`.
- **`balance_after` matches the running per-partition sum** — already covered at the ledger
  primitive level by `test_write_ledger_entry_running_balance_and_append_only_hygiene`
  (Opening → Availed → Adjustment) and now also end-to-end (Availed → Reversal) by the new
  lifecycle test; between the two, all four `txn_type`s are exercised.
- **Concurrent approve** — `test_approve_concurrent_calls_only_one_wins` already used two real
  `SessionLocal()` sessions/threads racing on `approve_leave_request` (not two sequential calls),
  same shape as the ledger-primitive concurrency test — confirmed this is genuine, no fix needed.
- **Leave-year boundary → two `Availed` rows** — already covered by
  `test_approve_across_leave_year_boundary_writes_two_availed_rows`.
- **Full lifecycle happy path (one test, whole chain)** — did not exist; per-step tests covered
  each transition but nothing chained apply → preview-agreement → approve → ledger debit →
  attendance recompute → cancel/reversal → attendance revert, with notifications fired (mocked)
  at each step. Added `test_full_lifecycle_apply_approve_attendance_cancel_notifications`. Apply
  and cancel go through the real self-service HTTP endpoints (`tenant.user` is the applicant);
  approve is called directly against `approve_leave_request` with a constructed `AuthPrincipal`
  for the manager, since no second login exists for a synthetic manager user — same technique
  `test_approve_concurrent_calls_only_one_wins` already used.
- **Security sweep** — manager-on-non-report (403) and employee-on-someone-else's-request (404)
  were already covered per-route (`test_get_employee_balances_manager_non_report_403`,
  `test_queue_manager_non_report_employee_filter_403`,
  `test_request_detail_manager_without_this_report_403`,
  `test_request_detail_and_cancel_404_for_someone_elses_request`); `ledger/adjust` admin-only was
  already covered by `test_adjust_ledger_requires_admin`.
- **Regression** — found and fixed a real bug in a *pre-existing* (task 24) test unrelated to this
  arc: `test_audit_written_on_success_and_not_on_rejection`'s second assertion queried
  `LeavePolicyAudit` with no filter at all (`db_session.query(LeavePolicyAudit).all()`), so it
  failed whenever the shared dev DB had any leftover rows from manual API testing (it did — 3
  real rows from manual testing the day before). Scoped the query by `leave_policy_detail_id`,
  matching the assertion immediately above it. This is the only production/test file touched
  outside `test_leave.py` itself besides the recompute test (which [[46]] already extended;
  no further changes needed there — 17/17 pass).
- Full `uv run pytest` (whole suite, 524 tests): **522 pass**. The remaining 2 failures
  (`test_engagement_email.py::test_send_email_ok`,
  `::test_send_email_resolves_template_variables`) are pre-existing, unrelated to leave/attendance
  (different module, not touched by [[42]]–[[48]]), and fail identically in complete isolation —
  confirmed out of scope for this task, not a regression from this arc.

# 48 — Leave request/approval backend — full test coverage audit

## Discussion

Mirrors [[24-leave-tests]]'s role for the types/policies arc: [[42]]–[[47]] each ship with
inline tests per CLAUDE.md's "add tests in the same change as the feature" rule, but nothing
audits the *combination* against `docs/leave-and-attendance/leave/api-and-pages.md` §7's
standing bar until now. Do the audit-and-fill-gaps pass task 24 did — read every test added by
[[42]]–[[47]] first, then check it against the checklist below and add only what's missing.
Don't duplicate coverage that already exists; note in an "As-built" section (like [[24]]'s) what
was already satisfied incidentally.

## Required coverage (cross-cutting, likely partially covered already)

### Generic (per `api-conventions.md` §7 / CLAUDE.md's testing section)

- [x] Every new route: 401 unauthenticated, 403 wrong-predicate, cross-CDP isolation (a second
      CDP's requests/ledger rows never appear), validation errors, encrypted round-trip.

### Ledger integrity (the module's highest-risk area)

- [x] No test anywhere issues an `UPDATE` against `employee_leave_balance_ledgers` — grep the
      test file and `ledger_service.py`/`leave/service.py` for any ORM `.update()`/raw `UPDATE`
      touching that table; there should be none.
- [x] `is_active` is always `true`, `updated_at == created_at`, on every ledger row across every
      code path that writes one (Availed via approve, Reversal via cancel, Adjustment via the
      admin endpoint).
- [x] `balance_after` equals the running `SUM(quantity) OVER (ORDER BY id)` within each
      `(cdp, employee, type, year)` partition after a realistic sequence of writes (apply →
      approve → cancel-with-reversal → admin adjustment).
- [x] Concurrent approve (two simultaneous approvals racing for the same
      `(employee, type, year)`) — confirm [[45]]'s test for this actually exercises real
      concurrency (two DB sessions/threads/processes), not just two sequential calls in the same
      test session, which wouldn't prove the advisory lock does anything.
- [x] A request straddling a leave-year boundary produces exactly two `Availed` rows on approve,
      correctly split by `leave_year`.

### Full lifecycle happy path (end-to-end, single test)

- [x] Apply → preview matches apply's actual day rows → manager approves → ledger debited →
      attendance date recomputed to `OnLeave` → employee cancels (should fail, already fully in
      the past relative to test's fixed dates, or use future dates and confirm the Reversal
      path) → notification calls fired at each step (mocked). One test walking the whole chain
      catches integration seams the per-task tests miss.

### Security / authz sweep

- [x] A manager can never approve/reject/view a non-report's request (403, matching the
      established "never an empty list" rule).
- [x] An employee can never see or act on another employee's request (404).
- [x] `POST /employees/{id}/ledger/adjust` is admin-only; a manager gets 403.

### Regression

- [x] Full `uv run pytest` (whole suite) green — confirms [[46]]'s changes to
      `attendance_recompute_service.py` didn't regress any existing attendance test.

## Files

- `backend/app/tests/modules/test_leave.py`
- `backend/app/tests/modules/test_attendance_recompute.py` (regression only, likely no new
  tests needed here beyond what [[46]] already added)

## Acceptance criteria

- [x] Every checklist item above has a corresponding test function or is documented in an
      "As-built" note explaining which existing test already covers it.
- [x] `uv run pytest` (full suite) — no regressions in any other module.

Completed: 2026-08-19
