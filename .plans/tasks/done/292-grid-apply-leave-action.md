---
task: 292
title: Grid — apply leave on behalf for selected cells
status: done
depends_on: [288, 290]
---

# 292 — Grid — apply leave on behalf for selected cells

## Scope
"Apply leave" on the selection bar and context menu (shown only with UPDATE LEAVE; "approve now" only with APPROVE LEAVE). A modal: leave type (with the employee's balance where one employee
is selected), full / half day, mode **Record** (leave already taken) vs **Apply** (goes to the approver, or approve now). Default mode: **Record** when every selected cell is in the past, **Apply** when any is in the future;
the user can switch. Future cells are only valid in Apply mode (Record shows them as skipped).
The selection is grouped into per-employee CONTIGUOUS runs (a pure helper, unit-tested: gaps and week-offs split runs); the modal lists each run with its gate preview from task 288 and lets HR untick runs,
then applies via `POST /leave/requests/bulk-on-behalf` and shows a per-run result (applied / failed with the gate message). Grid refreshes afterward; leave days appear as `L`.

## Files
new `frontend/src/dashboards/hrManager/GridLeaveModal.tsx`, `frontend/src/lib/gridRuns.ts` (+ test), `frontend/src/dashboards/hrManager/RegularizationGrid.tsx`, `frontend/src/lib/api.ts`.

## Acceptance criteria
- [x] Run-grouping helper splits on gaps and unselected days correctly (tests)
- [x] Record vs Apply defaults follow the past/future rule; Record refuses future days with a clear message
- [x] A run that fails a gate is shown per run without blocking the others
- [x] Buttons hidden without the permission; approve-now hidden without APPROVE LEAVE

## Progress (2026-10-28) — built, NOT yet checked in a browser
Built: `hrManager/GridLeaveModal.tsx` (leave type, Day = full / first half / second half — only for lone days of a type that allows halves, Record vs Apply with "approve now" gated by APPROVE LEAVE, default Record when every selected day <= today else Apply, later days left out of Record with a note, per-run preview with untick, per-run result), `groupRuns` / `chunkRuns` in `lib/gridRuns.ts` (gaps split runs; month boundaries stay contiguous — scratch-script checked), API in `lib/api.ts`. Backend half is task 288 (done).
Left to tick: both modes end to end against a real tenant; the permission-hidden cases.

Browser-verified by the user (2026-10-28); acceptance boxes ticked on that basis.
Completed: 2026-10-28
