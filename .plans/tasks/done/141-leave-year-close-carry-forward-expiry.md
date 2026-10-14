---
task: 141
title: Leave-year close — carry-forward / expiry ledger job
status: done
depends_on: [138]
---

# 141 — Leave-year close: carry-forward / expiry

## Scope
Nothing implements this today (the ledger's `uq_leave_ledger_system_txn` index already anticipates
`CarryForward` / `LapseExpiry`). New `app/services/leave_year_close_service.py`. Uses the existing
ledger columns only (`leave_policy_detail_id`, `accrual_period`, `source`, `remarks`) — no schema
change.

For each employee × leave type whose leave year ended on `as_of - 1` (year start = the resolved
detail's `reset_month`, default 4 — never assume Jan–Dec):
- Rule = the detail resolved (138) **as of the last day of the closing year** — later edits or a
  new policy version don't reinterpret the closed year.
- `unused = get_balance(old year)`; `unused <= 0` → nothing.
- `carry_forward = false` → one `LapseExpiry` row `-unused` in the old year.
- `carry_forward = true` → `carry = min(unused, max_carry_forward)` (no cap if NULL):
  `LapseExpiry -unused` in the old year, `CarryForward +carry` in the new year (effective = new
  year's first day), remarks record the expired remainder `unused - carry`.
  Scenario 6: unused 8, max 5 → old year closes at 0, new year opens +5, remarks "expired 3".
- Carry is capped by `max_carry_forward` only (`max_balance` caps accrual, per the brief).
- Ledger rows carry `leave_policy_detail_id`, `accrual_period = '<old year>-CLOSE'`,
  `source = 'YEAR_CLOSE'`.
- Idempotent: `uq_leave_ledger_system_txn` makes a re-run a no-op; catch `IntegrityError` per row,
  under the ledger advisory lock (same pattern as accrual).
- A detail of an archived/LEGACY master still closes years it governed (history), but never opens
  new ones beyond the `CarryForward` row.
- Daily `GlobalJobDef` in `job_defs.py`; it only acts on CDPs/types whose year just ended — no
  high-frequency loop.

## Files
- `hrms/backend/app/services/leave_year_close_service.py` (new), `app/services/job_defs.py`
- `hrms/backend/app/tests/modules/test_leave_year_close.py` (new)

## Acceptance criteria
- [x] Scenario 6 exact numbers; no carry-forward → full expiry; zero balance → no rows.
- [x] Run twice → no duplicates.
- [x] reset_month 1 vs 4 close on different dates.
- [x] Editing the detail after the year closed doesn't change what the close wrote.

## Verification notes
- `test_leave_year_close.py` — 13 tests: scenario 6 exact rows (LapseExpiry −8 in 2025 effective
  31-Mar, CarryForward +5 in 2026 effective 1-Apr, remarks "expired 3", provenance
  `leave_policy_detail_id` / `2025-CLOSE` / `YEAR_CLOSE`); uncapped carry; no carry → full
  expiry; zero balance → nothing; re-run later in the month → no duplicates; reset month 1 vs 4
  close on different dates; editing the rule after closing changes nothing; the rule in force on
  the year's last day governs (a new version starting 1-Apr doesn't); a policy archived after the
  year ended still closes it (falls back to the rule that last accrued into the series); a series
  with no governing rule is left open and counted; deferred while the rule's accrual job hasn't
  credited the last period, then closes; two tenants each close with their own rule; registered
  daily at 03:00, after the 02:00 accrual dispatch. All green, plus `test_scheduler.py` and the
  leave suites (209 passed).

## Decisions made while building
- **Runs after accrual and defers behind it.** Closing before the old year's last period is
  credited would strand that credit in a closed year (the close's own idempotency key would then
  block a second close). A series is skipped while its rule's LEAVE_ACCRUAL job cursor
  (`next_run_at`) is on or before the year's last day; the close re-tries every day of the month.
- **No rule → left open, not expired** (logged + counted as `no_rule`) — expiring a balance because
  a policy is misconfigured would silently destroy entitlement.
- `close_due_years(db, as_of, tenant_ids=None)` — the optional tenant filter is for manual
  re-runs and keeps tests off the shared DB's real series.

## Known gaps (for 149's docs)
- A leave request in the closed year that is still **Pending** at close is debited against the
  closed year on approval (the close only settles the ledger balance, not reservations) — it can
  push that year negative. Options: close only after pending requests clear, or reserve at close.
- The local API container runs the in-process scheduler (`enable_scheduler` defaults to true)
  against the shared hrms-dev DB, so this job will act there at 03:00 IST on the 1st of any month
  whose reset month matches a live rule (Oct 1 is the next; hrms-dev rules are mostly April).
- Found here, fixed in 143: Yearly accrual is credited in arrears (see 143).

Completed: 2026-09-29
