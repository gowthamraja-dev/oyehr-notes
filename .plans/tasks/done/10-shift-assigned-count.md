---
task: 10
title: "assigned_count on ShiftOut — how many employees are currently on a shift"
status: done
depends_on: []
---

# 10 — `assigned_count` on `ShiftOut`

## Scope

The "Attendance & Shifts" screen (task 11) shows "N employees mapped" per shift and org-wide.
No endpoint currently reports how many active `employee_shift_details` rows point at a given
shift — this task adds it, mirroring the existing `week_off_count` pattern exactly.

## Files

- `backend/app/modules/attendance/service.py`
- `backend/app/modules/attendance/schemas.py`
- `backend/app/tests/modules/test_attendance.py`

## Work

1. **`service.py`** — add `_assigned_count(db, shift_id)` next to `_week_off_count` (~line 266):
   ```python
   def _assigned_count(db: Session, shift_id: int) -> int:
       return db.scalar(
           select(func.count(EmployeeShiftDetail.id)).where(
               EmployeeShiftDetail.shift_master_id == shift_id,
               EmployeeShiftDetail.trmntn_dt.is_(None),
               EmployeeShiftDetail.is_active.is_(True),
               EmployeeShiftDetail.archive.is_(False),
           )
       ) or 0
   ```
   `trmntn_dt IS NULL` = current assignment (per `employee_shift_details`' own convention,
   documented in `docs/leave-and-attendance/01-domain-model.md` §2.5).
2. **`_shift_out`** — add an `assigned_count: int = 0` parameter, pass it through to
   `ShiftOut(..., assigned_count=assigned_count)`.
3. **`list_shifts`** — already does a per-shift aggregate join for `week_off_count`; add a
   second aggregate (or a second query) for `_assigned_count` per shift and pass it to
   `_shift_out`.
4. **`create_shift`** — new shift has no assignments yet; `_shift_out(shift)` defaults to 0
   (no change needed beyond the schema default).
5. **`update_shift`** — already calls `_shift_out(shift, _week_off_count(db, shift.id))`; add
   `_assigned_count(db, shift.id)` alongside it.
6. **`schemas.py`** — add `assigned_count: int = 0` to `ShiftOut`, next to `week_off_count`.
7. **Tests** — add to `test_attendance.py`:
   - A freshly created shift returns `assigned_count == 0` on list.
   - `POST /attendance/employee-shifts` assigning an employee to the shift bumps it to `1` on
     the next `GET /attendance/shifts`.
   - `PATCH /attendance/employee-shifts/{id}` with `trmntn_dt` set (ending the assignment)
     brings it back to `0`.

## Acceptance criteria

- [x] `ShiftOut.assigned_count` reflects the count of currently-active (`trmntn_dt IS NULL`,
      not archived) `employee_shift_details` rows for that shift, on both `list_shifts` and
      `update_shift` responses.
- [x] The three new test cases pass; full `test_attendance.py` suite otherwise unaffected
      (aside from the pre-existing task-07-related `test_config_*` failures, out of scope here).
      (38 passed, same 3 pre-existing unrelated failures.)
- [x] No model or migration changes — this is a read-side aggregate, no new column.

Completed: 2026-08-12
