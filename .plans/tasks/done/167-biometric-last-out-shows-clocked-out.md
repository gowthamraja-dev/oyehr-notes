---
task: 167
title: Device punches — a last punch tagged OUT shows "clocked out"
status: done
depends_on: []
---

# 167 — Device punches: a last punch tagged OUT shows "clocked out"

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Paths below
are relative to `workspace-2/hrms/`.

## Why
**Background (task 136).** For device punches (`punch_source = "Biometric"`, written by both
the iclock terminals and the punch webhook), "is this employee clocked in right now?" ignores
the punch's IN/OUT tag. Instead it counts the day's kept (debounced) punches: an odd count
means in, an even count means out. That rule lives in `is_open_session` in
`backend/app/services/attendance_recompute_service.py`, around line 713.

The count exists only so the status *displays* correctly. The ZKTeco/eSSL terminals store
status 0 (= IN) unless someone presses a function key before badging, so on those machines
nearly every departure is tagged IN. See the `trust_device_direction` note in
`backend/app/modules/devices/service.py`.

**The bug.** One CDP's bi-directional machines *do* record direction reliably, and people
there often badge OUT more than once. IN 09:00 → OUT 18:00 → OUT 18:03 is 3 punches. Odd, so
the employee shows **clocked in** after they have left. The Today card keeps a running timer,
and the register shows them in the office.

**The rule (from the user).**
- **Last kept punch tagged OUT** → clocked out, however many OUTs came before it.
- **Last kept punch tagged IN, or untagged** → keep today's logic exactly as it is: the
  odd/even count, bounded to today's business date and to before the day closes.

Both kinds of machine must keep working, and this rule covers both without a setting. An
unreliable machine almost never emits OUT, because OUT needs a key press, so the count still
decides there. A per-device or per-CDP "trust direction" switch was discussed and
**deliberately deferred**. Don't add one in this task.

## The change
In the Biometric branch of `is_open_session`, replace the final
`return len(kept) % 2 == 1` with:

```python
if kept and kept[-1][0].direction == "OUT":
    return False          # an asserted OUT is real evidence — several OUTs in a row stay out
return len(kept) % 2 == 1  # IN / untagged: unchanged odd-count rule
```

- **Use the last *kept* punch, not the incoming `punch` argument.** `kept` comes from
  `_kept_punches_for_day` → `_debounce_and_direction`, the same debounced list that settlement
  uses. So an IN + OUT double-tap within `PUNCH_DEBOUNCE_SECONDS` (60s) still collapses to
  the IN and stays open.
- **Read the stored `kept[-1][0].direction`, not the tag at `kept[-1][1]`.**
  `_debounce_and_direction` fills that tag in from the count when `direction` is NULL, so
  using it would turn an untagged punch into an OUT.
- **Leave the existing bounds alone.** The checks for today's business date and
  `_day_closed` stay where they are, before this point. They can only close a session.
- **Display only.** Worked minutes still settle first punch → last punch
  (`_settle_worked_minutes`). Payroll, `attendance_status` and the register's worked hours
  don't change.
- **Trusted sources are untouched.** App, Web and Manual punches still stay open iff the last
  punch is IN.

Update the `is_open_session` docstring, which currently describes only the odd-count rule.

### Where it shows up
No code change is needed in these; they all call `is_open_session`.
- `backend/app/modules/attendance/service.py:_open_in_punch`, which drives:
  - the `/me/today` and `/employees/{id}/today` state and live timer,
  - the clock-in duplicate guard (`409 Already clocked in`),
  - the clock-out session lookup.
- `backend/app/modules/attendance/dashboard_service.py:_open_punch_map`, which drives:
  - the HR Manager register's "In office" / live worked-hours credit,
  - the `stale_open_session` exception.

### Behaviour change to call out
A **single punch today that is tagged OUT** now reads as clocked out. It used to read as
open. The existing test `test_open_session_biometric_single_arrival_today_is_open_either_direction`
in `test_attendance_recompute.py` asserts the old behaviour. Rewrite it so a lone OUT →
closed and a lone IN → open, and rename it to match.

### Accepted limitation (document it; don't fix it here)
On a reliable machine, two INs in a row more than 60s apart (IN 09:00, IN 09:05) still read
as **out** by the count. That is the "keep the same logic for IN" half of the rule. Note it in
the doc as a possible follow-up.

## Files
- `backend/app/services/attendance_recompute_service.py`: the `is_open_session` change and
  its docstring.
- `backend/app/tests/modules/test_attendance_recompute.py`: tests next to the task-136 block
  (around line 905). Reuse the `_bio(db, cdp, emp, when, direction)`, `_day_shift_employee`,
  `_ist(_D, h, m, day_offset=)` and `_D` helpers, and always pass an explicit `now`.
- `backend/app/tests/modules/test_attendance.py`: one `/me/today` test.
- `docs/leave-and-attendance/attendance/assembler.md`, §"Who counts as currently clocked in"
  (task 136, around lines 424–443): update the Biometric row of the table and the paragraph
  about the count.
- `backend/app/modules/devices/service.py`: comment only. Amend the `trust_device_direction`
  note (around line 59) to say an asserted OUT is now trusted for the clocked-in/out display.

## Acceptance criteria
- [ ] IN 09:00, OUT 18:00, OUT 18:03, today, before shift end → **closed**. This is the bug case.
- [ ] IN 09:00, OUT 13:00, IN 13:45 → **open**. Last punch is IN with an odd count, as before.
- [ ] IN 09:00, IN 15:00 → **closed**. This is the unreliable-machine case, and the count rule
      is unchanged.
- [ ] IN 09:02, OUT 09:02:20 (double-tap) → **open**. The debounced last punch is the IN.
- [ ] A lone OUT today → **closed**. A lone IN today → **open**. (The rewritten old test.)
- [ ] The other existing task-136 tests still pass unchanged:
  - yesterday's IN is closed,
  - a punch after shift end is closed,
  - a night shift is open past midnight,
  - a punch linked to a day row uses the row's date,
  - a Web IN from days ago stays open.
- [ ] `/me/today` returns `state: "clocked_out"` for an IN, OUT, OUT device day.
- [ ] Worked minutes for these days are unchanged (first punch → last punch).
- [ ] From `backend/`, `uv run pytest app/tests/modules/test_attendance_recompute.py
      app/tests/modules/test_attendance.py app/tests/modules/test_attendance_dashboard.py` is
      green. The one exception is `test_hardening_manager_scope_sweep`: its test login gets no
      `access_token`, and it already fails on `feature/gowtham_AttendanceDateRange` without this
      change.

Completed: 2026-10-05
