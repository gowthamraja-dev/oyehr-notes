---
task: 241
title: Range assignment endpoint: PUT /shifts/employee-shifts/range
status: done
depends_on: [239]
---

# 241 — Range assignment endpoint: PUT /shifts/employee-shifts/range

## Scope
Reported: HR must apply shifts day-by-day; wants week/month. Today `PUT /employee-shifts/day`
does one employee × one date and `POST /employee-shifts/bulk` creates an open-ended row from one
effective date. Add `PUT /api/v1/shifts/employee-shifts/range`, gated `RequirePermission("UPDATE",
"ATTENDANCE")` like `/day`:

```
in:  { employee_master_ids: [int,..], from_date, to_date, shift_master_id,
       work_location_master_id?, holiday_calendar_master_id?,
       weekdays?: [1..7] (ISO, default all), skip_week_offs: bool = true,
       overwrite_manual: bool = true }
out: { assigned_count, unchanged_count, week_off_skipped_count, manual_skipped_count,
       locked_skipped_count, outside_employment_count,
       per_employee: [{employee_master_id, assigned, skipped:[{date, reason}]}] }
```

Implementation: add `_set_employee_shift_for_range` in `shifts/service.py` generalising
`_set_employee_shift_for_day`: carve ONE bounded segment `[from,to]` out of the timeline (trim the
covering row's tail, delete/trim rows fully inside, re-insert the remainder after `to`) — do NOT
loop the per-day function for writes (a month × org would create ~30 single-day rows/employee).
Non-contiguous days (weekday filter, week-offs on the NEW shift via `is_shift_week_off`, locked
days via `_attendance_locked`, outside employment via `_within_employment`) split the range into
contiguous runs; skipped days are reported, never fail the batch. Single-day runs keep
`is_auto_assigned=False`. When `overwrite_manual=false`, runs are split around human single-day rows.
Structural errors (unknown shift/location/calendar, non-report for a manager, duplicate ids,
from>to, range >92 days `_MAX_AUTO_ASSIGN_DAYS`) reject the whole request (4xx).
Reuse guards: `_require_employee`, `_require_manager_or_admin(…, "UPDATE")`,
`_require_assignable_shift`, `_get_work_location`, `_require_assignable_holiday_calendar`.
Every query scoped by `principal.tenant_id`; INFO log on success, WARNING at guards; `log_activity`
per employee. The shifts router is an `EncryptedRoute` — the endpoint inherits that; the frontend calls it with `secureFetch`.
NOT in scope: UI (task 243), location-only mode (task 242), roster read perf (task 244).

## Files
`hrms/backend/app/modules/shifts/{schemas,service,router}.py`, `hrms/backend/app/modules/shifts/carve.py` (pure timeline arithmetic),
`hrms/backend/app/tests/modules/test_shifts.py`, `hrms/backend/app/tests/modules/test_shift_range_carve.py`,
`hrms/docs/` shift doc if one exists (update, don't add).

## Implementation notes (2026-10-24)
- Rows a range fully replaces are **soft-deleted** (`is_active=false, archive=true, archived_*`) per `hrms-soft-delete`;
  `_resolve_effective_row` now filters `is_active`/`archive` so they stop resolving.
- Per-day conditions are decided from one pre-loaded snapshot per employee, then applied run by run
  (`_apply_range_run` reloads the overlap each run).

## Acceptance criteria
- [x] (unit, `test_shift_range_carve.py` — 12 passed) interior split / edge-aligned / spanning rows / gap / contiguous runs
- [x] (DB, `test_shifts.py`) Range interior to a long standing row → 3 rows (before / range / after), no gaps/overlaps
- [x] Range aligned to either edge; range spanning several existing rows; range over a gap
- [x] weekdays filter and week-off skip split into runs correctly
- [x] locked / outside-employment / manual-protected days skipped + reported, rest applied
- [x] Manager can only target direct reports (403 otherwise); non-UPDATE role 403; 401 unauth
- [x] Cross-tenant employee / shift / location / calendar ids rejected
- [x] >92-day, from>to, duplicate ids, empty list → 4xx
- [x] `_resolve_effective_row` / roster read back matches the applied plan day by day
- [x] `uv run pytest app/tests/modules/test_shifts.py` fully green

## Verification (2026-10-24)
`uv run pytest app/tests/modules/test_shifts.py app/tests/modules/test_shift_range_carve.py` → 140 passed (local postgres:18 on :5433). Fixed two tests that mis-stated existing behaviour (an unconfigured role passes the `RequirePermission` route gate; the roster hides relieved employees) and added edge-aligned, gap, manager-scope and foreign shift/location/calendar tests. Docs: `docs/leave-and-attendance/shifts/api-and-pages.md`.
