---
task: 254
title: Day-type resolver reads shift_day_overrides (attendance, roster, auto-assign, leave, payroll)
status: done
depends_on: [253]
---

# 254 — Resolver reads day overrides

Plan: `.plans/shift-day-swap-plan.md` §3 "Resolver". Schema: `.plans/shift-day-swap-schema.dbml`.
Repo: `workspace-1/hrms/backend/`.

## Scope
Make every "is this date a week-off?" answer honour an override. **No new endpoint, no recalculation** (255–257).

Resolution order, the one definition: **Holiday > override(shift, date) > override(all shifts, date) > weekly rule > Working.**
- `override = 'WeekOff'` → `(is_week_off=True, is_half_day=False)`
- `override = 'Working'` → `(False, False)` — a full working day; the weekly rule's half-day flag is ignored
- Holiday keeps winning: `resolve_day_type` already checks the calendar first — do not reorder.

Changes in `app/services/calendar_resolver_service.py` (the shared matcher stays in ONE place, as `week_off_from_rows` already is):
1. `load_day_overrides(db, tenant_id, start, end) -> dict[tuple[int | None, date], str]` — live rows only
   (`is_active`, `archive = false`), filtered on `care_delivery_program_master_id`. Key `(shift_master_id | None, date)`.
2. `pick_day_override(overrides, shift_master_id, d) -> str | None` — shift row first, then the `(None, d)` row.
3. `week_off_from_rows(rows, target_date, override=None)` — new keyword; override short-circuits the rule match.
4. `is_shift_week_off(db, shift_master_id, target_date, tenant_id=None)` — when `tenant_id` is None read it from the
   shift row, so an org-wide row of another tenant can never match. One extra indexed query.
5. `_resolve_week_off` / `resolve_day_type` — no resolved shift: org-wide override first, then the Sat/Sun fallback
   (decided 26-Oct-26: payroll's `resolve_day_type(db, tenant, 0, d, None)` sees org-wide swaps).
6. `resolve_day_types_for_pairs` — one extra query for the whole window, then the picker per pair.

Callers to switch (each currently calls `week_off_from_rows` / `is_shift_week_off` directly — grep both names):
`app/modules/shifts/service.py` (auto-assign, `skip_week_offs`, range/copy-week skip, roster grid ~line 1418–1531,
`resolve_employee_day` ~1590–1626), `app/modules/attendance/dashboard_service.py` (via `resolve_day_types_for_pairs`),
`app/modules/leave/service.py:737-760` (uses `resolve_day_type`; check it needs no change), `app/modules/payroll/service.py:93-102`.
The roster must batch: load overrides once per request, not per employee-day.

## Files
- `workspace-1/hrms/backend/app/services/calendar_resolver_service.py`
- `workspace-1/hrms/backend/app/modules/shifts/service.py`
- `workspace-1/hrms/backend/app/tests/modules/test_calendar_resolver_batch.py` (8 new), `test_shifts.py` (3 new), `test_leave.py` (1 new)

## Acceptance criteria
- [x] Alternate-Saturday rule (Sat 2nd + 4th off): override `WeekOff` on the 1st Saturday → `WeekOff`, `Working` on the 2nd → `Working`; the 3rd stays Working and the 4th stays off (`test_override_swaps_alternate_saturdays_org_wide`)
- [x] Shift row beats the org-wide row for the same date; an org-wide row alone applies to every shift of the tenant and to a no-shift employee; a shift-only row does not reach a no-shift employee
- [x] A Public holiday on the swapped date still resolves `Holiday` (for both a `Working` and a `WeekOff` override)
- [x] Archived and `is_active = false` override rows are ignored
- [x] **Tenant isolation:** another tenant's org-wide *and* shift row never changes this tenant's result, via `resolve_day_type`, `is_shift_week_off` without `tenant_id` (read from the shift row), with it, `day_override_for`, and the batch path
- [x] Single-date and batched resolvers agree pair for pair with overrides present (`_assert_batch_matches_single` in every override test)
- [x] Roster, auto-assign and range-assign agree with the per-day resolver on swapped dates. Roster loads overrides in one query for the window; the existing `test_roster_query_count_does_not_grow_with_employees_or_days` still passes with it
- [x] Leave over a swapped date with `exclude_week_offs`: a Friday swapped to week-off counts 0, a Saturday swapped to working counts 1.00
- [x] Tests are not vacuous: with override handling removed from `week_off_from_rows` 4 resolver tests fail; with the wiring removed from `shifts/service.py` 3 integration tests fail; both restored and green
- [x] No regression with zero override rows. Full backend suite, same DB, before vs after this change: the failing-test sets are identical (94 tests), apart from this task's own new tests which only fail on the old code

## What changed
- `calendar_resolver_service.py`: `load_day_overrides` (batch, one query), `pick_day_override`, `day_override_for` (single date, one query, tenant read from the shift row when not passed); `week_off_from_rows(rows, date, override=None)` is still the one matcher; `is_shift_week_off(..., tenant_id=None)`; `_resolve_week_off` now takes `tenant_id` and consults an org-wide override before the Sat/Sun fallback; `resolve_day_types_for_pairs` loads overrides once per window.
- `modules/shifts/service.py`: range / copy-week / location-only closures and auto-assign pass `principal.tenant_id`; the roster loads overrides once and passes `pick_day_override` into `week_off_from_rows`.
- `resolve_day_type` callers needed no edit: attendance recompute, attendance dashboard, leave day rows, payroll attendance and payroll's no-shift working-days count all get it through the resolver.
- A `Working` override is a **full** working day: it also cancels a half-day week-off rule on that date.

## Notes for the next tasks
- 255 can rely on `recompute_attendance_day` re-resolving through the override with no further change.
- **94 backend tests fail on this branch with or without this change**, in a DB with no reference data and no S3 credentials, plus three weekday-dependent ones (`test_attendance_dashboard.py`: "yesterday" is a Sunday today, so the no-shift Sat/Sun fallback makes it a week-off). Not fixed here. Lists were diffed, not eyeballed.
- Not yet covered (belongs to 259): the roster does not *show* that a day is overridden, only the correct `is_week_off`.

Completed: 2026-10-26
