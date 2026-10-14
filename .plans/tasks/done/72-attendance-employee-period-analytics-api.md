---
task: 72
title: Attendance — per-employee Day/Week/Month analytics API
status: done
depends_on: [68]
---

# 72 — Attendance — per-employee Day/Week/Month analytics API

## Scope

`GET /api/v1/attendance/employees/{employee_id}/analytics` — `api-and-pages.md` §3.1/3.2/3.3
already reserve this path ("Not built") for exactly this purpose: the aggregate metrics the
employee attendance drawer needs (design prompt §8) that `EmployeeAttendanceTab.tsx`'s existing
`getEmployeeAttendanceDaily` (task 54) does **not** compute — that endpoint returns raw per-day
rows only; nothing today sums them into "timely days", "attendance %", "average hours", etc.

**Does not replace** `GET /employees/{id}/daily` or `/today` (task 54) — those still back the
drawer's raw daily table and the "Day" tab's clock-in/out card. This is strictly the aggregate
layer on top, for the Week/Month tabs' metric tiles design prompt §8 lists:

- Day: worked hours, average hours, timely days, late days, attendance %
- Week: total hours, average hours, timely days, late days, attendance %
- Month: total hours, average hours, timely days, late days, attendance %, worked days

## Endpoint

`GET /attendance/employees/{employee_id}/analytics?period=day|week|month&date=2026-08-19`

`date` anchors the period the same way task 69 does (`week` = ISO week containing `date`,
`month` = calendar month containing `date`; `day` = just that one date).

### Response

```json
{
  "employee_master_id": 38, "period": "month", "date": "2026-08-19",
  "from": "2026-08-01", "to": "2026-08-31",
  "total_worked_minutes": 10104, "average_worked_minutes": 421,
  "timely_days": 17, "late_days": 3, "worked_days": 20,
  "attendance_percentage": 91.3,
  "shift": { "shift_master_id": 4, "name": "Morning", "start_time": "06:00:00", "end_time": "14:00:00" }
}
```

Formulas — do not invent alternates:
- `attendance_percentage` = `gaps.md #35`'s definition, same as task 69's period trend:
  `Σ payable_day_fraction / count(day_type = 'Working')` over `[from, to]`.
- `timely_days` = count of `Working` days where `late_by_minutes == 0 AND worked_minutes > 0`.
- `late_days` = count of `Working` days where `late_by_minutes > 0`.
- `worked_days` (month only, per design prompt §8) = count of days with `worked_minutes > 0`
  regardless of `day_type` (a worked WeekOff/Holiday counts).
- `total_worked_minutes` / `average_worked_minutes` = `Σ worked_minutes` / `Σ worked_minutes ÷
  count(days in range with worked_minutes > 0)` — average over days actually worked, not over
  every calendar day in the range (an all-zero denominator → `0`, not a division error).
- `shift`: the employee's effective shift for `date` (`resolve_effective_shift`), for the
  drawer's header — same shift info `EmployeeShiftAssignment`/`ShiftMaster` already expose
  elsewhere, just surfaced here so the drawer doesn't need a second round-trip.

## Authorization & scope

Reuse `_require_manager_or_admin_for_employee` from task 54's own code (`attendance/service.py`)
**verbatim** — this endpoint sits right next to `/today`/`/daily` in the same authorization
family (self, direct-report-manager, or admin; cross-CDP `employee_id` → `404`). Do not write a
new predicate.

## Files

- `backend/app/modules/attendance/router.py` — one new `GET /employees/{employee_id}/analytics`
  route
- `backend/app/modules/attendance/service.py` — `get_employee_analytics(db, principal,
  employee_id, period, date) -> EmployeeAnalyticsOut`
- `backend/app/modules/attendance/schemas.py` — `EmployeeAnalyticsOut`

## Tests

- Manager viewing a direct report's analytics for each period → correct aggregates against a
  hand-built fixture week/month of `EmployeeAttendanceDetail` rows.
- Manager viewing a non-report → `403`. Self-view → `200`. Admin → any employee in CDP → `200`.
- Cross-CDP `employee_id` → `404`.
- A period with zero worked days → all counts `0`, `attendance_percentage` handles the
  zero-`Working`-days edge case without dividing by zero (define and test the convention — e.g.
  `100.0` or `null` when there were no Working days to be measured against; pick one, document
  it in the response schema's field description).

## Acceptance criteria

- [x] All aggregate fields are computed from `EmployeeAttendanceDetail` rows already in the DB —
      no new table, no client-side aggregation moved into this task's frontend consumer (task
      78) beyond formatting.
- [x] Same authorization family and CDP-scoping as task 54, reusing its helpers.
- [x] Formulas match `gaps.md #35` and this file's definitions exactly, tested.
