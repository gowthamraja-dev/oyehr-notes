---
task: 90
title: Leave — bounded catch-up window for the OnJoining one-shot accrual grant
status: done
depends_on: []
---

# 90 — Leave — bounded catch-up window for the OnJoining one-shot accrual grant

## Context (why this task exists, and what turned out to already be done)

User ask: "the entire process should have auto assignment rules based on the leave policy
configuration — when a new employee is onboarded, an HR Manager shouldn't have to go and
assign leave every time; it should be automated by the leave accrual job. Also confirm the
refund-on-cancel behavior is a request-level flow."

Investigated both claims against the actual code before planning anything:

1. **Routine onboarding is already fully automatic — no task needed there.**
   `run_leave_accrual` (`backend/app/services/leave_accrual_service.py:102-212`, daily cron via
   `app.core.scheduler`/`job_defs.py`) already iterates **every** active employee with a
   `joining_date` set × **every** active leave type with a resolvable policy, with zero
   dependency on any prior ledger/assignment row. A brand-new employee is included
   automatically starting the very next cron run — `prorate_on_joining` is already handled
   (`_compute_raw`, lines 70-86). `leave.service.create_leave_assignment` (task 62-ish, the
   "Assign Leave" admin/HR-Manager modal) exists for the separate ad-hoc case — opening-balance
   migration, carry-forward, one-off manual correction — not routine onboarding. HR does not
   need to manually assign leave today for the common case; this part of the ask is already
   satisfied by existing code.

2. **Refund-on-cancel is already fully implemented and tested — no task needed there.**
   `cancel_my_request` (`backend/app/modules/leave/service.py:1387-1481`, backing
   `POST /leave/requests/{id}/cancel`) already writes a `Reversal` ledger entry when an
   `Approved` request is cancelled — full reversal if the leave hasn't started, partial (only
   the still-future days) if cancelled mid-leave. This is documented as **RESOLVED** in
   `docs/leave-and-attendance/leave/gaps.md` gap #8, and covered by
   `test_cancel_approved_before_from_date_full_reversal`,
   `test_cancel_approved_mid_leave_partial_reversal`, and
   `test_cancel_approved_fully_past_rejected` in `app/tests/modules/test_leave.py`. Nothing to
   build here.

3. **The one real gap found: the `OnJoining` accrual frequency is a fragile one-shot trigger.**
   Unlike the periodic frequencies (Monthly/Quarterly/Yearly, which naturally get another
   chance at their next period boundary if a run is missed), `OnJoining` fires **only** when
   `employee.joining_date == as_of` exactly
   (`backend/app/services/leave_accrual_service.py:152-154`):
   ```python
   if policy.accrual_frequency == "OnJoining":
       if employee.joining_date != as_of:
           continue
   ```
   If the cron doesn't run on that exact calendar day (deploy/downtime — an accepted,
   documented system-wide gap per `docs/leave-and-attendance/shared/jobs-and-scheduling.md`
   §3, "no supported way to recover [a missed day]") **or** — the much more common real-world
   case — HR creates/backdates the `EmployeeMaster` row a few days *after* the person's actual
   `joining_date` (paperwork lag), the grant is **silently and permanently skipped**. There is
   no catch-up logic anywhere in the file. This is the one piece of "auto assignment on
   onboarding" that is genuinely broken today, and it's what this task fixes.

   This is deliberately scoped narrower than the system-wide "no missed-run recovery" policy in
   `jobs-and-scheduling.md` — that policy is about *periodic* jobs, where a missed tick is
   naturally caught at the next tick. `OnJoining` has no "next tick": it is structurally a
   one-time event, so it needs its own bounded retry rather than inheriting the periodic jobs'
   "cadence is a tuning knob" guarantee, which doesn't apply to a one-shot trigger.

## Changes

`backend/app/services/leave_accrual_service.py`:

- Add a module-level constant, e.g. `_ONJOINING_CATCHUP_DAYS = 30`, with a short comment
  explaining it's a bounded exception to the "no missed-run recovery" policy, specifically
  because `OnJoining` has no natural next occurrence to catch up at.
- Change the `OnJoining` branch's skip condition from exact-day equality to a bounded window:
  ```python
  if policy.accrual_frequency == "OnJoining":
      if not (employee.joining_date <= as_of <= employee.joining_date + timedelta(days=_ONJOINING_CATCHUP_DAYS)):
          continue
      effective_date = employee.joining_date
      raw = policy.accrual_quantity
  ```
- `effective_date` stays `employee.joining_date` (unchanged) — this is what keeps it safe:
  the existing partial unique index `uq_leave_ledger_system_txn`
  (`employee_leave_balance_ledgers`, keyed on cdp+employee+type+year+txn_type+effective_date)
  means every day within the window after the first successful credit hits the same unique key
  and is caught as `IntegrityError` → `duplicate_skipped`, exactly like the existing dedup path
  for periodic accruals. No new state, no existence-check query — same idempotency mechanism
  already in the file, just given more days to succeed once.
- Update the module/function docstring's implicit assumption if it currently reads as "one
  attempt only" for OnJoining, so a future reader doesn't assume exact-day semantics still hold.

`docs/leave-and-attendance/shared/jobs-and-scheduling.md`:

- Add a short note under the "Leave accrual" row (or immediately after it) documenting this as
  the one deliberate, bounded exception to guarantee/§3's "no supported way to recover a missed
  day" — link back to why (one-shot trigger, no natural next tick) so it doesn't read as an
  inconsistency with the rest of that doc.

## Files

- `backend/app/services/leave_accrual_service.py`
- `docs/leave-and-attendance/shared/jobs-and-scheduling.md`
- `backend/app/tests/modules/test_leave.py` (new tests, see below — confirm the actual test
  file that covers `run_leave_accrual`; it may be `test_leave.py` or a dedicated
  `test_leave_accrual.py` — check before adding)

## Tests

Add (module/function names indicative, match existing style in whichever file already tests
`run_leave_accrual`):

- `test_onjoining_accrual_catches_up_within_window` — employee joined N days ago (N <
  `_ONJOINING_CATCHUP_DAYS`), cron's first-ever run for this employee happens today (simulating
  a joining date that was backdated at data-entry time, or a missed cron day) → the `OnJoining`
  grant still fires, ledger shows one `Accrual` row dated `joining_date`.
- `test_onjoining_accrual_does_not_double_credit_within_window` — run `run_leave_accrual` twice
  (or more) on different days within the catch-up window → exactly one `Accrual` row exists,
  no duplicate credit (exercises the existing unique-index dedup path, now reached from more
  than one calling day).
- `test_onjoining_accrual_gives_up_after_window` — employee joined `_ONJOINING_CATCHUP_DAYS + 1`
  days ago with no prior successful accrual → no `Accrual` row is written, and no exception is
  raised (silent skip, matching the rest of the file's tolerance for unrecoverable data-quality
  gaps).
- Re-run the existing accrual test(s) covering the exact-day case to confirm no regression:
  `OnJoining` still credits correctly when the cron happens to run exactly on `joining_date`
  (the common, un-degraded path).

## Explicitly out of scope

- No change to `create_leave_assignment`/the "Assign Leave" admin/HR-Manager UI — it remains
  the correct place for ad-hoc/manual grants; routine onboarding was already automatic before
  this task and stays that way.
- No change to the cancellation/refund flow (`cancel_my_request`) — already correct and tested
  (gap #8 in `docs/leave-and-attendance/leave/gaps.md`, RESOLVED).
- No general backfill/recovery CLI for missed cron days across *all* jobs — that is a
  deliberate, accepted, documented system-wide trade-off
  (`docs/leave-and-attendance/shared/jobs-and-scheduling.md` §3). This task adds a narrow,
  bounded exception for the one job whose failure mode is "permanently and silently lost," not
  a general recovery mechanism.
- No change to periodic (Monthly/Quarterly/Yearly) accrual semantics — unaffected by this
  change, they already self-heal at the next period boundary.

## Acceptance criteria

- [x] A new employee whose `EmployeeMaster` row is created (or whose `joining_date` is
      backdated) up to `_ONJOINING_CATCHUP_DAYS` days after their actual joining date still
      receives their `OnJoining` leave grant on the next cron run.
      (`test_onjoining_accrual_catches_up_within_window`)
- [x] Running the accrual job repeatedly across multiple days within the catch-up window never
      double-credits (confirmed by test, relying on the existing unique-index dedup).
      (`test_onjoining_accrual_does_not_double_credit_within_window`)
- [x] Beyond the catch-up window, the grant is silently skipped forever (unchanged philosophy:
      bounded, not unlimited, recovery) — no exception raised, `stats` unaffected.
      (`test_onjoining_accrual_gives_up_after_window`)
- [x] The exact-day case (cron runs the same day as `joining_date`) still works — no regression.
      (`test_onjoining_accrual_exact_day_still_works`)
- [x] `docs/leave-and-attendance/shared/jobs-and-scheduling.md` documents this as a deliberate,
      narrow exception with its rationale, not left implicit in code only.
- [x] `uv run pytest app/tests/modules/test_leave.py -q` passes — 172 passed (there was no prior
      test file for `run_leave_accrual`; the 4 new tests plus the full leave suite were run
      together to confirm no regression).
