---
task: 71
title: Manager attendance dashboard — exceptions API
status: done
depends_on: [68, 70]
---

# 71 — Manager attendance dashboard — exceptions API

## Scope

`GET /api/v1/attendance/exceptions` — new endpoint, not in the original `api-and-pages.md`
sketch (flag this addition in task 81's docs update). Backs design prompt §9: a count-per-type
list of actionable attendance problems for one date, and a way to filter the register (task 70)
down to one exception type.

This task is thin by design: every exception type below is a **derived view over the same data
task 70's register query already reads** (`EmployeeAttendanceDetail` + `AttendanceRequestDetail`)
— do not introduce a new table, job, or notion of "exception" beyond a named predicate.

## Exception types (design prompt §9)

| Type key | Predicate |
| --- | --- |
| `missing_clock_in` | `day_type='Working'`, `first_in_at IS NULL`, `last_out_at IS NOT NULL` — an OUT with no IN, i.e. a data anomaly the assembler recorded (rare; still representable in the schema) |
| `missing_clock_out` | `first_in_at IS NOT NULL AND last_out_at IS NULL` (same predicate as task 68's `"Incomplete"` worked-hours case) |
| `late_arrival` | `late_by_minutes > 0 AND day_type='Working'` (same as task 70's `status=late`) |
| `early_departure` | `early_exit_minutes > 0 AND day_type='Working'` (column already exists on `EmployeeAttendanceDetail`, computed by `attendance_recompute_service.py`, not yet surfaced anywhere in the UI) |
| `incomplete_punch` | Same predicate as `missing_clock_out` — design prompt lists both terms; treat as one type, don't double-count. Use `missing_clock_out` as the canonical key and skip `incomplete_punch` as a separate one (note this collapse in task 81's docs). |
| `unresolved_regularization` | `AttendanceRequestDetail.status = 'Pending'` for the scoped employees, joined the same way task 70's `has_pending_regularization` flag is computed |

No `attendance record requiring manager review` type — the design prompt lists it without a
concrete rule; it isn't derivable from anything in the current schema beyond the five above, so
it is intentionally omitted (do not invent a `remarks IS NOT NULL` heuristic — `remarks` is
free text set by multiple code paths for multiple reasons).

## Endpoint

`GET /attendance/exceptions?date=2026-08-19&type=late_arrival&department=Cardiology&shift_id=4&limit=25&offset=0`

- `date` required.
- `type` optional — omitted means "counts for every type, no row list"; present means "counts for
  every type **plus** the paginated row list for that one type" (same row shape as task 70's
  `RegisterRowOut`, reuse it, don't invent a parallel shape).
- `department`/`shift_id` — same optional filters as tasks 69-70.
- `search`, pagination — same conventions as task 70, only meaningful when `type` is present.

### Response

```json
{
  "date": "2026-08-19",
  "counts": {
    "missing_clock_in": 0, "missing_clock_out": 2, "late_arrival": 3,
    "early_departure": 1, "unresolved_regularization": 2
  },
  "type": "late_arrival",
  "items": [ /* RegisterRowOut[], only present when `type` is set */ ],
  "total": 3, "limit": 25, "offset": 0
}
```

## Authorization & scope

Reuse task 69's scope-resolution helper exactly (same manager/admin/CDP predicate) — do not
reimplement.

## Files

- `backend/app/modules/attendance/router.py` — one new `GET /exceptions` route
- `backend/app/modules/attendance/service.py` / `dashboard_service.py` — `get_exceptions(db,
  principal, date, type_, department, shift_id, search, limit, offset) -> ExceptionsOut`, built by
  calling the same row-fetch helper task 70's `get_manager_register` uses internally, then
  applying one of the five predicates above (factor the shared row-fetch out of task 70 if it
  isn't already a separate function by the time this task starts)
- `backend/app/modules/attendance/schemas.py` — `ExceptionsOut`

## Tests

- Counts for all five types against a fixture set with at least one row per type, zero for types
  with no matching row.
- `type=unresolved_regularization` row list matches exactly the employees with a `Pending`
  `AttendanceRequestDetail` for `date`.
- Manager/CDP scoping enforced (reuse task 69/70's fixture pattern).
- Omitting `type` returns counts only, no `items`/`total` key confusion (either omit the keys
  entirely or return an empty list — pick one and assert it explicitly).

## Acceptance criteria

- [x] All five counts are correct and CDP/manager-scoped.
- [x] `type=<x>` narrows to a paginated row list reusing task 70's row shape, not a new one.
- [x] No new table, column, or job introduced — everything reads existing columns.
