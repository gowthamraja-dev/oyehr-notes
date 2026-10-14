---
task: 123
title: Manager dashboard has no "in progress" bucket — a mid-shift clocked-in employee reads as YetToCheckIn
status: done
depends_on: []
---

# 123 — Manager dashboard has no "in progress" bucket — a mid-shift clocked-in employee reads as YetToCheckIn

## Scope

Split out of [115](../done/115-attendance-assembler-scheduled-sweep-job.md) — that task is the scheduled
sweep; this one is a separate, independently-shippable fix to the manager dashboard's *live*
read-time classifier. Filed from the same request: "today's attendance should show a temporary
status like InProgress while the employee is still on the clock — Present is also an acceptable
label for it, and Late should stay folded into Present, not become its own status."

**Verified: two different surfaces, two different states of correctness today.**

**Employee self-service (`/me/today`, the clock card) already gets this right — no change
needed.** `_today_snapshot` (`backend/app/modules/attendance/service.py:917-996`) returns a
`state: "not_started" | "clocked_in" | "clocked_out"` field **independent of** the nullable
`attendance_status` — so the frontend already has enough information to render "in progress" for
a currently-clocked-in employee whose worked minutes haven't yet crossed the half-day bar. The
frontend already consumes this distinction: `frontend/src/dashboards/shell.tsx` and
`frontend/src/dashboards/Employee/MyAttendance.tsx` both derive `isClockedIn = today.state ===
"clocked_in"` and drive the clock-card UI (running timer, "Clock out" button) off it. **Late is
also already correctly folded into Present, never a separate status** — `is_late`/
`late_by_minutes` (`TodayOut`) are metadata fields alongside `attendance_status`, never their own
value, both here and in the manager view (see below). No changes needed on this surface; this is
recorded here only so it isn't mistakenly "fixed" again by a future task.

**The manager dashboard (`Attendance.tsx`, `AttendanceInsightsRegister.tsx`, the underlying
`EffectiveStatus` enum) genuinely lacks this — confirmed gap.**
`backend/app/modules/attendance/schemas.py:325-337`:

```python
class EffectiveStatus(str, Enum):
    """... `Late` is deliberately absent — it's a badge (`is_late`/`late_by_minutes`) alongside
    `PRESENT`, not its own bucket."""
    on_leave = "OnLeave"
    week_off = "WeekOff"
    holiday = "Holiday"
    present = "Present"
    absent = "Absent"
    yet_to_check_in = "YetToCheckIn"
```

There is no bucket for "currently clocked in, mid-shift, hasn't yet worked enough minutes for
live credit to bump it to Present." `compute_effective_status`
(`backend/app/modules/attendance/dashboard_service.py:75-120`) only ever returns `present` once
`live_minutes >= half_day_minutes` (task 101's live-credit gate, lines 102-106) — an employee who
clocked in five minutes ago falls through every branch and lands on the same
`EffectiveStatus.yet_to_check_in` bucket as someone who hasn't shown up at all:

```python
if row.attendance_status is None and row.day_type == "Working":
    return EffectiveStatus.absent if row.attendance_date < today else EffectiveStatus.yet_to_check_in
return EffectiveStatus.yet_to_check_in
```

A manager looking at the live dashboard mid-morning cannot currently tell "clocked in, on the
clock, just hasn't hit the half-day mark yet" apart from "never checked in today" — both render
as the same "Yet to check in" pill (confirmed in the frontend:
`frontend/src/dashboards/hrManager/Attendance.tsx:71-81` and
`frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsightsRegister.tsx:55-65`
both key their status-style/label maps off exactly these six `EffectiveStatus` values, with
`YetToCheckIn` as the fallback for anything else).

**Decision (per "InProgress or Present, either is fine"): add a dedicated `in_progress` bucket**
rather than reusing `present`, because collapsing "still on the clock, not yet confirmed to have
worked enough" into the same value as "confirmed present" would make `present` counts on the
dashboard briefly inconsistent with `payable_day_fraction`/payroll's stricter, closed-interval-
only definition (`assembler.md` §6's own note on why `payroll_attendance_service.py` never needs
`is_provisionally_absent`/live-credit guards — it only ever reads settled rows). A distinct
`InProgress` bucket keeps "genuinely Present" meaning the same thing everywhere while still
giving the manager view a truthful live label instead of the misleading "Yet to check in."

## Files

### Edited

- `backend/app/modules/attendance/schemas.py`
  - Add `in_progress = "InProgress"` to `EffectiveStatus` (line ~325-337), with a docstring note
    parallel to the existing `Late` note: *"`InProgress` is a live, read-time-only bucket for a
    currently-clocked-in employee who hasn't yet reached the live-credit Present threshold —
    never written to `attendance_status`, never used by payroll."*
- `backend/app/modules/attendance/dashboard_service.py`
  - `compute_effective_status` (line 75-120): needs a way to know "does this employee currently
    have an open session for this date" independent of the `live_minutes >= half_day_minutes`
    comparison — add a `has_open_session: bool = False` parameter (or reuse/extend the existing
    `live_minutes is not None` signal, which today only fires when the employee has an open
    session *and* it's genuinely today per `_attendance_rows_for_date`'s docstring — confirm
    during implementation whether `live_minutes is not None` alone is already sufficient as the
    "currently on the clock" signal, since `_attendance_rows_for_date` already gates it to exactly
    that condition, or whether a clearer explicit boolean is worth adding for readability).
  - Add a branch: if `day_type == "Working"`, `attendance_status` isn't already one of the
    exclusive/stronger buckets (OnLeave/Holiday/WeekOff/Present/HalfDay/OnDuty/WFH/settled-Absent),
    and the employee currently has an open session for this date (per the signal above) — return
    `EffectiveStatus.in_progress` instead of falling through to `yet_to_check_in`. Order this
    check **after** the existing `live_minutes >= half_day_minutes` → `present` check (so an
    employee who has already worked enough still reads as `present`, not downgraded to
    `in_progress`), and **before** the final `yet_to_check_in` fallback.
  - `_attendance_rows_for_date` (line 226-322) already resolves everything this needs
    (`open_punch_at`, `attendance_date == _today_for_tz(tz)`, `row.day_type == "Working"`) — no
    new query should be needed, only threading the existing "has an open session for today" fact
    through to `compute_effective_status` alongside `live_minutes`/`half_day_minutes`.
- `frontend/src/dashboards/hrManager/Attendance.tsx`
  - Add `InProgress` to the `STATUS_STYLE` map (line ~71) and the status-label map (line ~81) —
    pick a style/label distinct from both `Present` and `YetToCheckIn` (e.g. "In progress", a
    third accent color) so a manager can visually tell the three states apart at a glance.
- `frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsightsRegister.tsx`
  - Same addition to its own `STATUS_STYLE`/label maps (line ~55-65) — keep the label and color
    consistent with `Attendance.tsx`'s choice above.

### Tests

- `backend/app/tests/modules/test_attendance_dashboard.py`
  - New test: an employee who clocked in a few minutes ago (open session, `live_minutes <
    half_day_minutes`) resolves to `EffectiveStatus.in_progress`, not `yet_to_check_in`.
  - New test: an employee who clocked in long enough ago that `live_minutes >= half_day_minutes`
    still resolves to `EffectiveStatus.present` (regression — the ordering above must not
    downgrade an already-live-Present employee to `in_progress`).
  - New test: an employee with no punches at all today still resolves to `yet_to_check_in`
    (regression — the new branch must not fire for someone who genuinely hasn't checked in).
  - New test: a *past* date's open session (stale, per `has_stale_open_session`) does **not**
    trigger `in_progress` for that past date's row — `in_progress` is a "today, right now" bucket
    only, matching the existing `live_minutes`/`half_day_minutes` gating's own "today" restriction.

## Acceptance criteria

- [x] `EffectiveStatus` has an `in_progress` value (`"InProgress"`).
- [x] `compute_effective_status` returns it for a currently-clocked-in employee on a Working day
      who hasn't yet reached the live-credit Present threshold — covering both the "never
      recomputed yet" path and row 12's provisional-Absent-then-reopened path — without changing
      any existing classification. Verified by 5 new tests plus the full pre-existing 61-test
      suite in `test_attendance_dashboard.py`, all passing (66 total).
- [x] Both frontend status-style/label maps (`Attendance.tsx`,
      `AttendanceInsightsRegister.tsx`) render `InProgress` distinctly from `Present` and
      `YetToCheckIn` (a third, blue accent color). `eslint` on both changed files shows only
      4 pre-existing `react-hooks/set-state-in-effect` findings, unrelated to and at different
      line numbers than these changes.
- [x] All five new backend tests pass (`test_effective_status_open_session_below_half_day_bar_is_in_progress`,
      `test_effective_status_provisional_absent_reopened_with_low_live_minutes_is_in_progress`,
      `test_effective_status_in_progress_does_not_override_present_once_half_day_crossed`,
      `test_effective_status_no_punches_and_no_open_session_stays_yet_to_check_in`,
      `test_effective_status_in_progress_never_applies_to_a_past_date`), and the full backend
      suite passes: 1148 passed, 21 failed (out of 1169). The 21 failures are the exact same
      test IDs, byte-for-byte, as task 115's already-documented pre-existing/unrelated set
      (`test_devices.py` ×2, `test_employee_import.py` ×3, `test_engagement_email.py` ×2,
      `test_geography.py` ×2, `test_leave.py` ×4, `test_organizations.py` ×5 — S3-credentials
      sandbox gap, `test_payroll.py` ×2, `test_seed_geography.py` ×1) — identical across both
      full-suite runs, confirming they're stable and unrelated to this change. Pass count rose
      by exactly 5 (1143 → 1148), matching the 5 new tests added here.
- [ ] Manually verified in the running app: not done — no running dev stack available in this
      session to click through. The backend classifier and frontend label/color are both
      verified by test and by direct code inspection; an end-to-end click-through is left for
      whoever next has the app running.

Completed: 2026-09-23
