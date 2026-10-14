---
task: 156
title: Attendance — same day shows only Present (+ Late); HalfDay/Absent settle only after the day closes; drop InProgress
status: done
depends_on: []
---

# 156 — Attendance — same day shows only Present (+ Late); HalfDay/Absent settle only after the day closes; drop InProgress

## Requirement (as given)

> On the current day the calculation should be limited to **Present**, and if they are late mark
> them as **Late**. Only once the day is over should the full calculation happen (**HalfDay**,
> **Absent**). Remove the **In progress** part.

## Why the dashboard shows three labels today

Asked about the Nano Health CDP (some employees show Present, some In progress, some Yet to check
in). There are two layers:

1. **What gets stored.** `_attendance_status` (`backend/app/services/attendance_recompute_service.py:364`)
   runs on every clock-in and clock-out. It sorts `worked_minutes` into categories straight away,
   even before the day ends: `>= full` (default 510) → `Present`; `>= half` (default 270) →
   `HalfDay`; `> 0` → `SHORT_DAY_STATUS` (`"Absent"`). Only the "a lone open IN" case is held
   back until `day_closed`, and it returns `None` meanwhile. So an employee who clocks out at 1 pm
   after 5 hours is stored as `HalfDay` at 1 pm, and one who steps out after 2 hours is stored as
   `Absent`.
2. **Read-time patches that cover up (1).**
   - `is_provisionally_absent` (same file, ~line 130) hides a same-day `Absent` on the Today card
     (`modules/attendance/service.py:1107`, `:1181`) and on the dashboard.
   - `compute_effective_status` (`modules/attendance/dashboard_service.py:81`) adds a live-credit
     rule (`live_minutes >= half_day_minutes` → `present`) and the `InProgress` bucket from task
     123 (on the clock but under the half-day bar).
   - `frontend/src/dashboards/Employee/MyAttendance.tsx:536` has its own client-side "In progress"
     rule (`attendance_status === "Present" && !last_out_at`). That rule doesn't match the
     manager dashboard.

The requirement replaces all of this with one rule, decided in one place, which is when
recompute runs.

## Target behaviour

The rule applies per employee-day on a **Working** day. Leave, holiday and week-off precedence
don't change.

| Situation | Before the day closes (`_day_closed` false) | After the day closes |
|---|---|---|
| No punches | `NULL` → **Yet to check in** | `NULL` until `AUTO_ABSENT_DAYS` lag, then `Absent` (unchanged) |
| Any punch (clocked in, or in and out, any duration) | **Present**, with `late_by_minutes` computed from `first_in_at` → **Late** badge | Full classification: `>= full` Present · `>= half` HalfDay · `> 0` Absent (`SHORT_DAY_STATUS`) · lone IN → Present + "Forgot to clock out" (unchanged) |
| Approved full-day leave / Holiday / WeekOff | unchanged | unchanged |
| Approved half-day leave + punches | **Present** | unchanged (rows 8-9: HalfDay if `>= half`, else OnLeave) |

- **"The day is over"** means the existing `_day_closed(shift_end_at, target_date, tz, now)`:
  `now >= shift_end_at` when there's a resolved shift, otherwise the next local midnight. Don't
  add a second definition. Night shifts close the next morning, the same way they do now.
- **What settles the day.** The on-demand recompute at punch time only runs while the day is
  still open, so it now always writes Present. The final HalfDay/Absent is written by
  `run_attendance_sweep` (`services/attendance_assembler_job.py`, `attendance_sweep`, cron
  `59 23 * * *` IST, `window_days=7`). It revisits every non-locked `(employee, date)` in the
  window. A day shift is therefore settled at 23:59 the same night. A night shift ending after
  23:59 is settled on the next night's run. A regularization approval after close also re-runs
  recompute and settles it. No new job is needed.
- **Late is a badge, not a status.** `is_late_row` / `late_by_minutes > 0` stays as it is.
  `_late_and_early` already computes `late_by_minutes` as soon as `first_in_at` exists, and it
  still runs because Present isn't one of its zeroing statuses. Keep `early_exit_minutes`
  computed as now. It is only meaningful after close, so don't surface an early-departure
  exception while the day is still open (see Acceptance).
- **`payable_day_fraction` is not changed.** It is still derived from `worked_minutes`, so payroll
  pays only what was actually worked, even while `attendance_status` reads Present during the
  day. Payroll only ever runs on past periods in practice. The 23:59 sweep corrects the status
  before any payroll run for that date.
- **Things to accept on purpose:**
  - During the day, an employee who clocked in for 20 minutes and left shows **Present** until
    23:59. That is the requirement.
  - The dashboard's `present_count` / `attendance_percentage` for *today* will be higher than
    before, because every punched-in employee counts.

## Scope

### Backend: `backend/app/services/attendance_recompute_service.py`
- `_attendance_status`: after the leave, holiday and week-off branches, add a guard for a
  **Working** day that is **not `day_closed`** and has `first_in_at is not None` (any punch). It
  returns `("Present", None)`. For the half-day-leave rows (8-9), return `("Present", None)` when
  the day isn't closed and there's a punch. The existing threshold branches then run only when
  `day_closed`. Keep the no-punch / auto-absent branches as they are.
- `is_provisionally_absent`: with the guard above, a stored `Absent` can only exist after close,
  so the helper is dead. Remove it and its call sites (`dashboard_service.py:124`,
  `service.py:1107`, `service.py:1181`). If any other caller turns up, keep it but document that
  it's always false for newly written rows. Rows written before this change are fixed by the
  backfill below.
- Update the module and function docstrings (the assembler.md §6 row 10-13 notes and the
  `auto_absent_elapsed` note) to describe the new "open day ⇒ Present" rule.

### Backend: `backend/app/modules/attendance/`
- `schemas.py`: remove `EffectiveStatus.in_progress` and update the enum docstring.
- `dashboard_service.py`, `compute_effective_status`:
  - Remove the `live_minutes`/`half_day_minutes` live-credit branch and the `in_progress`
    branch. The stored status is now enough: an open session always has `attendance_status =
    "Present"` after its clock-in recompute.
  - Drop the two parameters. Update callers: `_attendance_rows_for_date` /
    `_attendance_rows_for_pairs` (they build `live_minutes`/`half_day_minutes` with
    `day_thresholds`; remove that plumbing and the tuple slots, but keep
    `has_stale_open_session`), the summary at ~line 449, and anything else building
    `_AttendanceTuple`.
  - Also remove any `in_progress` handling in counts, filters, the register, the export, or
    `_STATUS_DISPLAY_LABEL` (~line 881).
  - Check the `early_departure` / `missing_clock_out` exception builders (~line 708) so they
    only flag days that have closed.
- `service.py` `_today_snapshot` (~line 1095-1130): remove the live-credit block that promotes an
  open session to Present. The stored status is already Present. Keep `state:
  "not_started" | "clocked_in" | "clocked_out"`; the clock card uses it for its own UI.
- `payroll_attendance_service.py` (~line 166) calls `compute_effective_status(row, today)`. Make
  sure it still compiles with the new signature. Its behaviour for past days doesn't change.

### Backfill for rows already written
- Existing rows for dates that haven't settled yet (today, and any open night shift) may carry a
  same-day `HalfDay`/`Absent`. They're fixed automatically on the next punch or at the 23:59
  sweep. **Past** days are already closed, so their stored status is correct under the new rule.
  No migration is needed. Confirm this reasoning holds, and if it does, don't write a backfill.

### Frontend
- `frontend/src/dashboards/hrManager/Attendance.tsx` (~lines 70, 84) and
  `frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsightsRegister.tsx`
  (~lines 54, 68): remove the `InProgress` colour and label entries. Remove any filter option
  that exists for it. Per memory, hrManager/Attendance.tsx is canonical and the admin register
  follows it, so make the same change in both.
- `frontend/src/dashboards/Employee/MyAttendance.tsx` (~lines 534-556): remove `isInProgress`
  and its "In progress" pill. An open-session row now renders as Present, plus the Late badge
  when `late_by_minutes > 0`. Worked hours keep showing "Incomplete" (`format_worked_hours` /
  its frontend equivalent) while `last_out_at` is null.
- `frontend/src/lib/api.ts`: remove `"InProgress"` from any status union type.

### Docs
- `docs/leave-and-attendance/attendance/assembler.md` (§6 rows 10-13, §5.6) and
  `docs/leave-and-attendance/attendance/gaps.md`: describe "open Working day with a punch ⇒
  Present; HalfDay/Absent only after `_day_closed`", remove InProgress and provisional-Absent,
  and link this task.

### Not in scope
- The sweep schedule (task 133, `59 23 * * *`, 7-day window). This task relies on it and doesn't
  change it.
- Leave, holiday, week-off, WFH or OnDuty precedence. Lock / regularization-window logic.
- Thresholds (`min_full_day_minutes` / `min_half_day_minutes` / defaults 510/270).
- `payable_day_fraction`.

## Files
- `workspace-2/hrms/backend/app/services/attendance_recompute_service.py`
- `workspace-2/hrms/backend/app/modules/attendance/schemas.py`
- `workspace-2/hrms/backend/app/modules/attendance/dashboard_service.py`
- `workspace-2/hrms/backend/app/modules/attendance/service.py`
- `workspace-2/hrms/backend/app/services/payroll_attendance_service.py` (signature follow-through only)
- `workspace-2/hrms/backend/app/tests/modules/test_attendance.py`
- `workspace-2/hrms/backend/app/tests/modules/test_attendance_dashboard.py`
- `workspace-2/hrms/backend/app/tests/modules/test_attendance_recompute*.py` / sweep tests (whichever cover `_attendance_status` and the sweep)
- `workspace-2/hrms/frontend/src/dashboards/hrManager/Attendance.tsx`
- `workspace-2/hrms/frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsightsRegister.tsx`
- `workspace-2/hrms/frontend/src/dashboards/Employee/MyAttendance.tsx`
- `workspace-2/hrms/frontend/src/lib/api.ts`
- `workspace-2/hrms/docs/leave-and-attendance/attendance/assembler.md`, `gaps.md`

## Acceptance criteria
- [x] Same day, clocked in and still open: stored `attendance_status = "Present"`; dashboard
      status `Present`; `is_late` true when `first_in_at` is past shift start + grace.
- [x] Same day, clocked in and out for 2 h (under half): stored `Present`, **not** `Absent`;
      Today card, `/me/daily`, manager dashboard and register all show Present.
- [x] Same day, clocked in and out for 5 h (between half and full): stored `Present`, **not**
      `HalfDay`.
- [x] Same day, no punches: `YetToCheckIn` (unchanged).
- [x] After `_day_closed` (freeze `now` past `shift_end_at`, then recompute or run
      `run_attendance_sweep`): 2 h → `Absent`, 5 h → `HalfDay`, 9 h → `Present`, lone IN →
      `Present` + remark "Forgot to clock out". This is the existing classification, unchanged.
- [x] Night shift (e.g. 22:00-06:00): at the 23:59 tick on the start date the row stays
      `Present`. After `shift_end_at` the next sweep settles it.
- [x] Half-day approved leave + punches: `Present` while open; rows 8-9 result after close.
- [x] `payable_day_fraction` for a 2 h same-day row stays `0.00` (payroll not inflated).
- [x] `EffectiveStatus.in_progress` / `"InProgress"` no longer appears anywhere in
      `backend/app` or `frontend/src` (`grep -rn "InProgress\|in_progress"` finds nothing
      attendance-related). `is_provisionally_absent` is removed, or documented as always false.
- [x] No early-departure / missing-clock-out exception is raised for a day that hasn't closed.
- [x] Existing task-101/123 tests that asserted `InProgress` or live-credit promotion are
      rewritten to the new rule, not deleted without replacement. CDP-scoping tests still pass.
- [x] `uv run pytest` green (from `workspace-2/hrms/backend/`); frontend `npm run build` and lint
      clean.
- [ ] Manual smoke test on the Nano Health CDP: HR Manager → Attendance for today shows only
      Present (with Late badges) / Yet to check in / leave, holiday and week-off buckets. No In
      progress.
- [x] Docs updated (assembler.md, gaps.md).

## Progress (29-Sep-26)
Built on `feature/gowtham_AttendanceDateRange` in `workspace-2/hrms/` (on top of tasks 150-154).

- `attendance_recompute_service.py`: `_attendance_status` returns `("Present", None)` for any
  punch on a Working day that hasn't closed. This comes after the full-day-leave / Holiday /
  WeekOff branches and before rows 8-13, and the old "lone IN on an open day → NULL" branch is
  gone. `is_provisionally_absent` is removed. A new
  `is_row_day_closed(row, tz, now)` wraps `_day_closed` from the row's own `shift_end_at` (for the
  exceptions). The docstrings for `day_thresholds` / `live_worked_minutes` were updated
  (display-only now).
- `schemas.py`: `EffectiveStatus.in_progress` removed.
- `dashboard_service.py`: `compute_effective_status(row, today)` uses only the stored status (no
  live credit, no InProgress; a stored Absent is final). `_AttendanceTuple` is now
  `(row, tz, has_stale_open_session)`, with the `live_minutes` / `half_day_minutes` plumbing and
  `_ScopedRow` fields dropped. Day types are resolved only for synthesized rows. `missing_clock_out`
  and `early_departure` exceptions require `is_row_day_closed`.
- `service.py`: `_today_snapshot` and `_daily_log_row` show the stored status as-is (the
  live-credit block and provisional suppression are gone; `state` is unchanged).
  `payroll_attendance_service.py` already called `compute_effective_status(row, today)`, so no
  change was needed.
- Frontend: `hrManager/Attendance.tsx` drops the `InProgress` style and label (there was no filter
  option for it). `Employee/MyAttendance.tsx` drops `isInProgress` and its pill. `api.ts` had no
  InProgress union. `AttendanceInsightsRegister.tsx` no longer exists (task 154), and admin uses
  the manager component. `EmployeeHome.tsx`'s "In progress" is a helpdesk/reimbursement request
  status, so it was left alone.
- Backfill: none, as the task reasoned. A past day's row was last written after close by the
  sweep, which gives the same answer as the new rule. An unsettled same-day row is rewritten by
  its next punch or the next sweep. Payroll pays from `payable_day_fraction`, which still
  follows worked minutes.
- Docs: `assembler.md` §5.6 table row, §6 new row **7a** + a replacement paragraph for the
  provisional-Absent / live-credit sections, and the task-136 note; `gaps.md` Addendum B note;
  `api-and-pages.md` exceptions (`missing_clock_out` / `early_departure` only after close).
- Tests: 15 old tests rewritten to the new rule, not deleted.
  `test_attendance_dashboard.py` has 8 classifier tests (stored Absent final, open-day Present,
  WeekOff precedence, past NULL → Absent, no InProgress member), the short-stint analytics test
  end-to-end through `recompute_attendance_day`, the exception-counts test's missing-OUT row
  given a past `shift_end_at`, and a new open-day no-exceptions test.
  `test_attendance.py` has 3 Today-card tests through the real clock-in/out API.
  `test_attendance_recompute.py` has 2 lone-IN tests plus 10 new frozen-`now` tests: 2 h / 5 h / 9 h
  30 before/after close with Late 20, payable 0.00, lone IN → "Forgot to clock out" after close,
  no punches → NULL, the sweep settling an open day, a night shift Present at 23:59 → Absent
  next morning, and half-day leave → HalfDay / OnLeave after close.
- Results: 527 passed across attendance / recompute / assembler / calendar batch / authz / shifts /
  devices / payroll. The 2 failures left (`test_devices.py::test_reported_name_reaches_the_unresolved_reason_on_a_punch`,
  `test_payroll_calculation.py::test_employer_contribution_excluded_from_net_pay`) fail the
  same way on the committed code without these changes, so they aren't caused by this task.
  ruff shows no new problems. Frontend `npx tsc --noEmit` is clean, `npm run build` succeeds, and
  eslint shows no new problems.

### Follow-up (29-Sep-26): same-day HalfDay/Absent still visible
The user still saw Absent/HalfDay for today. A read-only query showed that on the NanoCare CDP
(18761) all 11 of today's rows were punched with the shift still open, yet 4 were stored
`Absent`, 4 `HalfDay` and 3 `NULL`. The HalfDay rows were assembled 16:03–16:28, after the change,
so another process still on the pre-156 rule is writing to the shared dev DB (the deployed dev
backend / the `hrms/` checkout's Docker API). This branch's writer can't stop that, so the
read side now applies the rule too:
- `attendance_recompute_service.display_attendance_status(row, tz, now)`: returns Present for a
  Working day with `first_in_at` set, stored `NULL`/`HalfDay`/`Absent`, and not
  `is_row_day_closed`; otherwise it returns the stored value (leave/holiday/week-off/WFH/OnDuty
  are never overridden).
- It is used by `compute_effective_status(row, today, tz)` (the dashboard KPIs / register /
  exceptions / export and My-attendance-this-month), the register's `is_half_day` badge,
  `_today_snapshot` and `_daily_log_row`. Late is untouched (`late_by_minutes` badge). The
  regularization before/after previews and the audit values still record the stored value.
- Checked read-only against the real rows: all 11 display as Present, and all 11 keep Late.
- Tests: the stored-Absent test is now parametrized over Absent/HalfDay/NULL on an open day →
  present. There are new tests for a closed day showing the settled status and leave not being
  overridden, plus a register end-to-end test (old-writer HalfDay → Present + Late, no Half-day
  badge) and a Today card / daily log end-to-end test (old-writer Absent → Present). Attendance
  suites: 305 passed.
- `assembler.md` §6 paragraph updated.

**Still open:** the manual smoke test on the Nano Health CDP (needs a login). The stored values
from the old-rule writer stay in the DB until the next recompute after close. Deploying this
branch everywhere that writes to the DB stops new ones being written.

Completed: 2026-09-29 — browser/manual checks verified by the user.
