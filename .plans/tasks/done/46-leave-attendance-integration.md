---
task: 46
title: Approved leave suppresses Absent/missing-punch and sets attendance_status = OnLeave
status: done
depends_on: [45]
---

# 46 — Approved leave suppresses Absent/missing-punch and sets attendance_status = OnLeave

## Discussion

The attendance side of the integration is **already fully specified and deliberately stubbed
out**, not merely undocumented. Two docstrings in
`backend/app/services/attendance_recompute_service.py` say so explicitly:

- `_attendance_status` (line ~197): *"restricted to the rows this task set can actually reach
  ... no auto-absent job exists to ever produce row 14's Absent"* — the leave rows (1, 8, 9) of
  `docs/leave-and-attendance/attendance/assembler.md` §6's derivation table are simply absent
  from the current `if`/`elif` chain.
- `_payable_day_fraction` (line ~226): *"assembler.md §9 with the leave_fraction term omitted
  (always 0 — no leave module)."*

This task fills exactly those two gaps, using the request/day-row/ledger machinery
[[42]]–[[45]] just built. **`day_type` itself does not change** — leave never turns a `Working`
day into something else at the `day_type` level; only `attendance_status` and
`payable_day_fraction` become leave-aware. Re-read `assembler.md` §6 (the full derivation
table) and §9 (the payable-fraction formula with the `leave_fraction` term) before writing this
— both are already written to spec; this task implements them, it doesn't design them.

### 1. `calendar_resolver_service.py` — add an approved-leave lookup

```python
def resolve_approved_leave(
    db: Session, tenant_id: int, employee_id: int, target_date: date,
) -> ApprovedLeaveResolution | None:
    """Joins leave_request_day_details -> leave_request_details where status='Approved',
    not archived, leave_date = target_date, for this employee/tenant. Returns None if no
    approved leave covers the date. Returns the day_fraction, is_paid (from leave_type_masters),
    and from_half/to_half context needed for assembler.md §7.1's half-day comparison-point shift.
    """
```

New dataclass `ApprovedLeaveResolution` (day_fraction, is_paid, half_period: str | None) next to
`DayTypeResolution` in the same file. This is the second consumer `README.md` §3.4 already
anticipated for the shared calendar resolver — keep it in this file, not duplicated into
`leave/service.py`'s own module (leave's day-row *builder*, [[43]], computes rows for a request
under construction and has no need to query already-approved rows back; this is the reverse
direction, attendance asking "is there approved leave on this date," and belongs where
`resolve_day_type` already lives).

### 2. `_attendance_status` — add rows 1, 8, 9 from `assembler.md` §6

First-match-wins table, so the new checks must slot in at the *correct* position relative to the
existing Holiday/WeekOff checks — re-read the table's literal row order (approved full-day leave
checked **before** the Holiday/WeekOff worked-minutes checks) rather than assuming the plan's
simplified "Holiday → Leave → Punch" ordering from a generic planning doc; the row order in
`assembler.md` §6 is the authoritative source for this codebase, and it interacts correctly with
`exclude_holidays`/`exclude_week_offs` because a leave day sandwiched on top of an excluded
holiday/week-off already carries `day_fraction=0.00` in `leave_request_day_details`, so it falls
through to the existing Holiday/WeekOff rows naturally — the ordering is not a conflict, it's
already resolved by the day-fraction being zero on those dates.

```
row 1: approved leave covering D with day_fraction == 1.00           -> ("OnLeave", None)
row 8: approved half-day leave AND worked_minutes >= min_half_day_minutes -> ("HalfDay", None)
row 9: approved half-day leave AND insufficient work                  -> ("OnLeave", None)
```

Signature grows one parameter: `resolve_approved_leave(...)`'s result, passed in from
`recompute_attendance_day` (which already resolves `resolved_shift`/`day_type_resolution` at the
top of the function — add the leave lookup alongside those, before calling `_attendance_status`).

### 3. `_payable_day_fraction` — add the `leave_fraction` term from `assembler.md` §9

```
leave_fraction = Σ day_fraction of approved leave days on D, counting only leave types with
                 is_paid = true   # LOP contributes 0 to payable, though it still shows OnLeave
```

Remove the docstring's "omitted — no leave module" caveat once implemented; replace with a
comment citing `assembler.md` §9 directly, matching this codebase's convention of citing the doc
section a formula was lifted from (see `_attendance_status`'s own docstring style).

### 4. Half-day leave shifts the late/early comparison point (`assembler.md` §7.1)

`effective_start`/`effective_end` in the late/early-exit calculation move to the shift midpoint
when the day has an approved `FirstHalf`/`SecondHalf` leave. Locate where `late_by_minutes`/
`early_exit_minutes` are computed in `attendance_recompute_service.py` (search for
`late_by_minutes` — likely near `_late_and_early`) and thread the half-day leave context through
from the same lookup added in step 1.

### 5. Wire `recompute_attendance_day` to run when a leave request is approved

[[45-leave-manager-approval-api]]'s approve endpoint already calls
`recompute_attendance_day` for each affected date (see that task's step 6) — confirm it does, or
add the call here if [[45]] shipped first without it. Also handle **cancellation**: when
[[44-leave-employee-apply-cancel-api]]'s cancel path writes a `Reversal` for previously-approved
leave, the affected future dates must be recomputed too, or a cancelled leave day keeps showing
`OnLeave` after the fact.

### A punch on an approved leave date is preserved, never deleted

Per the generic plan's §19 and this codebase's existing house rule for `attendance_punch_details`
(append-only, `archive=true` to void, never DELETE): nothing in this task deletes a punch. If an
employee clocks in on an approved leave date, `worked_minutes > 0` and row 1's condition
(`day_fraction == 1.00`, full-day leave) still applies — `attendance_status` stays `OnLeave`
while the punch itself remains in `attendance_punch_details`, visible to a manager reviewing the
day, exactly like the existing Holiday/WeekOff-with-a-punch handling already does (§6.1's "what
wins if someone punches in on a holiday" reasoning applies identically here — the punch is
recorded, the leave decision is not silently overridden by it).

## Files

- `backend/app/services/calendar_resolver_service.py` — add `resolve_approved_leave` +
  `ApprovedLeaveResolution`
- `backend/app/services/attendance_recompute_service.py` — extend `_attendance_status`,
  `_payable_day_fraction`, the late/early-exit calculation; thread the new lookup through
  `recompute_attendance_day`
- `backend/app/tests/modules/test_attendance_recompute.py` — extended
- `backend/app/tests/modules/test_leave.py` — extended (approve → attendance side-effect)

## Tests

- Full-day approved leave on a `Working` day with no punches → `attendance_status="OnLeave"`,
  `payable_day_fraction=1.00` (paid type) or `0.00` (LOP), never `Absent`, never the missing-
  punch remark.
- Same, but the employee also punched in that day → punch preserved in
  `attendance_punch_details` (not deleted, not archived), `attendance_status` still `OnLeave`.
- Half-day `FirstHalf` leave + sufficient afternoon work → `HalfDay`, not `OnLeave`; same leave +
  insufficient work → `OnLeave`.
- LOP (`is_paid=false`) full-day leave → `attendance_status="OnLeave"` but
  `payable_day_fraction=0.00`.
- Approved leave on a day that is *also* an excluded holiday (leave's own day-fraction is 0.00
  for that date) → falls through to the existing Holiday row, `attendance_status="Holiday"`, not
  `OnLeave` — proves the two systems don't double-count or conflict.
- Cancelling a previously-approved future leave date and re-running recompute for that date
  clears `OnLeave` back to whatever the day resolves to without it (e.g. `Absent`/`NULL`/
  `Present` depending on punches).
- Half-day leave's late/early-exit comparison point shift, per §7.1, verified with a punch just
  after the shift midpoint on a `SecondHalf`-leave day.

## Acceptance criteria

- [ ] `assembler.md` §6 rows 1, 8, 9 and §9's `leave_fraction` term are both implemented exactly
      as specified — no divergence between the two docs' formulas and this code.
- [ ] Approved leave never produces `Absent` or a missing-punch remark for the covered dates.
- [ ] No punch is ever deleted or silently discarded because a leave request covers its date.
- [ ] Cancelling approved leave correctly reverts the attendance rows for the affected future
      dates.
- [ ] `_payable_day_fraction`'s docstring no longer claims leave is omitted.

Completed: 2026-08-18
