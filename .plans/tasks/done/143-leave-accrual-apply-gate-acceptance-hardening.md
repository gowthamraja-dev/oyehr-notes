---
task: 143
title: Accrual + apply-gate acceptance scenarios hardening
status: done
depends_on: [138, 139, 140]
---

# 143 — Accrual & apply-gate acceptance hardening

## Scope
Prove brief §32 scenarios 1–5 end to end through provider-mapping resolution (the accrual engine
already exists — `leave_accrual_service.process` / `process_onboarding`, one `SchedulerJob` per
periodic detail, daily dispatcher, idempotency via `uq_leave_ledger_accrual_period`). Fix whatever
the scenarios expose:
1. Monthly CL 1/month — one credit per month; `process` twice → no duplicate.
2. Yearly EL 18 — per leave year with `reset_month` 4.
3. Quarterly SL 3.
4. Joining mid-year — `prorate_on_joining` true → prorated, false → full; onboarding credit +
   later scheduled run → no double credit; re-assigning the same policy → no double credit.
   OnJoining never repeats.
5. Balance 11, accrual 2, `max_balance` 12 → ledger row quantity 1, remarks record forfeited 1.

**Known bug found in 141 — Yearly accrual is credited in arrears.**
`leave_accrual_service._resolve_period` treats a `Yearly` rule's period as the whole leave year,
and `process` only credits a period once `period_end <= as_of` — so an existing employee's yearly
entitlement (e.g. EL 18) is credited on the day *after* the leave year ends, into the year that
just ended, and is then immediately carried forward / expired by the year close (141). Only
`process_onboarding` credits a yearly rule up front (at joining). Scenario 2 must credit the
entitlement at the **start** of each leave year (effective the year's first day, into the new
year), idempotently per `accrual_period = '<year>'`; keep Monthly/Quarterly in arrears (a month is
earned by working it). The year close already defers on the rule's SchedulerJob cursor, so check
that cursor semantics still hold for a start-of-period yearly job.

Accrual eligibility (brief §16), add what's missing:
- `_eligible_employees` credits only employees whose resolved detail **is** this job's detail
  (winner takes all; corp-scoped detail skips other corps).
- `applicable_after_days` probation gate (NULL = none) — today only checked at apply time.
- Master/detail/leave type active, not archived, in date as of the period end (nullable dates open).
- In-place detail edits: periods already credited are never recomputed; only future periods use
  the new values (document in the job's docstring).

Apply path: no resolved detail for the type → clear 422 `NO_POLICY` ("No leave policy applies to
you for this leave type") instead of a None error; preview returns the same code. Gates keep using
the leave type's own rules (notice, max consecutive, half day, document, negative balance, gender)
and the existing shift/week-off + holiday calendar for day counting (never hardcoded weekends).

## Files
- `hrms/backend/app/services/leave_accrual_service.py`, `app/modules/leave/service.py`
- `hrms/backend/app/tests/modules/test_leave_accrual_scenarios.py` (new)

## Acceptance criteria
- [x] Scenarios 1–5 each a named test, green.
- [x] Probation gate + corp-scoped detail skip tests.
- [x] `NO_POLICY` apply + preview tests.

## Verification notes
- `test_leave_accrual_scenarios.py` — 15 tests, all green: scenario 1 (Monthly 1/month → Jan/Feb/Mar
  rows, leave year 2025 under an April reset, re-run writes nothing; a month isn't credited before
  it ends); scenario 2 (Yearly 18 credited on 1-Apr into the new year, nothing mid-year, next year
  on the next 1-Apr; reset month 1 honoured); scenario 3 (Quarterly Q1 + Q2); scenario 4
  (mid-year joiner prorated 12 → 6 once — onboarding, a later up-front catch-up run and the sweep
  don't double it; no proration → 12; OnJoining given once per leave type even after moving to
  another policy with its own OnJoining rule); scenario 5 (balance 11 + accrual 2, max 12 →
  credited 1, "forfeited 1"); probation gate delays Monthly accrual to Apr–Jun; OnJoining behind a
  30-day gate is granted by the sweep on the day it ends; the sweep catches a late record but not
  a 59-day-old joiner; a rule scoped to another corp accrues nothing; the sweep is scheduled
  daily; NO_POLICY in preview (`no_policy`) and apply (422 with the message).
- Full leave set + `test_authz.py` + `test_scheduler.py`: 318 passed.

## What changed
- `leave_accrual_service`: Yearly credited **up front** (period due at its start; effective the
  year's first day or the eligibility day; into the new leave year); Monthly/Quarterly unchanged
  (arrears). Eligibility = `joining_date + leave_type.applicable_after_days`; proration runs from
  it. One `_grant_first_credit` path shared by `process_onboarding` (registration event) and the
  new daily `grant_first_credits` sweep (`GLOBAL_JOB_DEFS["leave_first_credit"]`, 02:30, 30-day
  catch-up window, `tenant_ids` filter). OnJoining at most once per employee + leave type.
- **Bug fixed along the way:** `sync_scheduler_job_for_policy` set a new job's cursor one period
  late, silently skipping the rule's first period. Now the cursor is the first period's start.
  One-off repair `scripts/fix_leave_accrual_cursors.py` (dry run by default; only touches jobs
  exactly in the old creation state, never run) — **applied to hrms-dev 2026-09-29 with the
  user's OK: 16 jobs repaired (12 Monthly Sep, 1 Quarterly Q3, 3 Yearly 2026); re-run = no-op.**
- `leave/service._evaluate_apply_gates`: `no_policy` violation right after tenancy (winner takes
  all — an uncovered type is unavailable). Test fixture `_basic_leave_type` now gives its type a
  zero-accrual DEFAULT rule.

## Behaviour change to know
- Leave types with **no rule in the employee's policy** can no longer be applied for, even when
  `allow_negative_balance` is on. On hrms-dev that newly blocks APRC (2) and ASGCONC (1); other
  uncovered types were already rejected as "insufficient balance". Fix = add the type to the policy.

Completed: 2026-09-29
