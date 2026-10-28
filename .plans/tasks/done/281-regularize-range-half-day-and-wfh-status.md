---
task: 281
title: Regularize range — Half day and Work from home day statuses (backend)
status: done
depends_on: [270]
---

# 281 — Regularize range — Half day and Work from home day statuses (backend)

## Scope
Today the range regularization (task 270) can only make a day **Present** (shift punches or custom times). Add two more outcomes, chosen per request, to the **existing
single-employee** preview/apply endpoints. No schema change (no DBML gate); same tables, same `_regularize_one`. Multi-employee is 282; UI is 283.

Decisions (user, 2026-10-27): **WFH = Present + remote location** (no new stored status; recompute never produces `WFH`); **Half day = HR picks first or second half**.

### Request fields (added to `_RangeTimes` in `attendance/schemas.py`, so preview and apply both carry them)
- `day_status`: `"present"` (default, today's behaviour) | `"half_day"` | `"wfh"`.
- `half`: `"first"` | `"second"`, required iff `day_status == "half_day"`, otherwise must be null (422).
- `half_day` always derives its times from the shift: `mode` must be `"shift"` (422 for `custom`). `wfh` accepts both modes (like `present`).

### Half day
`full, half = day_thresholds(shift, False)` from `app/services/attendance_recompute_service.py` (the shift's `min_half_day_minutes`, else 270). `first`: IN = shift start,
OUT = start + `half` min. `second`: OUT = shift end, IN = end − `half` min (night shifts: use `present_for_shift_times` instants so the math crosses midnight). Worked time is
exactly the half-day bar, so recompute settles the day to `HalfDay`, payable 0.5. A day with a real clock-in and no clock-out gets only a clock-out at `first_in_at + half`
(the `half` selector is ignored for it; the message says so). Mark the punches `raw.synthesized`.
- Skip `ALREADY_PRESENT` for a half-day request when the day is `Present` **or** `HalfDay` with both a clock-in and clock-out (adding punches cannot shorten a real day);
  generalise the message ("Already has a clock-in and clock-out").
- Block `DAY_OPEN` when the date is today and the shift has not ended yet (an open day with any punch recomputes to Present until the close sweep — the result would be
  wrong now and silently change later). Use the recompute service's `_day_closed` on the day's shift end.
- If the resolved shift's `half >= full`, block `INVALID_TIMES` ("Half-day minimum is not below the full-day minimum on this shift").

### Work from home
Same punches as `present` (shift or custom), plus the day's work location moves to the tenant's remote site (`get_remote_work_location`; `WorkLocationMaster.is_remote`).
- No remote site configured → every candidate day is `blocked` `NO_REMOTE_SITE` ("No remote work location is set — set one under Work Locations").
- A locked day cannot take a location change (the shifts rules skip locked days) → `blocked` `WFH_LOCKED` ("Locked days can't be moved to the remote site — regularize as Present").
- Apply, per day inside the same `db.begin_nested()` and **before** `_regularize_one`: `apply_work_location_to_days(db, principal, employee, d, d, remote.id,
  action_path=".../regularize-range")` (`modules/shifts/service.py`; does not commit). If it assigned 0 days and the skip reason is not `unchanged`
  (e.g. `no_standing_shift` — a day override with no standing row), raise `HTTPException(409)` so the whole day rolls back and is reported `failed`/`REJECTED`
  with the reason in plain English. Then `_regularize_one` runs; recompute reads the new location, so the row's `work_location_master_id` is the remote site.
- Extra `raw_extra` key `wfh: true` on the punches.

### New codes (`RangeCode`)
`DAY_OPEN`, `NO_REMOTE_SITE`, `WFH_LOCKED`. `RangeDayPlan` and the result rows keep their shape; `RangeDayPlan` gains `day_status` echo? — **No**: the request owns it. The
apply result's `status` / `payable_day_fraction` already show the outcome (`HalfDay` / `0.50`, `Present` / `1.00`).

### Also
- The activity-log row (`deleted_data`) and the in-app summary notification carry the chosen status ("HR regularized 3 days as half days in Oct-26" / "as work from home") —
  extend `in_app.by_hr_range` with an optional label.
- Logging: stdlib `logging`, `%s`, never the note text; add `day_status` to the INFO completion line.

## Files
`backend/app/modules/attendance/{schemas,regularize_range,in_app}.py`, `backend/app/modules/attendance/service.py` (only if `_regularize_one` needs a hook — prefer not),
tests in `backend/app/tests/modules/test_attendance_regularize_range.py`.

## Acceptance criteria
- [x] Defaults unchanged: a request without the new fields behaves exactly as before (existing 34 tests still pass untouched)
- [x] `half_day` first/second → day recomputes to `HalfDay`, payable 0.5, punches span exactly the shift's half-day minutes at the start / end of the shift (also a night shift)
- [x] `half_day` on a day with real IN and no OUT → only a clock-out at IN + half; on a day already Present/HalfDay with both punches → skip `ALREADY_PRESENT`
- [x] `half_day` today before shift end → `DAY_OPEN`; `half` missing/extra or `mode=custom` → 422
- [x] `wfh` → day is Present, the row's `work_location_master_id` is the remote site, punches carry `wfh`; works in `custom` mode too
- [x] `wfh` with no remote site → `NO_REMOTE_SITE`; locked day → `WFH_LOCKED`; a day whose location write is skipped at apply (no standing shift) is `failed`, rolled back (no punches left)
- [x] Apply re-classifies (a day that stops being a candidate between preview and apply is reported, not written)
- [x] Gate and tenant-scoping tests from 270 still hold for the new modes (403 manager, 404 other tenant)
- [x] `uv run pytest` green for the attendance, shifts, authz and import suites

## As built (2026-10-27)
`day_status` / `half` added to `_RangeTimes` (so preview and apply, one employee or many, all carry them); classification and the half-day / WFH punch maths are in
`attendance/regularize_range.py` (`_regularize`, `_move_to_remote`). WFH reuses `shifts.service.apply_work_location_to_days` inside the per-day savepoint; a skipped location write
raises 422 → the day is `failed`/`REJECTED` and rolled back. A lone-clock-in half day gets a clock-out at IN + half. `half_week_off` thresholds are honoured via `day_types[...]`.
`in_app.by_hr_range` takes an optional `outcome` ("marked as a half day" / "marked as work from home"); the activity row carries `day_status` / `half`.
Tests: 22 new in `test_attendance_regularize_range.py` (56 total there). Suites run: attendance, recompute, WFH, import, shifts, authz — 785 pass; the one failure
(`test_employee_daily_pagination_matches_my_daily_shape`, extra `remarks` key) is the known pre-existing one from 270.

Completed: 2026-10-27
