---
task: 284
title: Regularize many employees — register multi-select and bulk modal
status: done
depends_on: [282, 283]
---

# 284 — Regularize many employees — register multi-select and bulk modal

## Scope
HR ticks employees on the HR attendance register, clicks **Regularize**, and a modal applies one date range + one status (283's picker) to all of them. Backend is 282; the status
control is 283's `RegularizeStatusPicker`. Entry point: `frontend/src/dashboards/hrManager/Attendance.tsx` (the register). Visible only to callers who can regularize on behalf
(the same `APPROVE` + `UPDATE` on ATTENDANCE check `EmployeeAttendanceTab` uses; a reporting manager must not see it).

### Register
Checkbox column (header checkbox = select the rows on the current page; a "Select all N matching" link is **not** in v1 — the cap is 50). A selection bar appears when ≥ 1 row is
ticked: "3 selected · Regularize · Clear". Selection survives paging/filtering within the screen but is capped at 50 (a 51st tick shows an inline note). Clearing on success.

### Bulk modal — `RegularizeBulkModal.tsx`
```
Regularize attendance — 12 employees                                         ✕
From [DateField] To [DateField]   Mark as [status picker (283)]   shift/custom times
Reason [select]   Note* [text]   (override reason only when a ticked day is locked)
Summary: "86 will be regularized · 2 locked · 140 skipped · 9 blocked"
Per-employee accordion: ☑ Name (code) — 8 of 21 days   [expand → per-day rows as in the single modal]
[Cancel] [Regularize 86 days for 11 employees]
```
Behaviour: preview via `POST .../regularize-range/bulk/preview` (debounced, `AbortSignal`, `latestOnly` lane); candidate days pre-ticked; an employee header checkbox toggles all that
employee's candidates; employees with nothing to do are collapsed and shown greyed with the reason counts. Apply sends the explicit `targets`; result screen per employee (applied / skipped /
failed with the day messages), **Review again**, **Done**; refresh the register when closing after any applied. Whole-request errors (403/404/422) show the server `detail` inline.
The 1,000 employee-day cap: if employees × span exceeds it, say so inline and don't call the API.

### Conventions
Tailwind only; shimmer skeleton (`ShimmerTable`/`ShimmerList` primitives, header + rows matching the real layout) for the preview body; `DateField`; `secureFetch`; `useConfirm` is not needed
(no destructive step). Share row/table pieces with `RegularizeRangeModal.tsx` instead of copying them — extract if they are inline today.

## Files
`frontend/src/dashboards/hrManager/Attendance.tsx`, new `frontend/src/dashboards/shared/RegularizeBulkModal.tsx`, `frontend/src/lib/api.ts` (`previewRegularizeBulk`, `regularizeBulk` + types).

## Acceptance criteria
- [x] Checkbox column and selection bar only for callers who can regularize on behalf; cap of 50 enforced
- [x] Modal preview lists every selected employee with per-day outcome; candidates pre-ticked; per-employee toggle works
- [x] Apply sends only ticked days; per-employee result screen; partial failure keeps failed days retryable
- [x] Register reflects the new statuses after closing; selection clears on success
- [x] Shimmer skeleton while previewing; usable at narrow widths (body scrolls, no page-level horizontal scroll)
- [x] `npx tsc --noEmit` clean; `eslint` adds no errors over the base
- [ ] Manual smoke check against a local stack — or recorded as skipped by decision

## As built (2026-10-27)
`RegularizeBulkModal.tsx` (per-employee collapsible blocks, header checkbox with indeterminate state, per-employee result list, "Review again") and a checkbox column + selection bar in
`hrManager/Attendance.tsx` (four static `ATTENDANCE_SELECT_*` grid strings so Tailwind sees them; skeleton rows get the extra track). Selection is a `Map<employeeId, BulkEmployee>`
capped at `REGULARIZE_BULK_MAX_EMPLOYEES`. Shown only with APPROVE + UPDATE on ATTENDANCE. Deviation: the register's own range pre-fills the modal (clamped to today); a "Select all N
matching" link is not built (per the task).
Verified: `npx tsc --noEmit` clean; eslint on `Attendance.tsx` shows the same 3 errors as the base (set-state-in-effect etc.), none new. **Not verified:** the running UI — the smoke
box stays unchecked. The preview skeleton is a list of `ShimmerRow`s (the employee-block layout), not a `ShimmerTable`.

Completed: 2026-10-27
