---
task: 302
title: My Shifts — shift calendar API (month grid + week strip: shifts, week-offs, holidays)
status: done
depends_on: []
---

# 302 — My Shifts: shift calendar API

## Scope
`GET /api/v1/shifts/me/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD` — the caller's own days, one entry per
calendar date. One endpoint feeds three screens of the mobile mockup (`.plans/my-shifts-mockup.jpeg`):
the **Calendar** tab (client sends the month, e.g. 01-Oct..31-Oct; dots = shift assigned / week off /
holiday; the selected-day card), the **My Shifts** tab ("Assigned Shifts" list, Week Off rows) and the
Home **This Week** strip (Mon..Sun, which crosses a month — hence a range, not `month=`). Self-service: **ungated** (own record only),
on the existing encrypted `/shifts` router. Read-only, no schema change.

Not covered: the available-shifts list (task 303), change requests (tasks after the schema in
`.plans/my-shifts-schema.dbml` is approved).

### Contract
Response `MyShiftCalendarOut`:
- `from_date`, `to_date`, `time_zone`.
- `days[]`, one per date in the range, each:
  `date`, `day_type` (`Working` | `WeekOff` | `Holiday`), `is_half_day`, `shift`
  (`shift_master_id`, `name`, `code`, `color`, `start_time`, `end_time`, `is_night_shift`; `null` when
  unassigned), `holiday` (`name`, `holiday_type`; only when a Public holiday), `day_override`
  (`WeekOff`/`Working` when HR swapped the day, else null), `has_pending_change_request` (false until
  the change-request task lands — keep the field so the client contract doesn't change). The "Assigned"
  badge and "Off" pill are derived by the client from `day_type`/`shift`; no status field is needed.
- `summary`: counts of working days, week-offs, holidays, unassigned days.

Rules:
- Resolve the day with `calendar_resolver_service` only — `resolve_effective_shifts_for_range`,
  `resolve_day_types_for_pairs` / `build_holiday_lookup`, `week_off_with_swap`. Never re-derive week-off
  or holiday logic. Precedence is Holiday > swap > weekly rule > Working (see `shift_day_overrides`).
- Only `holiday_type = 'Public'` is a holiday; Restricted/Optional may be listed as informational
  but never set `day_type = 'Holiday'`.
- Query the whole range in a fixed number of queries (no per-day `db.get`).
- Range validation: `from <= to`, at most 62 days, not more than 24 months back or 12 forward → 422.
  Leading/trailing greyed days in the month grid are the client's; it asks only for the real month (or week).
- Days before the employee's joining date or after exit: return `outside_employment: true`, `shift = null`,
  and `day_type = null` (so the client can grey them out rather than count them as working days).
  Add `outside_employment` to each day, and make `day_type` nullable.
- Caller must be an employee (`_require_caller_employee`); every query filters by
  `principal.tenant_id` and the caller's own `employee_master_id`.

## Files
- `backend/app/modules/shifts/schemas.py` — `MyShiftCalendarOut`, `MyShiftCalendarDayOut`, `HolidayBrief`.
- `backend/app/modules/shifts/service.py` (or a new `my_calendar.py` beside it) — `get_my_calendar`.
- `backend/app/modules/shifts/router.py` — route **registered before** `/me/{target_date}`, or `calendar`
  is read as a date.
- `backend/app/tests/modules/test_shifts.py` — or a new `test_my_shifts.py`.
- `.claude/skills/hrms-mobile-api-integration/SKILL.md` and `docs/leave-and-attendance/shifts/api-and-pages.md`
  — add the endpoint to the catalogue.

## Acceptance criteria
- [x] Returns every day in the range, in order, with shift / day_type / holiday correct
- [ ] A weekly week-off, an alternate-Saturday rule, a day swap and a Public holiday each resolve as the roster shows them
- [x] A mid-month shift change shows the right shift on each side of the change
- [x] Unassigned and outside-employment days are distinguishable
- [ ] Holiday calendar picked per the employee's assignment (location-specific beats all-locations)
- [x] Another tenant's data never appears; bad range → 422; non-employee caller → 4xx
- [ ] Encrypted round-trip test; fixed query count asserted
- [x] A Mon..Sun range crossing a month boundary works (Home week strip)
- [x] Route does not shadow `/me/{target_date}`

## Progress (2026-10-29)
Built in `workspace-2/hrms` on `feature/gowtham_shift_grid_bulk`, NOT committed. Tests: `backend/app/tests/modules/test_my_shifts.py` (47 pass against the local `hrms-test-pg`). API only — not exercised from the mobile app or a browser.
Unchecked above and why: the alternate-Saturday rule is not tested here (weekly rule, day swap, Public holiday and a Restricted holiday are); the location-specific vs all-locations holiday fallback is the shared `build_holiday_lookup`, covered by `test_calendar_resolver_batch.py`, not re-tested; no encrypted round-trip for this GET (the router's `EncryptedRoute` is the same one the submit round-trip test exercises). The query-count test asserts a 7-day and a 60-day range run the same number of statements.

Completed: 2026-10-29
