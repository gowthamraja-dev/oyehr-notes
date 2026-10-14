---
task: 185
title: Leave policy rule — configurable accrual timing (Pre / Post), admin UI + backend
status: ongoing
depends_on: []
---

# 185 — Leave policy rule: configurable accrual timing (`Pre` / `Post`), admin UI + backend

**Where:** the top-level `hrms/` clone (the user's choice, 2026-10-06). The work is uncommitted
on `feature/gowtham_AttendanceDateRange`; nothing is committed yet.

## Why
When a periodic accrual is credited is hard-coded today, in
`backend/app/services/leave_accrual_service.py:_is_up_front`:

| Frequency | Today | Meaning |
|---|---|---|
| `Monthly` / `Quarterly` | arrears | Credited the day after the period ends. The month is earned by working it. |
| `Yearly` | up front | Credited on the first day of the leave year, into that year (task 143). |
| `OnJoining` | n/a | A one-time grant that is never scheduled. |

HR can't choose otherwise. For example, they can't credit 1.5 days of EL on 1-Jan for January (up
front monthly), or credit a Yearly entitlement at year end. This task makes the timing a per-rule
setting.

## Naming: `accrual_timing` with values `Pre` / `Post`
It sits beside the existing rule columns `accrual_frequency`, `accrual_quantity`,
`prorate_on_joining` and `reset_month`:

- **Column:** `accrual_timing`. The `accrual_` prefix groups it with `accrual_frequency` and
  `accrual_quantity`. "Timing" says *when in the period* and doesn't overlap with "frequency"
  (*how often*).
- **Values:** `Pre` | `Post`. These are short PascalCase strings, like `Monthly` / `OnJoining`
  in `accrual_frequency`.
  - `Pre` means the credit lands at the **start** of the period (in advance / up front).
  - `Post` means the credit lands **after the period ends** (in arrears). This is today's
    Monthly/Quarterly behaviour.
- **UI label:** "Credit timing". The options are "Start of period (Pre)" and
  "End of period (Post)".

Alternatives considered: `credit_timing` (doesn't group with the `accrual_*` columns);
`Advance`/`Arrears` (correct payroll terms, but the request was for a pre/post keyword);
`accrual_mode` (too vague).

## Scope

### Backend
1. **Model** (`backend/app/models/leave_policy_detail.py`). Add the column after `accrual_quantity`:
   ```python
   accrual_timing: Mapped[str] = mapped_column(String(10), server_default=text("'Post'"))  # Pre|Post; ignored for OnJoining
   ```
   Extend the class docstring with one line about timing.
2. **Migration** (autogenerate, then review). Add the NOT NULL column with server default `'Post'`.
   Then **backfill `Yearly` rows to `'Pre'`** in the same revision:
   `UPDATE leave_policy_details SET accrual_timing = 'Pre' WHERE accrual_frequency = 'Yearly'`.
   This keeps today's behaviour exactly for existing rows. The downgrade drops the column. Run
   it through `scripts/migrate.py upgrade heads`, not `alembic upgrade head` (the nhforms branch
   is the second head).
3. **Schemas** (`backend/app/modules/leave/schemas.py`):
   - Add `ACCRUAL_TIMINGS = {"Pre", "Post"}` next to `ACCRUAL_FREQUENCIES`.
   - Create schema (~l.123): `accrual_timing: str | None = None`, with a validator.
     If it's omitted, default it from the frequency: `Yearly` → `Pre`, otherwise `Post`. Use a
     `model_validator(mode="after")` so existing API callers get today's behaviour unchanged.
   - Update schema (~l.162): `accrual_timing: str | None = None`, with a validator.
   - Out schema (~l.213): `accrual_timing: str`. Also add it to the resolution-panel out schema
     (~l.439) as `accrual_timing: str | None`.
4. **Service writes** (`backend/app/modules/leave/policy_service.py` ~l.126 create, ~l.399
   rule copy/clone). Pass `accrual_timing` through. Every place that copies a rule (for example,
   "new version of a policy") must copy it too.
5. **Accrual engine** (`backend/app/services/leave_accrual_service.py`):
   - `_is_up_front(policy)` becomes `return policy.accrual_timing == "Pre"`. It already drives
     all three decisions: `_period_is_due` (start ≤ as_of vs end ≤ as_of),
     `_period_leave_year` (period start vs end), and in `_process_period` the
     `resolve_on`/`effective` dates. No other branch should change.
   - Rewrite the module docstring's "When a period is credited" paragraph: timing is now
     per-rule, and the defaults are Monthly/Quarterly `Post` and Yearly `Pre`.
   - **Scheduler cursor: no translation is needed.** `next_run_at` is always "start of the
     next unprocessed period", whatever the timing. Switching `Post`→`Pre` makes the current
     period due at once. Switching `Pre`→`Post` leaves the already-credited current period
     behind the cursor. Add a test for each direction to prove neither one double-credits or
     skips (the `uq_leave_ledger_accrual_period` key is the safety net).
   - **Leave unchanged (call this out in the PR):** `_grant_first_credit` still grants a
     joiner's first (prorated) period immediately, for both timings. For `Post`, that means the
     first period is paid before it ends. This is today's behaviour, and changing it belongs in
     a separate task.
   - `OnJoining` ignores `accrual_timing`.
6. **Logging.** The existing INFO line on a rule create/update should include `accrual_timing`.

### Admin UI (HR Admin → Leave → Policies)
1. **Types** (`frontend/src/lib/api.ts` ~l.3494 rule type, ~l.4148 resolution type). Add
   `accrual_timing: "Pre" | "Post"` (nullable in the resolution type). Optionally export
   `type AccrualTiming = "Pre" | "Post"` from `dashboards/hrAdmin/leaveEntitlement.ts` next to
   `AccrualFrequency`.
2. **Policy stepper rule card**
   (`frontend/src/dashboards/hrAdmin/Leave_components/LeavePolicies.tsx`):
   - Add `accrual_timing` to the draft row type (~l.239), `fromRule` (~l.258), `toPayload`
     (~l.269) and the new-rule default (~l.341). New-rule default: `Pre`, because the default
     frequency there is `Yearly`.
   - Add a **"Credit timing"** `<select>` right after "Credited" (~l.462), using the same
     `labelCls`/`inputCls` and `readOnly` handling. Options: "Start of period (Pre)" /
     "End of period (Post)". **Hide it (or disable it, showing "—") when the frequency is
     `OnJoining`.**
   - When the frequency changes, reset the timing to the frequency's default (`Yearly` → `Pre`,
     otherwise `Post`) **only if** the admin hasn't touched it in this edit. Simplest version:
     always reset on a frequency change. That's acceptable; choose one and note it.
   - Rule summary line (~l.280/519): add "· credited at start" / "· credited at end".
3. **Read-only display.** `dashboards/shared/PolicyResolutionPanel.tsx` (~l.41) should add the
   same "credited at start/end" suffix. `MyLeave.tsx` doesn't need to change unless it already
   explains when a credit arrives.

### Docs
- `docs/leave-and-attendance/leave/ledger.md` ~l.349–351: replace the fixed rule with the
  `accrual_timing` description and its defaults.
- `docs/leave-and-attendance/shared/jobs-and-scheduling.md` l.20: same change in the
  leave-accrual row.

**Out of scope:** first-credit timing for `Post` joiners (see 5 above), timing for `OnJoining`,
and any change to `scheduler_jobs` (the frequency stays its only shape field).

## Files
- `backend/app/models/leave_policy_detail.py`
- `backend/alembic/versions/<new>_leave_policy_detail_accrual_timing.py`
- `backend/app/modules/leave/schemas.py`
- `backend/app/modules/leave/policy_service.py`
- `backend/app/services/leave_accrual_service.py`
- `backend/app/tests/modules/test_leave_accrual_scenarios.py` (and the policy API tests)
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/hrAdmin/leaveEntitlement.ts`
- `frontend/src/dashboards/hrAdmin/Leave_components/LeavePolicies.tsx`
- `frontend/src/dashboards/shared/PolicyResolutionPanel.tsx`
- `docs/leave-and-attendance/leave/ledger.md`, `docs/leave-and-attendance/shared/jobs-and-scheduling.md`

## Acceptance criteria
- [x] Migration `c5e2a7d41f93` is hand-written and existence-guarded, like `b7d41e9a2c05`,
      because shared hrms-dev is stamped at the orphan `8012104013b3`. Verified on a throwaway
      Postgres: Yearly→`Pre`, others→`Post`; a re-run keeps an admin's choice; the downgrade
      drops the column.
- [x] **Applied to shared hrms-dev on 2026-10-06**, at the user's request. The migration's own
      `upgrade()` was run through Alembic's Operations, and the `alembic_version` stamp stays
      `8012104013b3`. Result: the column is `varchar(10)` NOT NULL with default `'Post'`. The
      Monthly (39), Quarterly (6) and OnJoining (2) rules are `Post`, and the Yearly (47) rules
      are `Pre`. Equivalent SQL for another database stamped the same way:
      `ALTER TABLE leave_policy_details ADD COLUMN IF NOT EXISTS accrual_timing varchar(10) NOT NULL DEFAULT 'Post';`
      then `UPDATE leave_policy_details SET accrual_timing='Pre' WHERE accrual_frequency='Yearly';`.
- [ ] Test run against hrms-dev after applying: not done yet (the permission check blocked it).
      Run `uv run pytest -q app/tests/modules/test_leave_accrual_scenarios.py app/tests/modules/test_leave_policy_masters.py`
      from `backend/`.
- [x] `POST` a rule without `accrual_timing` → `Yearly` gets `Pre` and `Monthly` gets `Post`
      (backward compatible). `POST`/`PATCH` with `"Mid"` → 422.
- [x] Monthly + `Pre`: the January credit is written on 1-Jan (`effective` = period start), and a
      run on 15-Jan doesn't write February.
- [x] Monthly + `Post` (unchanged): January is credited on 1-Feb.
- [x] Yearly + `Post`: the year's credit lands the day after the leave year ends, into the leave
      year that just ended (`_period_leave_year` uses the period end).
- [x] Switching a live rule `Post`→`Pre` mid-month credits the current month once, with no
      duplicate on the next run. Switching `Pre`→`Post` neither re-credits nor skips the next month.
- [x] CDP scoping is unchanged: a rule in CDP A can't be read or edited from CDP B (existing
      policy API tests still pass, plus one that covers the new field).
- [ ] Admin stepper (built; tsc and eslint clean; **browser check still to do**): the "Credit timing" select shows, saves and reloads. It's hidden or disabled
      for On joining, read-only when the policy is read-only, and shown in the rule summary.
- [x] Leave and admin-org suites on a throwaway DB: 321 passed. The 62 failures also fail without
      this change (that DB has no `status_masters` seed rows). `tsc --noEmit` and eslint are clean.
- [x] Docs updated: ledger.md §7, jobs-and-scheduling.md, admin-configuration.md, domain-model.md,
      config-knobs.md, api-and-pages.md.

## Implementation notes
- The model has a frequency-aware Python `default` (`_default_accrual_timing`) plus a `'Post'`
  server default, so ORM inserts that don't set the timing (tests, scripts) keep the legacy
  behaviour.
- A PATCH that doesn't send `accrual_timing` keeps the stored value, even when the frequency
  changes. The admin UI resets the timing to the frequency's default whenever the frequency
  changes.
- On the rule card, "Rule active" moved to the end so the carry-forward and encashment rows keep
  their toggle + 2-column-input pairs.
- `MyLeave.tsx` now says "credited monthly at the start/end of each month".
