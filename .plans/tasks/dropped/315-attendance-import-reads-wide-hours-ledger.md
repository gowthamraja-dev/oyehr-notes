---
task: 315
title: (Later) Attendance import reads the wide hours ledger (In/Out per date)
status: dropped
depends_on: [310, 311, 312, 316]
---

# 315 — Read the wide `hours_ledger` (cell = in_out) as an import

## Scope
**Optional, after 310–314 ship.** HR may prefer editing the grid (one row per employee, a pair of columns per date) over the long daily log. Paths
relative to `workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md`.

Not covered, deliberately: `attendance_ledger` (status codes only — no times; a `P → A` edit is a regularization/leave decision, point HR to the
Regularization grid) and `monthly_summary` (totals). The `hours_ledger` with `cell=hours` (`8:45`) has no clock times either, so it is not importable.

## The shape to read (`attendance_export/hours_ledger.py`, `file_export/writers.py`)
* XLSX: meta block (incl. the period), group band (`01 Mon` / `01-Oct Mon` over each In/Out pair), then a header row `Department | Employee Name |
  Employee ID | Shift | In | Out | In | Out … | Days worked | …totals`. CSV: header labels are `01 In`, `01 Out`, … (day number only within one month,
  `01-Oct In` across months) — **no month or year in a CSV**.
* Cell content: `HH:MM` (24 h, employee's zone), `?` under Out for a missing clock-out, and a day with no punch shows its code (`A`, `WO`, `H`, `L`, `NS`, `YTC`)
  **under In**, nothing under Out.

## Approach (decide before building; the design here is a proposal)
1. Reuse the `ImportHandler.normalise_upload` hook and the `layout` option introduced by task 316 (a second layout, `hours_grid`, next to 316's `grid`) to **un-pivot** the
   wide sheet into `Employee ID | Date | In | Out` rows *before* staging, so validation, commit, settle and undo (310–312) are reused untouched. No new tables.
2. Dates: from the XLSX band row + the meta block's period; for a CSV (or any file where the period cannot be derived) the wizard asks HR for the
   **From date** and the engine maps the Nth column pair to From + N days, rejecting the file if the pair count does not match the range.
3. Cells that are a code (`A`, `WO`, `H`, `L`, `NS`, `YTC`) or `?` are blank times → the same "keep current value / left as is" rules as 311.
4. `max_rows` is 5,000 **after** un-pivoting (62 days × 80 employees already exceeds it) — raise the handler's `max_rows` or reject early with a clear
   sentence; do not silently truncate.
5. Detection: `detected.export_type = "hours_ledger_in_out"`; the wizard (313) shows the period picker only for this type.

## Files
`backend/app/modules/file_import/handlers.py` (hook), `backend/app/modules/file_import/router_factory.py` (call it; accept `from` for the period),
`backend/app/modules/attendance_import/parsing.py` or a new `unpivot.py` beside it, `frontend/src/dashboards/shared/ImportAttendance.tsx` /
`FileImportWizard.tsx` (period field), tests, docs sections from 314.

## Acceptance criteria
- [ ] An in_out `hours_ledger` XLSX and CSV from the real exporter, unchanged, stages as all-Unchanged under `Update`
- [ ] An edited In/Out cell becomes exactly one changed day; a code cell (`A`, `WO`…) is never read as a time
- [ ] A CSV without a period is refused until HR supplies From; a mismatched column count is refused with a sentence
- [ ] Row limit behaves as decided in step 4
- [ ] Totals columns and the Legend sheet are ignored
- [ ] Tests in `test_attendance_reupload.py` extended and green; docs updated

Dropped: 2026-11-02 — not started; shelved by the user ("leave it for now"). Moved out of `ongoing/` rather than deleted; move it back to restart. Design: `.plans/attendance-export-reupload-plan.md`.
