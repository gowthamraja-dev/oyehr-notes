---
task: 102
title: Attendance — premature "Absent" mid-shift, and no live credit for an open second session
status: done
depends_on: []
---

# 102 — Attendance — premature "Absent" mid-shift, and no live credit for an open second session

## Scope

Two related bugs reported against `employee_attendance_details`/the attendance dashboards,
found while investigating one user report end-to-end.

### Part A — premature "Absent" before the shift ends

**Bug**: clock in, clock out mid-shift with a short interval → the day is immediately marked
`Absent`, hours before the shift is scheduled to end and even if the employee intends to clock
back in.

**Root cause**: `attendance_recompute_service._attendance_status` row 12 (`0 < worked_minutes <
min_half_day_minutes` → `short_day_status`, default `Absent`) has no `day_closed` gate, unlike
row 13 (dangling IN). This matches `docs/leave-and-attendance/attendance/assembler.md` §6's
table literally — the written spec has no gate here either — but the eagerness exists only
because there's no batch job to ever revisit the day otherwise (see
`attendance_recompute_service`'s own module docstring). Per the user's explicit choice
(cosmetic-only, not touching the engine/DB value): every **display** surface must suppress a
stored `Absent` read before the shift's own `shift_end_at` — applies whether the employee is
currently clocked in or clocked out, since recompute reruns on every clock-in/out event.

### Part B — no live credit for a currently-open second session

**Bug** (follow-up from the same investigation): clock in late, clock out short (tripping Part
A), clock in again — the second (open) session's elapsed time is never reflected in
`attendance_status`, so the day stays stuck at pending/Absent-suppressed on the manager
KPI/register ("present count... only in late it is showing and half-day too") no matter how
long the employee has genuinely been working, until they clock out again.

**Root cause**: `worked_minutes` only ever counts *closed* intervals (§5.5) — by design, since
the stored value is payroll truth. But a live dashboard/Today card showing "who's present now"
shouldn't have to wait for the next clock-out. Per the user's explicit choice: credit the
elapsed time of a currently-open session for **display only** (never written back), and bump
the shown status to Present once the live total crosses the half-day bar.

**Out of scope for both parts**: the recompute engine itself, `EmployeeAttendanceDetail`
storage, payroll (`payroll_attendance_service.py` — must never be inflated by an in-progress
session), and per-period analytics (`get_employee_analytics`/`get_my_analytics` — same "actual
closed time only" requirement as payroll). The regularization-request detail snapshot
(`_attendance_snapshot`) and audit-log entries are also deliberately left showing the raw
stored value — a manager reviewing a correction needs the real state, not a smoothed one.

## Files

### Edited

- `backend/app/services/attendance_recompute_service.py`
  - Added `is_provisionally_absent(row, now=None) -> bool` — true iff `row.attendance_status ==
    "Absent"` and `row.shift_end_at` (or the no-shift midnight fallback via `DEFAULT_TIME_ZONE`,
    reusing `_day_closed`) hasn't passed yet.
  - Renamed `_day_thresholds` → `day_thresholds` (public — now used cross-module) and updated
    its two internal call sites (`_attendance_status`, `_payable_day_fraction`).
  - Added `live_worked_minutes(stored_minutes, open_since, now=None) -> int` — stored
    `worked_minutes` plus the elapsed time of an open session, display-only.
- `backend/app/modules/attendance/service.py`
  - `_today_snapshot`: suppress a provisional `Absent` to `None`; when currently clocked in
    (`open_punch is not None`) and not already in an exclusive bucket, resolve
    `day_type`/`is_half_day_week_off` live, compute `live_worked_minutes`, and bump to
    `"Present"` once it crosses `day_thresholds`' half-day value.
  - `_daily_log_row`: same provisional-Absent suppression (no live-credit here — out of scope,
    see Discussion below).
- `backend/app/modules/attendance/dashboard_service.py`
  - `compute_effective_status`: added optional `live_minutes`/`half_day_minutes` params
    (default `None` — original stored-only behavior unchanged, which is what
    `payroll_attendance_service.py` relies on); added the provisional-Absent →
    `yet_to_check_in` guard; added the live-credit → `present` bump when both params are given
    and `row.day_type == "Working"`.
  - Added `_open_punch_map(db, employee_ids)` — one batched `DISTINCT ON` query returning each
    employee's currently-open IN punch's `punch_at`, if any.
  - `_attendance_rows_for_date`: now returns `(row, tz, live_minutes, half_day_minutes)` tuples
    — the last two are `None` unless the employee has an open session *and*
    `attendance_date == _today_for_tz(tz)` (never for a historical date query).
  - `_ScopedRow`: added `live_minutes`/`half_day_minutes` fields; `_build_scoped_rows` and
    `_register_row_out` thread them through to `compute_effective_status` — this is the single
    choke point shared by register/exceptions/export (task 71's own design), so all three pick
    up the fix together.
  - `get_manager_analytics` (KPI summary): same threading.
- `docs/leave-and-attendance/attendance/assembler.md` — documented both the row-12
  provisional-value gotcha (with the guard every new endpoint must use) and the live-credit
  helpers, so a future endpoint doesn't reintroduce either bug by reading `attendance_status`/
  `worked_minutes` raw.

### Tests

- `backend/app/tests/modules/test_attendance.py`: `test_today_suppresses_absent_before_shift_ends`,
  `test_today_still_suppresses_absent_while_clocked_in_again`,
  `test_today_credits_open_session_toward_present`, `test_today_shows_absent_once_shift_has_ended`
  (regression guard — the suppression is time-bound, not permanent).
- `backend/app/tests/modules/test_attendance_dashboard.py`:
  `test_effective_status_absent_before_shift_end_is_still_provisional`,
  `test_effective_status_absent_after_shift_end_is_final`,
  `test_effective_status_live_minutes_crossing_half_day_bar_is_present`,
  `test_effective_status_live_minutes_below_half_day_bar_stays_absent`,
  `test_effective_status_live_minutes_ignored_on_non_working_day`,
  `test_analytics_credits_open_session_toward_present` (end-to-end via the KPI endpoint).

## Discussion

- **Why the daily log (`_daily_log_row`) gets Part A but not Part B**: live-credit needs the
  actual open punch's start time, which `_daily_log_row` doesn't currently fetch per row (it
  iterates a date range, not "today" specifically). The user's report was about the manager
  KPI/register count, which this task does fix end-to-end; the employee's own historical daily
  log list still only gets the (already-correct) provisional-Absent suppression. A future task
  can extend live-credit there if it's actually wanted.
- **Why `worked_hours_display`/`worked_minutes` on the register row aren't live-credited too**:
  same reasoning — the user's ask was specifically about the status/count bucketing, not the
  hours display. `format_worked_hours` still shows the stale (pre-second-session) duration for
  a currently-open row; fixing that would need the same plumbing but wasn't the reported
  symptom.
- **Two pre-existing, unrelated task-86-era bugs were confirmed still present** and not touched
  by this task (out of scope): `test_analytics_yesterday_never_punched_counts_absent` fails
  whenever "yesterday" lands on a week-off day (date/weekday-dependent flake) — reproduces
  identically with this task's changes stashed out.

## Acceptance criteria

- [x] A short clock-in/clock-out mid-shift no longer surfaces as `Absent` on `/me/today`,
      `/me/daily`, or the manager KPI/register/exceptions/export before the shift's own
      `shift_end_at` has passed — regardless of whether the employee is currently clocked in or
      clocked out.
- [x] The suppression is time-bound: once the shift has genuinely ended, a real short day still
      resolves to `Absent` normally (not permanently hidden).
- [x] A currently-clocked-in employee whose live total (closed intervals + the open session's
      elapsed time) crosses the half-day bar shows `Present` on `/me/today` and counts toward
      `present_count` on the manager KPI summary — without waiting for the next clock-out.
- [x] `payroll_attendance_service.py` and per-period analytics
      (`get_employee_analytics`/`get_my_analytics`) are provably unaffected: they call
      `compute_effective_status` without the new optional params, which default to the
      original stored-only behavior exactly.
- [x] Full attendance test suite passes: `uv run pytest app/tests/modules/test_attendance.py
      app/tests/modules/test_attendance_dashboard.py` → 142 passed, 1 failed (the pre-existing
      `test_analytics_yesterday_never_punched_counts_absent` weekday flake, confirmed identical
      with this task's changes stashed out).

Completed: 2026-09-07
