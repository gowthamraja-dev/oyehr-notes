---
task: 244
title: Batched roster read + month view
status: done
depends_on: [241, 243]
---

# 244 — Batched roster read + month view

## Scope
`list_shift_roster` resolves each employee-day with `resolve_employee_shift` +
`_resolve_effective_row` + `is_shift_week_off` — ~3 queries per employee-day (fine for a week,
unusable for a month × whole org). Rewrite to load all `employee_shift_details` rows for the
employees overlapping `[from,to]` in one query, preload shift masters and
`shift_week_off_details` for the shifts involved, and resolve in memory — behaviour identical
(same latest-effective-wins rule, same week-off semantics, same fields). Then add a Week / Month
toggle on the Shift Scheduling breadcrumb control (month = compact cells, horizontal scroll),
still clamped to today onward. Cap `to-from` (e.g. 62 days) server-side.
NOT in scope: pagination of employees (add only if measured slow after batching).

## Files
`hrms/backend/app/modules/shifts/service.py` (+ reuse `calendar_resolver_service` rule, don't
re-derive it a third time), `test_shifts.py`, `ShiftScheduling.tsx`, `api.ts`.

## Acceptance criteria
- [x] Existing roster tests unchanged and green; new equivalence test vs the old per-day resolver
- [x] Query count for a 31-day × 200-employee roster is O(1) in employees×days (assert in a test)
- [x] Month view renders, navigates, respects filters; no layout shift from skeleton

## Implementation notes (2026-10-24)
- `calendar_resolver_service.week_off_from_rows(rows, date)` is now the single week-off matcher; `is_shift_week_off`, the attendance batch
  (`resolve_day_types`) and the roster all call it (there were two copies before, this would have been a third).
- `list_shift_roster`: employees (1, as before) + assignment rows overlapping the window (1) + shifts in tenant (1) + week-off rows (1), resolved
  in memory with `_covering` (the same latest-effective-wins rule `_resolve_effective_row` uses). Measured: 17 statements for 2 employees × 7 days
  AND for 62 × 31 (the per-day version needed ~3 per employee-day). Window capped at `_MAX_ROSTER_DAYS = 62` (422 beyond / `to` < `from`).
- Tests (`test_shifts.py`): `test_roster_batched_read_equals_the_per_day_resolvers` (open-ended rows, single-day override with location, a gap,
  soft-deleted + archived rows, a shift from another tenant, a bounded row, week-of-month / half-day / deactivated week-offs — 5 employees × 31 days
  cell-for-cell against the old resolvers), `test_roster_query_count_does_not_grow_with_employees_or_days`, `test_roster_window_is_capped`.
  The 9 pre-existing roster tests are unchanged.
- UI: Week | Month toggle + period nav in the breadcrumb control. Month shows today→month end only (clamped), compact cells, horizontal scroll,
  sticky employee column; the day-column count rides on a `--cols` CSS variable (a Tailwind class can't carry a variable count). Tile and title
  follow the view. The roster skeleton now uses the real grid template (same width; 56px rows vs 56px real — a row with a location badge is 62px).
- Observation, not changed: `POST /employee-shifts/bulk` only looks at the employee's open-ended row, so after a bounded range assignment it can
  create an open-ended row *overlapping* it (latest effective date wins, so the grid reads fine, but the older row resurfaces after the bounded one ends).

## Browser smoke (2026-10-24)
Headless Chrome vs the local stack (API :8001, Next copy :3001), 22/22: week unchanged (7 columns); month = today→31 Oct (8 columns), one roster
request `from=2026-10-24&to=2026-10-31`; previous disabled in the current month; next → November (30 columns, request 1–30 Nov); scrolls
horizontally with the name column pinned and 30 Nov reachable; search + window in one request in month view; "Whole month" in the assign modal from
month view = 01–30 Nov; skeleton same width as real rows; month→week keeps the period (26 Oct – 01 Nov).
