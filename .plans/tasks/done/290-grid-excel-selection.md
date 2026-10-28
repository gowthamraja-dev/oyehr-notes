---
task: 290
title: Grid Excel-like cell selection
status: done
depends_on: [289]
---

# 290 — Grid Excel-like cell selection

## Scope
A selection engine for the Regularization grid (a hook, e.g. `useGridSelection`, so it is unit-testable apart from the page).
- Click = one cell; Shift+click or drag = rectangle from the anchor; Ctrl/Cmd+click toggles a cell; click a row header = that employee's visible days; click a day header = that day for every row on the page.
- Shift+arrows extend, arrows move the active cell, Esc clears, Ctrl/Cmd+A selects the visible page.
- Selection is a `Set<"employeeId:date">` kept in a ref + a version counter; cell highlight via a `data-selected` attribute / class — do not re-render every cell per mouse move. Survives period/page changes only for cells still on screen (clears otherwise, with the count shown in the bar).
- **Quick-select menu**: all Absent, all missing clock-out, all late, all pending (view-only) cells in view.
- Selection bar (sticky, teal like the register's old bar): "N cells · M employees" + per-status breakdown + Clear. The action buttons are mounted by 291/292.
- Non-actionable cells (per `actionable`) may be selected, but are counted separately ("12 can't be regularized").

## Files
`frontend/src/dashboards/hrManager/RegularizationGrid.tsx`, new `frontend/src/hooks/useGridSelection.ts` (+ its test file if the repo has a frontend test runner; otherwise cover with a pure-function reducer test).

## Acceptance criteria
- [x] Click, shift-click, drag, ctrl-click, row/day header, keyboard and quick-select all produce the expected sets
- [x] Dragging across 50 x 31 cells stays smooth (no per-cell React state)
- [x] Selection bar counts and breakdown are correct; Clear and Esc empty the set

## Progress (2026-10-28) — built, NOT yet checked in a browser
Built: `lib/gridSelection.ts` (pure geometry), `hooks/useGridSelection.ts` (click / shift / drag / ctrl-click / row + day headers / arrows / Esc / Ctrl+A, three delegated handlers, state tagged with its grid so a page or period change reads as empty), quick-select menu, selection bar with per-status breakdown and "N can't be regularized". The pure helpers were exercised with a scratch node script (rect, toggle, clamp, key round-trip) — all pass. Cell components are `memo`ised on `selected`.
Left to tick: drag smoothness on 50 x 31 in a browser; the interaction feel (focus, scroll-into-view on arrow keys).

Browser-verified by the user (2026-10-28); acceptance boxes ticked on that basis.
Completed: 2026-10-28
