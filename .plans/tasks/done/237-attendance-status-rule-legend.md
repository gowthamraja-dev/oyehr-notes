---
task: 237
title: "How status is decided" legend on the attendance register
status: done
depends_on: []
---

# 237 — "How status is decided" legend on the attendance register

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Source:
`.plans/attendance-shifts-leave-holidays-todo.md` item **ATT-G1** (notes: "What is logic for Absent and
Present — we should put those details on the system"; issues.csv `HR:ATTENDANCE-B4`, `Admin:INS-B3`).

## Why
Users can't tell why a day is Present / Half day / Absent / Late. Review rows that looked inconsistent
(2h32m = Half day, 4h54m = Present, "Absent + Late") were all explained by the General shift's overrides
(full day 4h / half day 2h) — the rule is simply invisible. Only grace tooltips exist today
(`frontend/src/dashboards/hrManager/Attendance.tsx:86,95`).

## Rule to display (as built)
Written by `_attendance_status` (`backend/app/services/attendance_recompute_service.py:453-530`):
- Full-day leave → On leave. Holiday / week-off → that label, or Present if the person worked.
- Open Working day with a punch → Present (not settled until day close).
- **Closed day:** worked ≥ **full-day minutes** → Present; ≥ **half-day minutes** → Half day;
  any worked time below half-day → **Absent** (`SHORT_DAY_STATUS`).
- IN with no OUT on a closed day → Present, remark "Forgot to clock out".
- No punches → Absent once grace-in has passed (same-day, only when grace-in > 0 on a non-flexible shift)
  or after the auto-absent day; otherwise "Yet to check in".
- **Late** = a badge (not a status): late-by minutes > 0 on a Working day, beyond grace-in.
- Thresholds per shift in `policy_config`: `min_full_day_minutes`, `min_half_day_minutes`,
  `grace_in_minutes`, `grace_out_minutes`. **Defaults when blank: 510 / 270 minutes**
  (`attendance_recompute_service.py:47-48`), halved on a half-day week-off. Read via `day_thresholds`
  (`:400-410`).

## Scope
1. **Backend:** `GET /attendance/status-rules?shift_id=<id>` (read-only, `READ ATTENDANCE`, tenant-scoped)
   returning the effective thresholds for a shift (or the CDP's shifts as a list) by calling the **same**
   `day_thresholds` / grace readers the recompute uses — no copy of the numbers, so the legend can never
   drift. Include `source: "shift_override" | "default"` per value and the auto-absent day count.
2. **Frontend:** an info button beside the register's status filter / tiles
   (`frontend/src/dashboards/hrManager/Attendance.tsx`) opening a popover "How status is decided":
   rule bullets above + a small table of the *selected employee's / filtered shift's* actual numbers
   (e.g. "General — full day 4h · half day 2h · grace 15 min (override)"). Same popover reusable in
   `shared/EmployeeAttendanceTab.tsx` and the HR Admin attendance insights rail.
3. In the shift editor's "Min. for full day / half day" help text, point to this legend.

**Not in scope:** changing any rule or default; fixing the shift form's "inherited" label mismatch
(item SHF-D4); Late/Absent counting decision (item ATT-D3).

## Files
- `backend/app/modules/attendance/router.py`, `service.py` (or `dashboard_service.py`), `schemas.py`
- `backend/app/tests/modules/test_attendance.py`
- `frontend/src/dashboards/hrManager/Attendance.tsx`, new `frontend/src/dashboards/shared/StatusRulesPopover.tsx`, `frontend/src/lib/api.ts`
- Tailwind only; use existing popover/tooltip primitives; skeleton via `Shimmer*` primitives if it loads async

## Acceptance criteria
- [ ] Endpoint returns the shift's effective full/half/grace values, flagging overrides vs defaults; blank → 510/270.
- [ ] A shift edited via the shift screen shows the new values in the legend without a code change.
- [ ] Popover appears on the HR Manager register, employee Day/Week/Month view and HR Admin insights.
- [ ] Tests: values match `day_thresholds` for override, default and half-day-week-off cases; tenant isolation; 401/403.
- [ ] Verified in the browser against the General shift (4h/2h override visible and labelled "override").

Completed: 2026-10-23
Note: closed on the user's instruction. Backend tests green (new status-rules tests in test_attendance.py / test_attendance_dashboard.py; attendance, dashboard, recompute and shifts modules pass apart from the existing test_hardening_manager_scope_sweep failure) and `tsc` clean. The browser check against the General shift was left to the user and is not recorded here.
