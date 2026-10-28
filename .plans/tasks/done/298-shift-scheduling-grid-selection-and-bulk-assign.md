---
task: 298
title: Shift Scheduling — Excel-style cell selection and bulk assign on the shared grid
status: done
depends_on: [295, 296, 297]
---

# 298 — Shift Scheduling: cell selection + bulk assign on the shared grid

## Scope
Rebuild `hrManager/ShiftScheduling.tsx`'s grid on the shared shell (297) and add the regularization grid's interaction model:

- Drag / shift-click / ctrl-click / row & day headers / arrows / Esc / ctrl+A over roster cells (selectable = not in the past-locked state the roster already shows; the server
  re-classifies on apply anyway).
- A selection bar (like the regularize one) with **Assign shift** → opens the existing `BulkAssignShiftModal` in a "cells" mode: pick shift, work location, holiday calendar,
  skip-week-offs, overwrite-manual → **Preview** (task 295 preview, shows will-change / skipped by reason per employee) → **Apply** (task 295 apply; partial success shown as
  today's range result, `copyResult` dialog pattern).
- Keep what exists: row checkboxes + whole-week/month assign, Copy last week, single-cell click-to-assign (a plain click with no drag still opens the one-cell modal — decide
  and document how a click vs a one-cell selection is told apart; recommended: single click selects, double-click / Enter opens the assign modal), legend, day swaps overlay, KPIs.
- Switch to server-side role / location / shift filters and paging from 296 (`listShiftRoster` with `page`); remove the client-side `filteredRoster` filtering. The Filters drawer
  and search stay.
- `lib/api.ts`: `previewShiftCells`, `setShiftCells`, types; `lib/gridSelection` / `useGridSelection` used as-is.

NOT in this task: shared-shell extraction (297), backend (295/296), docs (299).

## Files
`frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, `frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`, `frontend/src/lib/api.ts`.

## Acceptance criteria
- [ ] Drag-select a ragged set of cells across employees and dates, assign one shift: preview matches what apply then writes
- [ ] Locked / week-off / outside-employment days are reported, not written
- [ ] Row ticks, week/month assign, Copy last week, legend, day-swap overlay and KPIs still work
- [ ] Role / location / shift filters and paging are server-side; changing a filter resets to page 1 and clears the selection
- [ ] Manager (direct reports only) and HR (whole org) both work; a manager cannot select outside their team
- [ ] Shimmer skeleton mirrors the real grid; `npx tsc --noEmit` and eslint clean
- [ ] Browser check on a real tenant (needs a dev server — ask the user first)

## Progress (2026-10-28) — built, NOT yet checked in a browser (the user is doing the UI check)
Frontend only (the backend was 295 / 296). Files: `hrManager/ShiftScheduling.tsx`, `shared/BulkAssignShiftModal.tsx`, `shared/SelectableGrid.tsx` (extended), `lib/api.ts`.

Built:
- The roster grid is now `SelectableGrid`. Drag / shift / ctrl-click, row and day headers, arrows, Esc, ctrl+A all work as on the Regularization grid (same `useGridSelection`). Only today onward is selectable; past
  cells stay dimmed. A sticky bar shows "N cells · M employees" with **Assign shift to N cells** and Clear.
- **Cells mode** in `BulkAssignShiftModal` (`cells={{targets}}`): shift list, "change work location only", location / calendar, "skip weekly offs", "keep days someone set one by one" (= `overwrite_manual:false`),
  and a LIVE preview (debounced `POST …/cells/preview`) — "N days will change · left as they are: …". Assign is disabled until a fresh preview shows >= 1 day that will change; a stale preview (inputs changed since) can never enable it.
  Apply = `PUT …/cells`; a result with skips or failed employees opens `RangeResultBody` + a "could not be updated" list.
- Server-side filters and paging: role, work location (incl. "Not set"), shift (new select), 50 per page; `meta.total_employees` drives "N shown", the pager and the Direct-reports KPI. The page rides on the list it belongs
  to (`listKey`), so any filter or period change reads as page 1 with no double fetch; a list that shrinks under the current page steps back to the last page.
- Role options: `getRoleAggregates()` (every role in the org), falling back to the roles on the current page for a caller who may not read it.
- Copy last week still covers EVERYONE the filters match (not just the page): it pages through the roster (one-day window, 100 per page) to collect ids, then copies in chunks of 500 and merges the results.
- Kept: row checkboxes + whole week / month assign, per-row range button, legend, day-swap markers (cell + header), WFH / SWAP badges, KPIs, Filters drawer + chips, breadcrumb period controls, every `data-testid`.
- Shell additions (all optional, defaults untouched): `gridCols` / `gridMinW`, `renderCorner`, `renderRowHead`, `dayHead`, `onDoubleClick`, `emptyText` as a node; `GridRowsSkeleton` takes `cols`.

Deviations from the task text:
- A plain click now SELECTS; **double-click** (or **Enter** on the active cell) opens the one-cell assign modal — the recommended option in the task.
- Live preview instead of a separate Preview button / step.
- The three KPIs besides "Direct reports" are computed over the page on screen; they say "· this page" when the list is longer than the page.
- Visual: rows use the shared shell's spacing (7px row padding, two-line day headers, today highlighted) rather than the old page's; the first-column width and month column minimum are kept via `gridCols` / `gridMinW`.

Verified without a browser: `tsc --noEmit` and eslint clean on all touched files; every pre-existing `data-testid` and `data-*` attribute of the page is still present; the Regularization grid's class tokens and attributes
are still identical to before the extraction (re-run after extending the shell). The backend contract is covered by 12 + 11 tests from 295 / 296.

Left to tick (browser): drag-select a ragged set of cells across employees and dates and assign one shift — preview matches what is then written; locked / week-off / outside-employment days are reported, not written;
row ticks, week / month assign, Copy last week (incl. with a filter active and more than one page), legend, swap overlay, KPIs; filters and paging server-side (changing a filter returns to page 1 and clears the
selection); manager (direct reports) and HR (whole org); skeleton -> content with no shift; double-click and Enter open the single-cell modal.

Browser check done by the user outside this session (not re-verified by Claude); moved to done on the user's instruction.

Completed: 2026-10-28
