---
task: 243
title: Assign-shift modal: this day / week / range / month + multi-select rows
status: done
depends_on: [241]
---

# 243 — Assign-shift modal: this day / week / range / month + multi-select rows

## Scope
Reported: "HR manager should apply shifts for a month or week — right now it is day-wise."
Frontend over the task-241 endpoint (add `setEmployeeShiftForRange` to `api.ts`):
- `BulkAssignShiftModal`: **Apply to** segmented control — This day · This week · Custom range ·
  Whole month; weekday chips (default all 7; the shift's weekly offs are skipped via the
  "Skip weekly offs" checkbox, default on); `DateField` for custom dates; past dates clamped like the grid.
  Result panel reuses the skipped-list UI (now per-date reasons).
- `ShiftScheduling.tsx`: checkbox per employee row + header select-all; "Assign shift to selected"
  button opens the modal with `employees[]`; row-level "Assign week/month" for one employee.
- Directory's existing bulk assign keeps the open-ended effective-date mode (don't break it).
NOT in scope: month grid view (task 244), copy-last-week (task 245).

## Files
`hrms/frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`,
`hrms/frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, `hrms/frontend/src/lib/api.ts`.

## Acceptance criteria
- [x] One employee, one week → 5–7 cells updated in one request; grid refreshes
- [x] Multi-select N employees × month works; skipped dates reported with reasons
- [x] Directory bulk assign (effective-date mode) unchanged
- [x] Modal keeps header/footer chrome static per CLAUDE.md; shimmer, not "Loading…" text
- [x] `tsc`/eslint clean; browser smoke

## Implementation notes (2026-10-24)
- `api.ts`: `setEmployeeShiftForRange` + `SetEmployeeShiftForRangeInput/Result`, `RangeSkipReason`.
- `BulkAssignShiftModal`: `singleDate` prop replaced by `schedule={{anchorDate, applyTo}}` (only ShiftScheduling passes it). Segmented
  "Apply to" (This day · This week · Custom range · Whole month), weekday chips (default all 7), "Skip weekly offs" (default on),
  `DateField`s for a custom range (`min` = today). Week / month windows are clamped to today ("Starts today"). One employee × one day
  still goes through `PUT /day`; everything wider through `PUT /range` (one request). Directory mode (no `schedule`) is untouched
  (`POST /bulk`, effective date). "Change work location only" (task 242) now works for any scope.
- Result panel after a range apply lists skipped dates per employee by reason. It only opens when something *unexpected* was skipped
  (locked, outside employment, no shift to keep); routine skips (weekly off, already set) are summarised in the toast instead.
- Modal chrome: header and footer are now outside the scrolling body; the loading state is a shimmer body (no "Loading shifts…" text).
- `ShiftScheduling`: per-row checkbox + header select-all (indeterminate), a selection bar ("N selected · Assign shift to selected"),
  a per-row week/month button. Selection only acts on rows still shown (a filter that hides a ticked row drops it from the batch) and
  is cleared after a selection-driven assign. Employee column widened (240px min) for the checkbox + button.
- Not changed: `overwrite_manual` is always sent as the server default (true) — no UI for protecting hand-set single days.

## Browser smoke (2026-10-24)
Headless Chrome vs a local stack (API :8001 on local postgres, Next copy :3001, remote backend never touched), HR Manager login. 26/26 checks:
past clamp ("Starts today", custom-range `min`), shimmer + static chrome while loading, one employee × one week → one `PUT range` and 7 GEN cells,
Mon–Fri only → 5 cells, 2 selected × whole month → one request, 50 employee-days, Meera's 10 days after her relieving date reported, Rohan stored as ONE
01–30 Nov row, single cell → `PUT day`, Directory modal unchanged (Effective date, no Apply-to, `POST bulk`).
