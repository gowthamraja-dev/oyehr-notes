---
task: 289
title: Attendance tabs + Regularization grid view (read-only)
status: done
depends_on: [286]
---

# 289 — Attendance tabs + Regularization grid view (read-only)

## Scope
`hrManager/Attendance.tsx` gets two tabs: **Register** (today's page, untouched) and **Regularization** (new). The Regularization tab renders the grid from `GET /attendance/grid`
(task 286) in the roster's look: week / month toggle (month <= 31 days), period nav, department / shift / search filters, paging by employee, sticky first column and header row, a status
chip per cell (P A HD L WO H WFH colours = the register's), small badges for late / pending / locked / regularized, a legend, dimmed non-actionable cells. Read-only here — selection is task 290.
Model the layout on `hrManager/ShiftScheduling.tsx` (grid columns, week/month constants, skeleton). Tailwind only; page spacing per `hrms-spacing`; dates dd-MMM-yy; loading uses
`Shimmer*` primitives mirroring the real grid (header row + N employee rows) — export `RegularizationGridSkeleton`. HR Admin's embedded Attendance (`embedded`) does NOT show the tab (only the HR Manager has regularize rights through this screen); the drawer / Regularization Inbox link keeps working.
Below `NARROW_BREAKPOINT` (1000px) show a "use a larger screen" notice instead of the grid.

## Files
`frontend/src/dashboards/hrManager/Attendance.tsx` (tab shell), new `frontend/src/dashboards/hrManager/RegularizationGrid.tsx`, `frontend/src/lib/api.ts` (`getAttendanceGrid` + types).

## Acceptance criteria
- [x] Tab switch keeps Register state; Register behaviour unchanged
- [x] Grid cells match the register's statuses for the same day; legend present
- [x] Skeleton matches the real layout (no shift on load); week/month, filters and paging work
- [x] `npx tsc --noEmit` and lint clean for touched files

## Progress (2026-10-28) — built, NOT yet checked in a browser
Built: `hrManager/RegularizationGrid.tsx` (week/month, period nav, Today, search + department + shift filters, paging by employee, status chips, badges, legend, dimmed cells, `RegularizationGridSkeleton`, narrow-screen notice) and the tab shell in `hrManager/Attendance.tsx` (the register component is now `AttendanceRegister`; `Attendance` wraps it with Register | Regularization tabs, register stays mounted, grid mounts on first open, embedded = register only). `getAttendanceGrid` + types in `lib/api.ts`. `npx tsc --noEmit` clean; eslint clean for the new files.
Left to tick: grid cells vs the register on a real tenant; skeleton -> content shift; week/month/filters/paging; register state surviving a tab switch. Needs a dev server (not started — needs approval).

Browser-verified by the user (2026-10-28); acceptance boxes ticked on that basis.
Completed: 2026-10-28
