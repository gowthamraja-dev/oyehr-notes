---
task: 166
title: HR Manager attendance register — late-by in hours, "—" instead of "Incomplete"
status: ongoing
depends_on: []
---

# 166 — Attendance register: late-by in hours, "—" for open days

Work in **`workspace-2/hrms/`**. The branch at planning time was
`feature/gowtham_AttendanceDateRange`. Run `git -C workspace-2/hrms status -sb` first.

## Why
The HR Manager attendance register (`hrManager/Attendance.tsx`) shows two columns in
different units:
- **Worked hours**: `8h 05m` (built by the backend as `worked_hours_display`).
- **Late by**: `25m` (built in the frontend from `late_by_minutes`).

The user wants both in hours, so "Late by" should read `0h 25m` (and `1h 10m`, not `70m`).
A day with a clock-in but no clock-out currently shows the word **"Incomplete"** under
Worked hours. Show `—` there instead.

This is the canonical attendance UI. HR Admin → Insights → Attendance mounts the same
component (`embedded`), so the change covers both screens automatically.

## Scope
**In:**
1. **Late by column.** `frontend/src/dashboards/hrManager/Attendance.tsx:841` renders
   `` `${row.late_by_minutes}m` ``. Change it to `formatMinutes(row.late_by_minutes)`, using the
   file's existing helper at `:96`, which returns `Xh MMm`. Keep `—` when `!row.is_late`.
2. **"Incomplete" → "—".** The source is the backend.
   `backend/app/modules/attendance/dashboard_service.py:127 format_worked_hours` returns
   `"Incomplete"` when `first_in_at` is set and `last_out_at` is null. Make it return `"—"`,
   the same value it already returns for "no punches". Update its docstring, which cites
   design prompt §17. Changing the backend, not the frontend, means the CSV export
   (`dashboard_service.py:931`, which writes `row.worked_hours_display`) matches the screen.
3. **Tests**, in `backend/app/tests/modules/test_attendance_dashboard.py`:
   - `:311` `test_format_worked_hours_incomplete_when_no_clock_out`: expect `"—"`, and rename
     the test to `..._dash_when_no_clock_out`.
   - `:539` `test_register_incomplete_worked_hours_display`: expect `"—"`, and rename it.
   - `:955` CSV export test: it currently asserts that `"Incomplete"` appears on Priya Rao's
     line. Assert that the Worked Hours cell is `—` instead.
   - `:1152` already asserts `not in ("Incomplete", "—")`. It still holds, so leave it.

**Out:**
- **Worked hours format.** It is already `Xh MMm`, so the format doesn't change.
- **KPI tiles.** "Total/Average logged hours" already use `formatMinutes`.
- **CSV "Late By (min)" column.** It stays raw minutes. The export is a data file, and a
  numeric column is more useful in a spreadsheet. This is a decision to confirm with the user.
- **Employee-side screens** (`Employee/MyAttendance.tsx`, `shared/EmployeeAttendanceTab.tsx`
  "Late by {n}m"). These are a different screen. File a follow-up if the user wants them
  changed too.
- **Sorting.** The `late_by` and `worked_hours` sort keys still sort on the underlying minutes.
  Nothing changes there.

## Files
- `workspace-2/hrms/frontend/src/dashboards/hrManager/Attendance.tsx` (line ~841)
- `workspace-2/hrms/backend/app/modules/attendance/dashboard_service.py` (`format_worked_hours`)
- `workspace-2/hrms/backend/app/tests/modules/test_attendance_dashboard.py`

## Acceptance criteria
- [ ] A late row shows Late by as `Xh MMm`. For example, 25 → `0h 25m` and 70 → `1h 10m`.
      A row that isn't late shows `—`.
- [ ] A row with a clock-in and no clock-out shows `—` under Worked hours. "Incomplete" no
      longer appears anywhere on the register.
- [ ] The CSV export's Worked Hours cell for that row is `—`.
- [ ] `grep -rn "Incomplete" backend/app/modules/attendance frontend/src/dashboards/hrManager`
      returns nothing.
- [ ] `uv run pytest app/tests/modules/test_attendance_dashboard.py` is green. Run
      `uv sync` in `workspace-2/hrms/backend` first if `.venv` is missing.
- [ ] `npx tsc --noEmit` and `npm run lint` are clean in `workspace-2/hrms/frontend`. Run
      `npm install` first if `node_modules` is missing.
- [ ] Manual check: HR Manager → Attendance, for a single day and for a date range. Also check
      HR Admin → Insights → Attendance, since it renders the same component.
