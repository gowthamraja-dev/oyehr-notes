---
task: 259
title: Roster and "my shift for a date" expose the swap (day_override marker)
status: ongoing
depends_on: [254, 258]
---

# 259 — Roster shows swapped days

Plan: `.plans/shift-day-swap-plan.md` §3 "Roster field", §4. Repo: `workspace-1/hrms/`.

## Scope
After 254 the roster's OFF / working answer is already correct, but HR cannot tell *why* a Saturday differs from the weekly rule.
Carry the reason through.

Backend (`backend/app/modules/shifts/`):
- `schemas.py`: add `day_override: Literal["WeekOff", "Working"] | None = None` to the roster cell model and to `ResolvedDayOut`
  (next to `is_week_off`, line ~373; document that it is the override that decided `is_week_off`, None when the weekly rule decided).
- `service.py`: the roster builder and `resolve_employee_day` set it from the **same** `pick_day_override` result 254 already loads
  once per request — no new query, no second matcher. `/shifts/me/{date}` (employee app) gets the field for free; do not change its other fields.
- Employee app (`employeeapp/`): **no change** — an additive nullable field on `/shifts/me/{date}`; note in the completion line that
  the app ignores unknown fields.

Frontend (`frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, types in `src/lib/api.ts`):
- Cell/header marker when `day_override` is set: a small "Swapped" badge with a tooltip "Working Saturday — swapped, <reason>" /
  "Week off — swapped". Reason comes from the existing list call (`listDayOverrides`) for the visible window, fetched once per range, not per cell.
- "Shifts this week" counter keeps counting working days only (a swapped-off day is OFF).
- Tailwind only; 10px spacing; no layout shift when the marker appears.

## Carried over from task 258 (done)
- `listDayOverrides(from, to, { shiftId?, includeArchived?, signal? })` is in `src/lib/api.ts`; the roster window (≤ 62 days) is inside the API's 460-day limit. Default (no `includeArchived`) returns live swaps only, which is what the roster marker wants. With `shiftId` it returns that shift's own swaps plus the all-shifts ones. Fetch once per visible range, not per cell.
- Reuse `weekdayShort`, `dayTypeLabel` (Week off / Working) from `AttendanceShifts_components/utils/daySwaps.ts` for the tooltip wording, and `formatDDMMMYY` for dates.
- A `DayOverride` carries `reason`, `day_type`, `shift_name` (null = all shifts), `recalc_status`; the roster cell needs only `day_override` from the backend (task 259's own backend field) and the `reason` from this list.

## Files
- `workspace-1/hrms/backend/app/modules/shifts/schemas.py`, `service.py`
- `workspace-1/hrms/backend/app/tests/modules/test_shifts.py`
- `workspace-1/hrms/frontend/src/lib/api.ts`, `workspace-1/hrms/frontend/src/dashboards/hrManager/ShiftScheduling.tsx`

## Acceptance criteria
- [ ] Roster cell on a swapped date: `is_week_off` follows the override and `day_override` is `WeekOff`/`Working`; on an unswapped date `day_override` is `null`
- [ ] A shift-specific swap marks only that shift's employees; an org-wide swap marks everyone; another tenant's swap never shows
- [ ] `GET /shifts/me/{date}` returns `day_override` and a correct `is_week_off` on a swapped date
- [ ] Roster endpoint does not issue per-employee-day override queries (assert query count stays flat as employees grow, as the 254 batching test does)
- [ ] The marker and tooltip render in the grid and the layout does not shift
- [ ] `uv run pytest app/tests/modules/test_shifts.py` green; frontend `tsc`/lint no new errors
