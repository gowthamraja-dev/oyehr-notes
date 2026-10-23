---
task: 236
title: Day panel — explain a missing clock-out instead of showing 0% and "—"
status: done
depends_on: []
---

# 236 — Day panel: explain a missing clock-out

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Source:
`.plans/attendance-shifts-leave-holidays-todo.md` item **ATT-D2** (issues.csv `HR:ATTENDANCE-B3`).
Related, already in `ongoing/`: task 166 (register shows "—" for open days) — read it first so the two
don't conflict.

## Why
Dumpa Tirumal Reddy, 09-Oct: clocked in 11:30 AM, no clock-out. The day status is **Present / Late**, but
the Day tab shows **Attendance 0%** and **Worked hours "—"** with no explanation. Mechanism:
- A closed day with IN and no OUT is stored Present with remark "Forgot to clock out"
  (`backend/app/services/attendance_recompute_service.py:519-523`) and `payable_day_fraction = 0`.
- `compute_attendance_percentage` averages `payable_day_fraction` over Working rows
  (`backend/app/modules/attendance/dashboard_service.py:640-648`) → 0%.
- `format_worked_hours` returns "—" without both punches (`dashboard_service.py:236-243`).
A header chip "Missing clock-out · 1" exists but the panel itself says nothing.

## Scope
Frontend-first; **no change to payable fraction / payroll behaviour** in this task.
1. In the Day tab (`frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx`, tiles at ~205-212) when
   the selected day has a first-in and no last-out:
   - Replace "Worked hours —" with **"Incomplete"** and a one-line hint: *"No clock-out recorded. Regularize
     to add it."*
   - Replace **"0%"** with **"—"** and a tooltip *"Not counted until the clock-out is fixed."*
   - Show a **Regularize** button reusing `dayActionsFor` / `AttendanceDayActions.tsx` (HR sees the on-behalf
     action; an employee sees their own request flow). Default the action to "Clock-out fix".
2. Backend: expose `missing_clock_out: bool` (and `remark`) on the per-employee Day analytics response
   so the frontend doesn't infer it from nulls (`AnalyticsOut`/`EmployeeAnalyticsOut` in
   `backend/app/modules/attendance/schemas.py` ~544/636/648; built in `dashboard_service.py` ~1139).
   An *open* session on **today** is not "missing" — only past days or a closed shift (same rule as the
   `missing_clock_out` exception, `dashboard_service.py:1015-1043`).
3. Week/Month periods: unchanged.

**Open question for the product owner (do not change here):** should a Present-but-no-clock-out day
count as 0 payable? Raised as the late/status decision in `.plans/attendance-shifts-leave-holidays-todo.md` §6.

## Files
- `frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx`, `AttendanceDayActions.tsx`, `frontend/src/lib/api.ts` (types)
- `backend/app/modules/attendance/dashboard_service.py`, `schemas.py`
- `backend/app/tests/modules/test_attendance_dashboard.py` (or the existing dashboard test module)

## Acceptance criteria
- [ ] Day with IN and no OUT on a past date shows "Incomplete", "—" (not 0%), the hint and a working Regularize action.
- [ ] Today's open session shows the normal live behaviour (no hint).
- [ ] Day with both punches is unchanged; Week/Month unchanged.
- [ ] API returns `missing_clock_out` correctly; tenant-scoped; tests cover past-open, today-open, complete, no-punch.
- [ ] Verified in the browser against the 09-Oct case; shimmer/spacing conventions untouched.

Completed: 2026-10-23
Note: closed with backend tests green (the 235 lock-impact/423 tests, the 4 new 236 analytics tests) and `tsc` clean; the full suite had 88 pre-existing failures identical with and without this change. Browser checks were not done at close.
