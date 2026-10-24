---
task: 242
title: Change work location without re-picking the shift
status: done
depends_on: [241]
---

# 242 — Change work location without re-picking the shift

## Scope
Reported: "Select shift → Change location" — location is a sub-field of a shift assignment, so
changing only the location forces re-selecting a shift. Add a **location-only** mode:
- Backend: on `PUT /employee-shifts/range` (task 241) and `PUT /employee-shifts/day`, allow
  `shift_master_id` to be omitted when `change_location_only: true`; each covered day keeps its
  currently-resolved shift and only `work_location_master_id` (and optionally holiday calendar)
  changes. Days with no resolved shift are skipped + reported (`no_standing_shift`).
- Frontend: in `BulkAssignShiftModal` a "Change location only" toggle that hides the shift list;
  the cell popup in single-day mode gets the same toggle (default ON when opened to change location).
NOT in scope: the range/week/month picker itself (task 243) — this task only adds the mode flag
and wires it through whatever the modal looks like at that point.

## Files
`hrms/backend/app/modules/shifts/{schemas,service,router}.py`, `test_shifts.py`,
`hrms/frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`, `hrms/frontend/src/lib/api.ts`.

## Acceptance criteria
- [x] Location-only keeps each day's shift (incl. across a standing row boundary) and changes location
- [x] Day with no resolved shift skipped + reported; shift-required error when flag is false and shift omitted
- [x] UI toggle hides shift picker, submit enabled with only a location chosen
- [x] Tests for both endpoints; `tsc`/eslint clean

## Implementation notes (2026-10-24)
- `change_location_only` on both inputs (`schemas.py`, shared `_check_location_only`): requires `work_location_master_id`, forbids
  `shift_master_id` (422 otherwise); with the flag off `shift_master_id` is required (422). `holiday_calendar_master_id` omitted =
  keep the day's current calendar (in normal mode omitted still clears it).
- `/range`: per-day target is `(covering row's shift, calendar)`; `carve.keyed_runs` splits runs where the kept shift/calendar changes,
  so crossing a standing-row boundary writes one row per shift. New skip reason `no_standing_shift` + `no_standing_shift_count`
  (0 outside this mode). Week-off skipping checks the day's *kept* shift. `_apply_range_run` now takes explicit shift/location/calendar.
- `/day`: a day with no shift is a 422 `no_standing_shift: …` (single day, so an error rather than a skip list).
- Frontend: `BulkAssignShiftModal` single-day mode gets "Change work location only" (shown only when the cell already has a shift;
  hides the shift list and holiday calendar; submit needs a location). New prop `initialLocationOnly`, **not yet passed by
  `ShiftScheduling.tsx`** — the grid has no separate "change location" entry point, so the toggle defaults off there.
- Not done: the effective-date bulk mode (`POST /employee-shifts/bulk`) has no location-only mode; the range client function lands with 243.
- Verified: `pytest test_shifts.py test_shift_range_carve.py` → 154 passed; `tsc --noEmit` and eslint clean on the modal + api.ts;
  docs updated in `docs/leave-and-attendance/shifts/api-and-pages.md`.

## Browser smoke (2026-10-24)
Headless Chrome (playwright-core) against a local stack — API :8001 on a fresh local postgres:18 migrated + `seed_dev.py` + RBAC defaults for the 'beta' tenant, Next copy on :3001 with `NEXT_PUBLIC_API_URL` overridden (the shared remote backend was never touched). Logged in as the seeded HR Manager.
- Priya Nair Sun 25-Oct (has General): checkbox shown, ticking hides the shift list and holiday calendar, title becomes 'Change work location', submit disabled until a location is picked, then enabled; submit → toast 'Work location updated', cell still `GEN` + `HEA`; DB: General kept, location Head Office, rows carved to a single day.
- Beta Manager Sat (no shift): no checkbox offered.
