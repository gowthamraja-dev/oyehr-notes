---
task: 259
title: Roster and "my shift for a date" expose the swap (day_override marker)
status: done
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
- `workspace-1/hrms/backend/app/modules/shifts/schemas.py`, `service.py`; `app/services/calendar_resolver_service.py` (+ `swapped_override`, `week_off_with_swap`, `_rule_rows`)
- `workspace-1/hrms/backend/app/tests/modules/test_shifts.py` (3 new, 1 extended), `test_calendar_resolver_batch.py` (2 new)
- `workspace-1/hrms/frontend/src/lib/daySwapMarker.ts` (new, pure), `src/lib/api.ts`, `src/dashboards/hrManager/ShiftScheduling.tsx`

## Acceptance criteria
- [x] Roster cell on a swapped date: `is_week_off` follows the override and `day_override` is `WeekOff` / `Working`; on an unswapped date it is `null` (also against the live API: October 2026, four swapped Saturdays marked, every other day null)
- [x] A shift-specific swap marks only that shift's employees; an all-shifts swap marks everyone; another tenant's swap never shows; a cell with no shift is never marked
- [x] `GET /shifts/me/{date}` returns `is_week_off` and `day_override` (see the first deviation below: it returned neither before); checked through the real `getMyShiftForDate` against the live API
- [x] The roster issues no per-employee-day swap queries: the query count for 62 employees x 31 days equals the count for 2 x 7 with swaps present (`test_roster_swap_marker_adds_no_per_employee_queries`)
- [ ] The marker and tooltip **render in the grid** and the layout does not shift: **not seen in a browser**. What is verified: the cell and header JSX typecheck, lint and build; every input to it is correct against the live API (the roster cells, the swap list, the exact tooltip `"Working Saturday — swapped, Diwali bridge"` and header note); the marker is positioned absolutely in the corner opposite the existing WFH badge, so it cannot move anything. The roster component itself was not rendered (it needs the full app context and data)
- [x] `uv run pytest app/tests/modules/test_shifts.py` green (with the new tests); `tsc --noEmit` 0 errors; `eslint` clean on the touched frontend files; `npm run build` passes
- [x] Mutation check, 6 deliberate backend bugs, each caught: a swap marked although it only repeats the rule (2 ways); a shift-less cell given the all-shifts swap; the employee's own day dropping the swap, or ignoring it for `is_week_off`, or reading swaps without the tenant. Frontend helper: a removed swap still counting, and the all-shifts swap beating the shift's own, both caught

## Deviations from the task text (found by reading the code)
- **`/shifts/me/{date}` did not carry `is_week_off` at all** (the task said it "gets the field for free"): `MyShiftOut` has only the shift's identity and times and never used the roster model. Both `is_week_off` and `day_override` are now added to it, additively with defaults; `week_off_with_swap` (two queries: the swap and the weekly rule) feeds it. The employee app is unaffected: it only calls `/shifts/me` (the history list), never the dated endpoint. The web `getMyShiftForDate` type has the two new optional fields; no web screen shows them yet.
- **`day_override` is set only when the swap changed the day**, i.e. flipped week-off vs working compared with the weekly rule (`swapped_override`, one definition shared by the roster and the employee's own day). A swap that merely repeats the rule (week off on a day already off) is not "swapped" and shows no marker. A half-day rule does not count as a week-off here. The task text said "None when the weekly rule decided", which this refines.
- **The "Shifts this week/month" counter did NOT already count working days only** (the task said "keeps counting"): it counted every cell with a shift id, and a week-off cell keeps its shift id, so off days were counted (this is SHF-D2 in `.plans/attendance-shifts-leave-holidays-todo.md`). It now counts `shift_master_id != null && !is_week_off`: against the live API, 124 cells with a shift became 100 working (4 employees x 25 working days). This changes a number HR sees even where no swap exists.
- Existing test `test_roster_batched_read_equals_the_per_day_resolvers` hand-builds the expected cells; its reference now computes `is_week_off` / `day_override` with the per-date `week_off_with_swap`, and its world got swaps (a both-shifts flip, a one-shift flip that only repeats the rule for the other, a shift-only Sunday, another tenant's), so the parity check really covers the new field (it asserts some cells are marked).

## Found while verifying (outside this task's scope)
- **My own tests from 255–257 were not isolated** (`test_shift_day_overrides.py`, `test_shift_day_override_service.py`): they counted and listed `ShiftDayOverride` rows across the whole table, which only passed because nothing else had committed any. 23 of them failed once my end-to-end run had left committed swaps in the shared test database. They are now scoped to the test's own tenant (`_all(db, cdp)` / `_live(db, cdp)`); 78 pass with that data still present.
- **Upstream was merged into workspace-1 between 258 and 259** (attendance bulk import, FCM push, visitor QR pass, file-import engine; `HEAD` is `14dc5be`). All of my edits survived. No new caller of the week-off matcher came with it (the bulk import goes through `recompute_attendance_day`, so it honours swaps). The migration chain now has **three HRMS heads** (`a4c9e2d7b350`, `c3a7e1d9f402` and mine, `d5e9a1c7f302`, which still chains from `b83f6d1c0e47`); `scripts/migrate.py ... heads` handles that, and merging them is for whoever owns the merge.
- **Two failures that are not mine:** `test_visitors.py::test_manager_approves_an_employees_invite` and `test_reimbursements_oversight.py::test_read_shows_a_manager_only_their_team_and_update_the_organisation` fail identically on a clean upstream `HEAD` checkout (a separate worktree, none of my changes) against the same database. Two dashboard tests that failed before because "yesterday" was a Sunday pass today, confirming that they were weekday-dependent.
- Full backend suite: 98 failing (2,744 passing, +123 on the post-257 run); every failure is in the pre-existing set, the two above, or was fixed by the calendar.
- `frontend/.env.dev` is modified in the working tree (`NEXT_PUBLIC_API_URL` now `http://localhost:8000`): not mine, left alone. `stash@{0}` holds a snapshot of my tracked changes taken at 10:09 today against the old `HEAD`, from whatever pulled the merge; left alone too.

## Decisions
- The marker is a small amber `SWAP` badge (a dot in the month view) at the cell's top-left, mirroring the WFH badge at the top-right; the column header gets an amber dot with a hover listing every live swap on that date by scope. The hover on a cell is `"Working Saturday — swapped, <reason>"` / `"Week off — swapped, <reason>"`, then the cell's usual hover text.
- The reason comes from one `listDayOverrides(from, to)` call per visible window, resolved with the backend's own precedence (the shift's swap, else the all-shifts one) in `lib/daySwapMarker.ts`. If that call fails the marker still shows and only the reason is missing.
- Dates the roster marks come from the roster response, not from the swap list, so a swap that applies to nobody on screen marks nothing.

Completed: 2026-10-27
