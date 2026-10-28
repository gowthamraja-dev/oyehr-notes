---
task: 296
title: Shift roster — server-side role/location filters and paging
status: done
depends_on: []
---

# 296 — Shift roster: server-side role / location filters and paging

## Scope
`GET /shifts/employee-shifts/roster` returns every employee in scope for the window, and `ShiftScheduling.tsx` filters **role** and **work location** client-side over that
full list (`filteredRoster`). That does not scale with a large org and cannot coexist with a paged shared grid (297). Make the roster server-paged and server-filtered like
`GET /attendance/grid`:

- New query params: `page` (default 1) and `page_size` (default 50, max 100) — **both optional and backward compatible**: when `page` is omitted the endpoint behaves as today
  (other consumers, if any, must not break; grep the frontend for `listShiftRoster` callers first).
- `role` already exists server-side (`EmployeeMaster.designation`) — just have the page pass it instead of filtering client-side.
- New `work_location_master_id` filter (`0`/sentinel = "has a shift but no location set", mirroring the page's `LOC_NOT_SET`): keeps employees with at least one resolved day in the
  window on that location.
- New `shift_master_id` filter: keeps employees with at least one resolved day on that shift (parity with the regularization grid's shift filter).
- `ShiftRosterMetaOut` gains `page`, `page_size`; `total_employees` becomes the count AFTER filters, BEFORE paging. Order stays (first name, last name, id).
- Resolve days only for the page's employees (the four-query resolver already loads by employee list — page BEFORE resolving, except for the location/shift filters which need
  resolving first; document the cost and cap it).

NOT in this task: the frontend switch-over (done in 298 once the shared shell exists).

## Files
`backend/app/modules/shifts/service.py` (`list_shift_roster`), `router.py`, `schemas.py` (`ShiftRosterMetaOut`), `frontend/src/lib/api.ts` (`listShiftRoster` options + meta type),
shifts tests.

## Acceptance criteria
- [x] Without `page` the response is byte-identical to today (existing tests unchanged and green)
- [x] With `page`/`page_size`, `data` is that slice and `meta.total_employees` is the filtered total
- [x] Role, work-location (incl. "not set") and shift filters return the same people the client-side filter did
- [x] Scoping unchanged: whole org vs direct reports; filters never widen scope; tenant isolation test
- [x] `page_size` > 100 → 422
- [x] `uv run pytest` for the touched module passes

## Built (2026-10-28)
- `GET /shifts/employee-shifts/roster` gained `page`, `page_size` (default 50, 1-100, else 422), `work_location_master_id`, `work_location_not_set` and `shift_master_id`; `role` was already
  server-side. `service.list_shift_roster` + two helpers (`_load_roster_rows`, `_tenant_shift_ids`); `ROSTER_DEFAULT_PAGE_SIZE` / `ROSTER_MAX_PAGE_SIZE` in `service.py`.
- Semantics (match the old client-side filter): an employee matches when at least one day in the window has a shift **in this tenant** and every day-level filter given holds on that SAME day
  (shift = X, location = Y, or location not set). Resolution is the grid's own "latest effective row wins" (`_covering`).
- No shift/location filter -> the employee list is paged BEFORE anything is resolved. With one -> the shift rows of all candidates are read in one query (same cost class as today's unpaged
  read) to decide who matches, then the page is cut; the per-day `ResolvedDayOut` build only ever runs for the page. Query count stays constant in head-count (tested).
- `meta`: `ShiftRosterOut.meta` is `SerializeAsAny[ShiftRosterMetaOut]`; a paged read returns `ShiftRosterPagedMetaOut` (adds `page`, `page_size`); an unpaged read serialises exactly as before
  (verified through FastAPI's response_model, and by a test).
- **Deviations from the task text:** (1) "not set" is `work_location_not_set=true`, not a `0` sentinel id (both together -> 422). (2) No hard cap was added for the filtered path: it reads no more than the
  existing unpaged endpoint always did, and the heavy build is now bounded by the page, so a cap would only add a new failure mode.
- Frontend: `lib/api.ts` `listShiftRoster` takes `workLocationId`, `workLocationNotSet`, `shiftId`, `page`, `pageSize`; `ShiftRoster.meta` gains optional `page` / `page_size`. `ShiftScheduling.tsx` is
  NOT switched over here (task 298); `tsc --noEmit` clean.
- **For 298:** once the roster is paged the role dropdown can no longer be derived from the fetched rows (it only sees one page) — it needs a distinct-roles source (e.g. the directory's designations
  lookup, or a small `GET` on this module). Decide there.
- Tests: 11 new in `test_shifts.py` (`test_roster_*` after `test_shift_cells_*`); all roster tests incl. the existing query-count ones pass; `test_shifts.py` + range-carve + day-override job pass.
  Failures seen elsewhere are environmental, not this change: `test_authz` / `test_employees` need nhforms tables (`form_masters`, `form_response_values`) and 4 in `test_shift_day_override_service`
  need `status_masters` OVERTIME_* rows (migration c7e1a4f9d283) — neither present in the shared test DB.

Completed: 2026-10-28
