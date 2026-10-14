---
task: 202
title: HR Manager attendance — tiles count inactive/not-yet-joined employees, and no-shift employees sit in "Yet to check in" forever
status: done
depends_on: []
---

# 202 — HR Manager attendance: tile headcount and the no-shift bucket

Build this in the **top-level `hrms/`** clone, the same clone as tasks 180 and 201, on whatever
branch it's on (`feature/gowtham_HrmsDevConfig` when this was planned). Paths below are
relative to `hrms/`.

## Why (diagnosis, 2026-10-08, CDP 100240 NEXTENTI, read-only against hrms-dev)
HR reported tiles of roughly "Present 36 / Absent 36 / Yet to check in 2" with only **76**
employees. The tiles are live (they re-poll every 60 s, task 180). That afternoon they
summed to **79** (`present=38, absent=38, yet_to_check_in=3, on_leave=0, off_day=0`). The
counts aren't adding wrong. The population behind them is wrong. There are two causes.

### Cause 1: the headcount includes employees who shouldn't be counted (79, not 76)
`_employee_scope_stmt` (`backend/app/modules/attendance/dashboard_service.py`) filters by CDP
through `corp_masters` and by manager scope. It does **not** filter on `is_active`,
`archive`, `joining_date` or `relieving_date`. In CDP 100240, the 79 employees in scope
include these three:

| id | name | emp_id | problem |
|---|---|---|---|
| 95567 | Test | 2024152 | `is_active = false`, but still counted (shows as Yet to check in) |
| 87038 | BELLAPU | NT-131 | `joining_date = 2028-08-10`, in the future (probably a data typo), but punches daily |
| 81571 | Vasu | — | `joining_date IS NULL` |

79 − 3 = 76. That matches HR's number, but **confirm with HR which screen gives "76"**
(Employee Directory "Active" = 78) before settling the rule.

### Cause 2: employees with no resolved shift can never become Absent
`compute_effective_status` only marks a never-punched day "Absent" after grace
(`_is_grace_candidate`) when the row has `shift_master_id` and `shift_start_at` set. An
employee with **no shift assigned** stays `yet_to_check_in` all day. Past days do flip to
Absent (`attendance_date < today`). So today's "Yet to check in" is mostly *people with no
shift*, not people still within grace. On 2026-10-08 the 5 no-shift employees were:
VANDANA NT-158 and BELLAPU NT-131 (punched, so Present), PAVAN NT-44 and Remella NT-141 (not
punched, so Yet to check in), and Test 2024152 (inactive, Yet to check in).
VANDANA and PAVAN joined **2026-10-08** and have no shift assignment yet.

## Scope
1. **Headcount rule.** Add one shared predicate for "employee counts for attendance on date
   D": `is_active AND NOT archive AND (joining_date IS NULL OR joining_date <= D) AND
   (relieving_date IS NULL OR relieving_date >= D)`. Apply it in `_scoped_employees` (single
   date) and in the per-day build in `_build_scoped_rows_for_range` (range: per employee-day,
   so a mid-range joiner only counts from joining).
   - It flows automatically to everything built on these helpers: the tiles, the register,
     exceptions, export, and the scheduled summary in `attendance_alerts` (it calls
     `day_status_counts` with its own employee list, so check that caller too).
   - **Open decision (ask HR):** should `joining_date IS NULL` count? The predicate above
     includes it, so Vasu stays counted. If HR wants 76 exactly, the fix is data: set Vasu's
     joining date. Don't silently drop NULLs.
2. **No-shift bucket.** Add `no_shift_count` to `AnalyticsOut`/`DayStatusCounts`. These are
   employees on a Working day with no resolved shift who haven't punched. Count them there,
   not in `yet_to_check_in`.
   - Frontend: give the "Yet to check in" tile the sub-line "+N without a shift", or add a
     `no_shift` exception chip. Pick one; the chip reuses the existing exception filter.
   - Clicking it lists those employees so HR can assign shifts (deep link to Shift
     Scheduling).
3. **Data clean-up note for HR (no code):** Test 2024152 (inactive), BELLAPU's 2028 joining
   date, Vasu's missing joining date, and PAVAN/Remella/VANDANA/BELLAPU with no shift.

**Not in scope:** HR regularization (203/204) and recording leave (204).

## Files
- `backend/app/modules/attendance/dashboard_service.py`: predicate, `_scoped_employees`,
  range builder, `DayStatusCounts`, `_day_status_counts`, analytics outputs
- `backend/app/modules/attendance/schemas.py`: `AnalyticsOut.no_shift_count`
- `backend/app/modules/attendance_alerts/*`: verify it uses the same employee filter
- `frontend/src/lib/api.ts` (`AttendanceAnalytics` type), `frontend/src/dashboards/hrManager/Attendance.tsx`
  (tile sub-line or chip, and the skeleton if the tile count changes)
- `backend/app/tests/modules/test_attendance_dashboard*.py` (or the existing analytics test file)

## Acceptance criteria
- [ ] Inactive, archived, not-yet-joined and relieved employees are excluded from the tiles,
      register, exceptions and export for that date. Tests cover each case, plus a range that
      spans a joining date.
- [ ] A never-punched, no-shift employee is counted in `no_shift_count`, not
      `yet_to_check_in`. A no-shift employee who punched is still Present.
- [ ] present + absent + yet_to_check_in + no_shift + on_leave + off_day == headcount
      (asserted in a test).
- [ ] CDP scoping is unchanged: a cross-tenant test still passes.
- [ ] Re-running the 2026-10-08 diagnosis against hrms-dev gives headcount 77 (or 76 once
      Vasu's joining date is fixed), with PAVAN and Remella under no-shift.
- [ ] `uv run pytest` for the attendance tests is green.

Completed: 2026-10-08
