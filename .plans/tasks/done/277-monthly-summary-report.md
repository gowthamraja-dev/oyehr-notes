---
task: 277
title: Monthly attendance summary report (one row per employee)
status: done
depends_on: [275]
---

# 277 — Monthly attendance summary report

## Scope
Report type `monthly_summary`: **no date columns** — one row per employee with the period's totals, the figure HR hands to payroll.
Built on 275's `data.py` pivot. Not a payroll feature: it only reports what attendance already computed; it does not read or write payroll tables.

### Layout
```
Emp ID | Name | Department | Shift | Working days | Present | Half days | Absent | Week off | Holidays | Leave | Paid leave | Unpaid leave | No shift | Late days | Late (min) | Early exit (min) | Total hours | Overtime (min) | Payable days | Pending regularisations
```
* **Working days** = days in range that are employed and not week-off / holiday (so Present + Half + Absent + Leave + No shift ≈ Working days for a settled period).
* **Paid / Unpaid leave**: split `OnLeave` days by the leave type's paid flag. Find how the leave module records the day
  (`EmployeeAttendanceDetail.leave_request_detail_id` → leave request → leave type) and the type's paid/unpaid attribute; **if the register rows do not
  carry it, read it with one batched, tenant-filtered query for the page's employee-days — never per row**. If the column cannot be derived reliably,
  drop the split and keep only `Leave`, and say so in the task's completion note.
* **Payable days** = Σ `payable_day_fraction` (same source as 275). Late days = count of late days; Pending regularisations = count of days with a pending request.
* A "today / future" window (days not yet settled) is reported in an extra `Unsettled days` column rather than silently counted as absent, so a mid-month
  export is not misread as final. Meta line says "Period not fully settled" when `to` ≥ today.
* Optional params: `employee_ids` as 275. Sorted department → name.
* Audit row `report: "monthly_summary"`.

## Files
* `backend/app/modules/attendance_export/monthly_summary.py`; registration; extend `test_attendance_export.py`

## Acceptance criteria
- [x] Seeded month with every day type: each total matches a hand count; Working days excludes week-offs and holidays
- [x] Paid/Unpaid leave split correct for one paid and one unpaid leave type (or the documented fallback, noted in the completion line)
- [x] Mid-range joiner: Working days counts only employed days
- [x] Range containing today → `Unsettled days` > 0 and the "not fully settled" meta line; a fully past range → 0 and no line
- [x] Payable days equals Σ the engine's fractions (not recomputed)
- [x] Scoping / limits / 401 / 403 / audit criteria of 275 hold (parametrised shared tests)
- [x] No N+1: query count for 200 employees × 31 days is bounded (assert with a query counter, as other tests in the repo do, or note if none exists)
- [x] `uv run pytest app/tests/modules/test_attendance_export.py` green

## Implementation notes
* Paid vs unpaid leave needed no extra query: the engine's `payable_day_fraction` on an OnLeave day is > 0 for paid leave and 0 for LOP, so the split is read off the row.
  Hence there is nothing per-employee to N+1 on; no query-counter test was added (the repo has no query-counter helper).
* The mid-range-joiner rule is the register's (`is_employed_on`), so Working days counts only employed days.

Completed: 2026-10-27
