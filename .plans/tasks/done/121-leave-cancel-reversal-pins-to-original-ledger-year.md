---
task: 121
title: Leave — cancel reversal pins to the original Availed ledger row's leave_year
status: done
depends_on: []
---

# 121 — Leave — cancel reversal pins to the original Availed ledger row's leave_year

## Context (why this task exists — a real, currently-exploitable balance leak)

Found while investigating why archiving a leave type 409s when it still has a policy
(`archive_leave_type`, `backend/app/modules/leave/service.py:323-348`) and analyzing the
drawback of making that cascade instead of blocking. The blocker itself is fine to remove
(see task 122), but doing so *before* this fix would make the bug below trivially easy to
trigger — any employee with an open approved request under a type that gets bulk-archived.

**Root cause:** `resolve_leave_year(policy, date)` (`service.py:730-742`) labels a date by
`policy.reset_month`, falling back to a hardcoded `tenant_default_month=4` if `policy` is
`None`. `write_availed_ledger_rows` (`service.py:1360-1388`) uses this **once**, at approval
time, to split a request's debit into one `Availed` ledger row per `leave_year` actually
touched — each row's `leave_year`/`quantity`/`effective_date` then become permanent frozen
facts (`employee_leave_balance_ledgers` is append-only — see
`backend/app/models/employee_leave_balance_ledger.py`).

`cancel_my_request` (`service.py:1544-1671`) does **not** read those frozen facts back — it
**re-resolves** the policy fresh at cancel time (`service.py:1585`,
`resolve_leave_policy(..., as_of=request.from_date)`) and recomputes `year` per day
(`service.py:1608-1610`), then looks up an existing `Availed` row filtered on that
freshly-computed `year` (`service.py:1614-1620`) to link as `reversal_of_id` — but if nothing
matches, it still writes the `Reversal` anyway with `reversal_of_id=None`
(`service.py:1621-1627`). `resolve_leave_policy` (`service.py:169-186`) always filters
`archive.is_(False)`, with no "as of that date, historically" escape hatch — so once the
policy row that governed a request's `from_date` is archived, it becomes invisible to this
lookup **for any `as_of`, past or present**, even though `as_of=request.from_date` was
otherwise correctly targeting the right historical window.

### Concrete walkthrough (verified against the actual formulas in the code)

- Policy P1 (Earned Leave, all corps): `reset_month=1`, Monthly accrual 1.75/mo,
  `max_balance=21`, effective 2026-01-01. Under `reset_month=1`, every date labels as its own
  calendar year (`month >= 1` always true) — year-boundary bugs only show up for dates that
  would label *differently* once the fallback (`reset_month=4`) kicks in, i.e. Jan–Mar dates.
- By Dec 2026: 12 × 1.75 = **21.00 days** accrued, all in the `leave_year=2026` bucket.
- Jan + Feb 2027: two more monthly accruals of 1.75 each land in a **fresh, independent**
  `leave_year=2027` bucket (each `leave_year` has its own running `balance_after` chain, keyed
  by `(tenant, employee, leave_type, leave_year)` — `backend/app/services/ledger_service.py:23-24,42-90`).
  Bucket 2027 balance: **3.50**.
- 2027-02-15: employee applies for 3 days, **Mar 10–12, 2027**; approved same day.
  `resolve_leave_year(P1, Mar-10-2027)`: month 3 ≥ reset_month 1 → **leave_year=2027**.
  Availed row written: quantity `-3.00`, `leave_year=2027`, `balance_after = 3.50 − 3.00 = 0.50`.
- 2027-02-25: HR archives the Earned Leave policy (or its type, cascading — see task 122) — no
  replacement policy exists for it going forward.
- 2027-03-01: employee cancels the Mar 10–12 request (still future — full reversal path).
  `resolve_leave_policy(..., as_of=Mar-10-2027)` now returns **None** (P1 is archived).
  `resolve_leave_year(None, Mar-10-2027, tenant_default_month=4)`: month 3 < 4 →
  **leave_year = 2027 − 1 = 2026**.
  Lookup for an Availed row with `leave_year=2026` on this request finds **nothing** (the real
  one is in the 2027 bucket) → `availed_row = None` → still writes `Reversal +3.00` into the
  **2026** bucket, `reversal_of_id=None`.

**Net damage:** the 2027 bucket's `-3.00` Availed debit is **never reversed** — the employee
permanently loses 3.00 days they were correctly approved to get back (real 2027 balance stays
at 0.50 instead of the correct 3.50). The 2026 bucket — already closed out months earlier —
gets a **phantom +3.00 credit** with no debit to offset it and no `reversal_of_id` trail tying
it back to anything. Net raw-count-wide it's a wash (+3/−3), but it's wrong in both years,
invisible to the employee (their *current* balance is short 3 days), and unreconcilable later
without manually diffing ledger rows against request history.

**Forward-looking risk (documented, not yet built):** the year-end carry-forward job
(`docs/leave-and-attendance/leave/ledger.md` §8) doesn't exist in code yet, but per its spec it
will compute `carried = 0 if not carry_forward else min(closing, max_carry_forward)`. If a
policy is archived before that job runs for an employee still sitting on a real balance under
it, `resolve_leave_policy` will return `None` the same way — a naive `if not policy or not
policy.carry_forward` treats `None` as "no carry-forward," lapsing the *entire* balance instead
of the correct `min(closing, max_carry_forward)`. Example: closing balance 21.00,
`max_carry_forward=10` → should carry 10.00 / lapse 11.00; naive-`None` handling would lapse
all 21.00, an extra 10-day loss. Nothing to build now — just don't repeat this mistake when
that job is eventually written.

## Scope

Stop re-deriving `leave_year` from policy state when reversing a request that **already has**
Availed ledger rows. Read the target bucket(s) off those existing rows instead — they are the
permanent, frozen record of what was actually written; the policy that produced them is
irrelevant once they exist.

- In `cancel_my_request`, before computing `by_year`, fetch the request's existing Availed rows:
  `select(EmployeeLeaveBalanceLedger).where(leave_request_detail_id == request.id, txn_type == "Availed").order_by(effective_date)`.
- **Full reversal** (`request.from_date > today`, i.e. `reversal_rows == day_rows` — the common
  "cancel before it starts" path, and the exact path the walkthrough above hits): skip
  `resolve_leave_policy`/`resolve_leave_year` entirely for targeting — for each existing
  `Availed` row, write one `Reversal` with **that row's own** `leave_year`, quantity = its
  negated `quantity`, `reversal_of_id=row.id`. Zero ambiguity, zero dependency on current
  policy/archive state.
- **Partial (mid-leave) reversal**: map each day in `reversal_rows` to the correct existing
  Availed bucket using the buckets' own `effective_date` values as boundaries (sort existing
  Availed rows by `effective_date`; a day belongs to the last bucket whose `effective_date <=`
  that day) instead of re-deriving `resolve_leave_year(policy, day.leave_date)` per day. Sum per
  bucket, write one `Reversal` per bucket touched, each linked via `reversal_of_id`.
- `policy = resolve_leave_policy(...)` and the day-by-day `resolve_leave_year` call in
  `cancel_my_request` (`service.py:1585, 1608-1610`) become unnecessary for this path and should
  be removed — nothing else in the function needs `policy` once targeting is bucket-based.
- Not covered by this task (confirmed unaffected, don't touch): `approve_leave_request` and
  `apply_for_leave`/`_evaluate_apply_gates` are **first writes**, not reversals of an existing
  row. The employee-ledger adjustment endpoint (`adjust_employee_ledger`) is an admin-driven
  fresh correction, not a reversal-of-a-prior-write — leave it alone without re-checking its
  semantics first if picking up more than this task.

## Files

- `backend/app/modules/leave/service.py` — `cancel_my_request`'s Availed-lookup/reversal block
  (`service.py:1544-1671`, specifically the `policy = resolve_leave_policy(...)` line and the
  `by_year`/`availed_row` block).
- `backend/app/tests/modules/test_leave.py` — new tests (see below).

## Tests

- `test_cancel_full_reversal_pins_to_original_availed_leave_year` — reproduce the walkthrough
  above near-verbatim (policy with `reset_month=1`, approve a future request that lands in a
  year whose label would differ under the `reset_month=4` fallback, archive the policy, cancel
  the request) → assert the `Reversal` row's `leave_year` matches the original `Availed` row's
  `leave_year` (not the fallback), `reversal_of_id` is set, and `balance_after` in that bucket
  returns to the pre-Availed value. Also assert the *other* (wrong) bucket got no stray row.
- `test_cancel_mid_leave_partial_reversal_pins_correctly_after_policy_change` — a request whose
  days span two `leave_year` buckets (a genuine year-boundary case, independent of archiving —
  e.g. the policy's `reset_month` changes between approval and a mid-leave cancel), cancel
  mid-leave (only future days reverse) → assert each reversed day lands in its original bucket.
- Re-run the existing cancel/reversal tests (grep `test_cancel_approved` in
  `app/tests/modules/test_leave.py`) to confirm no regression on the ordinary,
  policy-unchanged path.

## Explicitly out of scope

- No change to `approve_leave_request`'s or `apply_for_leave`'s policy resolution — they're
  first writes, not reversals; unaffected by this bug class.
- No change to `adjust_employee_ledger` without separately confirming its semantics first.
- No schema change (no new column) — the fix reads data that's already stored (`leave_year`,
  `quantity`, `effective_date` on existing `Availed` rows).
- No cascade-archive behavior change — that's task 122, which depends on this one.

## Acceptance criteria

- [x] Cancelling a future-dated approved request always reverses into the *same* `leave_year`
      bucket its Availed debit was written to, regardless of any policy change/archive that
      happened in between (`test_cancel_full_reversal_pins_to_original_availed_leave_year`).
- [x] A mid-leave partial cancel spanning a year boundary still splits correctly by original
      bucket (`test_cancel_mid_leave_partial_reversal_pins_correctly_across_two_buckets` — named
      slightly differently than originally sketched above, same coverage).
- [x] Every `Reversal` row this function writes has a non-null `reversal_of_id` whenever a
      matching `Availed` row exists (it always should, post-fix).
- [x] Full `backend/app/tests/modules/test_leave.py` suite passes (the 4 pre-existing, unrelated
      date-drift failures noted this session are still the *only* failures — 171 passed / 4
      failed, up from 167 passed before this task's 2 new tests).

Completed: 2026-09-22
