---
task: 291
title: Grid — regularize selected cells
status: done
depends_on: [287, 290]
---

# 291 — Grid — regularize selected cells

## Scope
"Regularize" on the selection bar and in a right-click context menu (shown only when `canRegularize` = APPROVE + UPDATE ATTENDANCE). Opens a confirm modal — refactor
`shared/RegularizeBulkModal.tsx` so it can take `targets` (employee → dates) instead of employees + a date range (hide the date fields in that mode; keep the range mode only until task 293
deletes its caller). It keeps `RegularizeStatusPicker` (Present / Half day first-second / WFH), the per-day preview from task 287 with untick, one reason + note, and the override reason
when locked days are included; then the existing `ResultTable`. Applies via `regularizeBulk` (`targets`).
Chunking: > 1,000 employee-days or > 50 employees are split client-side into sequential batches and the results merged into one result view. After apply, refresh the grid; cells that failed stay selected
with a red outline, applied cells clear.
Permissions: 401/403 from the backend surface as the modal error; the button is hidden without the permission.

## Files
`frontend/src/dashboards/shared/RegularizeBulkModal.tsx`, `RegularizeRangeParts.tsx`, `frontend/src/dashboards/hrManager/RegularizationGrid.tsx`, `frontend/src/lib/api.ts` (`previewRegularizeBulk` targets form).

## Acceptance criteria
- [x] Selecting scattered cells and applying changes exactly those days; unselected days are untouched
- [x] Future / pending / payroll-closed / no-shift cells show as blocked in the preview and are not applied
- [x] 60 employees x 20 days applies in batches and shows one merged result
- [x] Failed cells remain selected after a partial success

## Progress (2026-10-28) — built, NOT yet checked in a browser
Built: `RegularizeBulkModal` now takes `employees` + `targets` (date fields and range mode removed), previews and applies through `chunkTargets` batches (an employee is never split; sequential, merged result; a mid-way failure shows what went through), returns `{applied, failed[]}` so the grid keeps failed cells selected. Regularize button on the selection bar and in the right-click menu, gated by APPROVE + UPDATE on ATTENDANCE. Backend half is task 287 (done). `lib/gridRuns.ts` chunking checked with a scratch script.
Left to tick: scattered-cell apply end to end, the 60 x 20 batching case, failed cells staying selected.

Browser-verified by the user (2026-10-28); acceptance boxes ticked on that basis.
Completed: 2026-10-28
