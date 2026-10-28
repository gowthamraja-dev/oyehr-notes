---
task: 297
title: Extract a shared selectable-grid shell from RegularizationGrid
status: done
depends_on: []
---

# 297 — Extract a shared selectable-grid shell (pure refactor)

## Scope
`hrManager/RegularizationGrid.tsx` (622 lines) and `hrManager/ShiftScheduling.tsx` (972 lines) duplicate the same chrome. Pull the common parts into
`frontend/src/dashboards/shared/` so both screens compose them, with **no behaviour or visual change** to the Regularization grid:

- period navigation (week / month toggle, prev / next, Today) and the `periodDays` / `shiftAnchor` / `GRID_COLS` / `GRID_MIN_W` constants
- the filter bar (debounced search + department + shift selects + Clear), configurable so a screen can add its own controls (Shift Scheduling keeps its Filters drawer, role and
  location selects)
- the paging footer ("1–50 of N employees", Previous / Next)
- the sticky first column + header row layout with `data-cell` / `data-row` / `data-col` / `data-rowhead` / `data-colhead` attributes and the three `useGridSelection` handlers
- a skeleton built from the `Shimmer*` primitives (header row + N employee rows) taking the column count as a prop

The shell takes: `rows` (`{id, label, sublabel}`), `days`, `renderCell(row, date, {selected, active})`, `isSelectable(key)`, an `actions` slot for the selection bar, and
`legend`. Selection state stays in `useGridSelection` (already generic — do not fork it). Keep cells memoised on their own `selected` flag so a drag re-renders only changed cells.

Rules: Tailwind only, 10px page spacing (`hrms-spacing`), dd-MMM-yy dates, `hrms-responsive-side-panel` / `useIsNarrow` for the narrow-screen notice — no page-local `matchMedia`.
Do NOT touch Shift Scheduling in this task (that is 298) and do not change any API.

## Files
New `frontend/src/dashboards/shared/SelectableGrid.tsx` (+ small helpers/hooks alongside, e.g. `gridPeriod.ts`); `frontend/src/dashboards/hrManager/RegularizationGrid.tsx` (now a
thin consumer).

## Acceptance criteria
- [ ] Regularization grid looks and behaves exactly as before: week/month, filters, paging, drag / shift / ctrl selection, arrows, Esc, ctrl+A, regularize, leave and unlock actions — static equivalence verified (below); BROWSER CHECK STILL TO DO
- [ ] Skeleton still matches the real layout (no layout shift on load) — markup unchanged by construction; confirm in the browser
- [x] `RegularizationGrid.tsx` shrinks substantially (655 → 482 lines); no duplicated period / paging / filter code left in it
- [x] `npx tsc --noEmit` and eslint clean for touched files
- [ ] Browser check on a real tenant (needs a dev server — ask the user first)

## Progress (2026-10-28) — built, NOT yet checked in a browser
Built (all under `frontend/src/`):
- `lib/gridPeriod.ts` — pure: `GridView`, `GRID_VIEW_OPTIONS`, `periodDays`, `shiftAnchor`, `periodLabel`, `parseIso`, `initials`, `GRID_COLS` / `GRID_MIN_W`, the date formatters.
- `hooks/useGridPeriod.ts` — `useGridPeriod()` (view, anchor, days, page; moving or switching returns to page 1) and `useDebouncedSearch(onSettle)` (400 ms).
- `dashboards/shared/SelectableGrid.tsx` — `SelectableGrid` (card + sticky header with `data-colhead` + rows with `data-rowhead` + paging footer + optional `selectionBar` slot),
  `GridPeriodControls`, `GridSearchBox`, `GridSelect`, `GridRowsSkeleton`, `GridTableSkeleton`. Takes rows `{id,label,sublabel}`, `days`, `renderCell`, the selection STATE
  (`{selected, active, handlers}`), `fetching`, `emptyText`, `pager`. A cell must carry `data-cell data-row data-col` itself; the shell wraps each `renderCell` result in a keyed Fragment.
- `dashboards/hrManager/RegularizationGrid.tsx` — now a consumer; keeps what is its own (cell look + legend, what a selection means, fetch, quick select, context menu, the three modals).
  `RegularizationGridSkeleton` is still exported and composes `GridTableSkeleton`.

Decisions:
- The PAGE calls `useGridSelection` and passes the state in (not the shell): the action bar, modals, quick select and context menu all need the selection outside the grid.
- No speculative extension points. Shift Scheduling (298) needs a checkbox column, per-day swap markers in the header, a sticky first column, different widths/padding (its page uses 26px padding and
  a 240px first column; this shell is the Regularization look at the 10px convention). 298 extends the shell for those, and decides whether Shift Scheduling adopts the shared look — expect a small visual shift there.

Verified without a browser:
- `tsc --noEmit` and eslint clean.
- Differential test of the moved period maths (old inline functions vs `lib/gridPeriod.ts`): 800 anchors x week/month x {days, next, previous, label} = 6,400 comparisons, 0 mismatches.
- Markup equivalence: the set of Tailwind class tokens (196) and every `data-*` / `aria-*` / `role` attribute is identical before and after, across page + shell.

Left to tick (needs a dev server for workspace-2 — not started, needs approval; the server already on :3000 serves workspace-1, not this checkout): week/month, filters, paging, drag / shift / ctrl
selection, row and day headers, arrows, Esc, ctrl+A, regularize / leave / unlock, context menu, quick select, skeleton -> content with no shift, narrow-screen notice.

Browser check NOT run — skipped by user decision; the unticked criteria above (behaviour/skeleton in a browser) remain unverified beyond the static equivalence checks.

Completed: 2026-10-28
