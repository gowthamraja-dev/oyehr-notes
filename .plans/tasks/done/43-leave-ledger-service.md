---
task: 43
title: Ledger primitives and the leave day-row builder
status: done
depends_on: [42]
---

# 43 — Ledger primitives and the leave day-row builder

## Discussion

Two pieces of shared machinery that [[44-leave-employee-apply-cancel-api]] and
[[45-leave-manager-approval-api]] both need, built once so neither module re-derives them —
per `docs/leave-and-attendance/README.md` §3.4's hard requirement that leave and attendance
never diverge on calendar resolution, and `ledger.md` §5's concurrency mandate. No routes here —
this task is pure service-layer functions plus their tests.

### 1. `app/services/ledger_service.py` — new shared file

Per `docs/leave-and-attendance/shared/implementation-structure.md` §4, this lives in
`app/services/` (not `leave/service.py`) because the future accrual/rollover jobs will also
call it — a `services/`-worthy file per CLAUDE.md's own convention for cross-module code.

```python
def write_ledger_entry(
    db: Session, tenant_id: int, employee_id: int, leave_type_id: int, leave_year: int,
    txn_type: str, quantity: Decimal, effective_date: date,
    leave_request_detail_id: int | None = None, reversal_of_id: int | None = None,
    remarks: str | None = None, created_by_id: int | None = None,
) -> EmployeeLeaveBalanceLedger:
    """Takes the advisory lock as its first statement, reads the latest balance_after for
    (tenant, employee, leave_type, leave_year) ordered by id DESC, inserts one new row with
    balance_after = that + quantity. Caller commits — this only flushes, matching
    recompute_attendance_day's convention of composing into a larger transaction."""

def get_balance(
    db: Session, tenant_id: int, employee_id: int, leave_type_id: int, leave_year: int,
) -> Decimal:
    """balance_after of the newest row by id, or 0 if none exists. Must be called only inside
    the same locked transaction as any decision that depends on it — ledger.md §5.2's rule:
    'never read balance_after for an authorization decision outside the lock.'"""

def get_available_balance(
    db: Session, tenant_id: int, employee_id: int, leave_type_id: int, leave_year: int,
) -> tuple[Decimal, Decimal, Decimal]:
    """Returns (ledger_balance, pending_committed, available_balance).
    pending_committed = Σ total_days of this employee's Pending, non-archived
    leave_request_details for this leave_type whose day rows fall in this leave_year
    (ledger.md §1.2). available_balance = ledger_balance - pending_committed."""
```

The advisory lock itself:

```python
def _lock_ledger(db: Session, tenant_id: int, employee_id: int, leave_type_id: int, leave_year: int) -> None:
    db.execute(text(
        "SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"
    ), {"key": f"{tenant_id}:{employee_id}:{leave_type_id}:{leave_year}"})
```

Called as the first statement inside `write_ledger_entry` (and by
[[44-leave-employee-apply-cancel-api]]'s apply-time balance gate, and
[[45-leave-manager-approval-api]]'s approve gate, before they read `get_available_balance`).
**Do not** implement the rejected `SELECT … FOR UPDATE` alternative — `ledger.md` §5.2 explains
why it fails for a series' first row.

`updated_at`/`is_active` hygiene from `domain-model.md` §5.5 (`is_active` always `true`,
`updated_at` always equals `created_at`, never touched again): don't set either explicitly
beyond what the model's `server_default`s already do — no code path in this file should ever
`UPDATE` a ledger row. Cover with a test that re-reads a row after an unrelated later write and
asserts both are unchanged.

### 2. Day-row builder — extend `calendar_resolver_service.py`, add to `leave/service.py`

**Reuse `resolve_day_type` — do not reimplement week-off/holiday matching a third time.**
`app/services/calendar_resolver_service.py::resolve_day_type(db, tenant_id, employee_id,
target_date, resolved_shift)` already returns a `DayTypeResolution` with `day_type` (`Working|
WeekOff|Holiday`) for exactly this purpose, consumed today by
`attendance_recompute_service.recompute_attendance_day`. The leave day-row builder must call
the *same* function, not a leave-specific reimplementation — this is the literal mechanism
`README.md` §3.4 requires to keep `total_days` and `payable_day_fraction` from disagreeing.

Add to `backend/app/modules/leave/service.py`:

```python
@dataclass
class LeaveDayRow:
    leave_date: date
    day_fraction: Decimal
    is_week_off: bool
    is_holiday: bool

def build_leave_day_rows(
    db: Session, tenant_id: int, employee_id: int,
    leave_type: LeaveTypeMaster, from_date: date, to_date: date,
    from_half: str | None, to_half: str | None,
) -> list[LeaveDayRow]:
```

Implements `ledger.md` §2 exactly: for every calendar date in `[from_date, to_date]` inclusive
(including zero-fraction days — do not skip any), resolve `is_week_off`/`is_holiday` via
`resolve_effective_shift` + `resolve_day_type`, then apply the day-fraction table (§2 step 3:
week-off/holiday exclusion per the leave type's `exclude_week_offs`/`exclude_holidays`, then the
half-day rules keyed on `from_half`/`to_half`, first match wins, default `1.00`). Reject
(raise, caller converts to `422`) if a half-day is requested but `leave_type.allow_half_day` is
false.

Also add the apply-time gate functions from `ledger.md` §6 as small, individually testable
functions (tenancy, type-in-force, gender, probation, date sanity, notice, max-consecutive-run,
overlap, balance, document, approver-resolution) — implemented here as pure validation
functions returning either nothing or raising `HTTPException(422, ...)`, **not yet wired to any
route** (that's [[44-leave-employee-apply-cancel-api]]/[[45-leave-manager-approval-api]]'s job).
Building them here, once, means both the apply and re-validate-at-approve call sites
([[44]], [[45]]) call the identical functions rather than two copies drifting apart — the same
argument `README.md` §3.4 makes for the calendar resolver, applied to the validation gates too.

**Max-consecutive-days gate (§6 row 7):** the longest run of consecutive calendar dates with
`day_fraction > 0`, not the raw `to_date - from_date`. An excluded week-off in the middle must
not break the run, or the rule is trivially bypassable — implement by walking the day rows
computed above, not by re-deriving dates independently.

**leave_year** — implement per `ledger.md` §3 as its own small function
(`resolve_leave_year(policy, target_date, tenant_default_month) -> int`), precedence
`leave_policy_details.reset_month → 4` (the CDP knob doesn't exist yet — `tenant_params.py` per
`shared/tenant-config-storage.md` isn't built; hardcode `4` as the ultimate fallback and leave a
comment pointing at that doc for when it is).

## Files

- `backend/app/services/ledger_service.py` — new
- `backend/app/modules/leave/service.py` — extended: `build_leave_day_rows`, the apply-time gate
  functions, `resolve_leave_year`
- `backend/app/tests/modules/test_leave.py` — extended (see below)

## Tests

- Day-row builder: a 5-day range spanning one holiday and one week-off (both excluded by
  default) produces 5 rows, 3 with `day_fraction=1.00` and 2 with `0.00`, `is_holiday`/
  `is_week_off` flags set correctly on the zero-fraction rows.
- Same range with `exclude_holidays=false` on the leave type: the holiday row gets
  `day_fraction=1.00`.
- Single-day request with `from_half='FirstHalf'` (no `to_half`) on a type with
  `allow_half_day=true` → one row, `day_fraction=0.50`. Same request on a type with
  `allow_half_day=false` → rejected.
- Max-consecutive-days: a request whose raw span exceeds `max_consecutive_days` but whose
  actual worked-day run (excluding a sandwiched week-off) does not, is **not** rejected; a
  request whose run of `day_fraction > 0` days genuinely exceeds it **is** rejected.
- `write_ledger_entry`/`get_balance`: three sequential writes produce the correct running
  `balance_after`; `is_active` is always `true`, `updated_at == created_at`, on every row.
- `get_available_balance`: a `Pending` request for the same employee/type/year is reflected in
  `pending_committed` and subtracted from `available_balance`, but not from `ledger_balance`.
- Concurrency: two threads/sessions calling `write_ledger_entry` for the same
  `(tenant, employee, type, year)` concurrently produce a correct, non-clobbered final
  `balance_after` (the advisory-lock proof — this is the test
  `docs/leave-and-attendance/leave/api-and-pages.md` §7 calls out by name; a real must-have, not
  optional).

## Acceptance criteria

- [x] `build_leave_day_rows` calls `calendar_resolver_service.resolve_day_type` — no second
      week-off/holiday matcher exists anywhere in `leave/service.py`.
- [x] `write_ledger_entry` takes the advisory lock as its first statement; no code path anywhere
      in `ledger_service.py` executes an `UPDATE` against `employee_leave_balance_ledgers`.
- [x] `get_available_balance`'s formula matches `ledger.md` §1.2 exactly.
- [x] All tests above pass; `uv run pytest app/tests/modules/test_leave.py -v` is green (77/78 —
      the one pre-existing failure, `test_audit_written_on_success_and_not_on_rejection`, fails
      identically with this task's changes stashed out entirely; it's stray committed data in
      the shared dev DB, unrelated to this task). Full `app/tests/` suite also run: only that
      same test plus two pre-existing, unrelated `test_engagement_email.py` failures (confirmed
      via the same stash check) — no regressions from this task's changes.

Completed: 2026-08-18
