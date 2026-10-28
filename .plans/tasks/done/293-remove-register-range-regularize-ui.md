---
task: 293
title: Remove the range / bulk regularize UI from the register
status: done
depends_on: [291]
---

# 293 — Remove the range / bulk regularize UI from the register

## Scope
Requested by the user: remove the "range regularization" button from the HR Manager. Delete, from the Register tab and the drawer:
- the register's checkbox column, the "N selected -> Regularize" bar, `picked` / `bulkOpen` state, the `RegularizeBulkModal` mount and `afterBulk` in `hrManager/Attendance.tsx` (and the grid-column helpers' select flag);
- the "Regularize range" action in `shared/EmployeeAttendanceTab.tsx` and the `onRangeRegularized` plumbing — only if no other dashboard (employee directory drawer) still mounts it; otherwise gate it off for the HR Manager with a prop.
- `shared/RegularizeRangeModal.tsx` if it has no caller left; keep the parts the grid uses (`RegularizeRangeParts`, `RegularizeStatusPicker`).
KEEP: the single-day Regularize / Record-leave icons on register rows (task 204), the Regularization Inbox, the backend range endpoints (the grid uses bulk apply; the single-employee
`regularize-range` endpoints stay until a separate decision).

## Files
`frontend/src/dashboards/hrManager/Attendance.tsx`, `shared/EmployeeAttendanceTab.tsx`, `shared/RegularizeRangeModal.tsx`, `shared/RegularizeBulkModal.tsx` (drop the range-mode branch added in 291).

## Acceptance criteria
- [ ] No "Regularize range" / multi-select bar on the register or the drawer; row icons still work
- [ ] No unused exports or dead state left; `npx tsc --noEmit` and lint clean
- [ ] The employee-directory drawer still behaves as before

## As built (2026-10-28)
Removed from `hrManager/Attendance.tsx`: the checkbox column, the "N selected -> Regularize" bar, `picked` / `bulkOpen` / `pickCapHit` state, `togglePicked` / `afterBulk`, the `RegularizeBulkModal` mount, the `*_SELECT_*` row-grid constants and the `withSelect` parameters. Removed "Regularize range" from `shared/EmployeeAttendanceTab.tsx` (it is also mounted by `EmployeeProfileView`, so the button is gone there too — the grid replaces it everywhere) together with its `employeeName` / `onRangeRegularized` props, and deleted `shared/RegularizeRangeModal.tsx` (no caller left). Kept: the single-day Regularize / Record-leave row icons, the Regularization Inbox, the backend `regularize-range` routes.
Checked: `npx tsc --noEmit` clean; no remaining references to the removed names (`grep`). The employee-profile Attendance tab was not opened in a browser.

Completed: 2026-10-28
