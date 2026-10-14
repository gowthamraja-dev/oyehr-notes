---
task: 101
title: Move attendance KPI insights into Attendance & Shifts as a tab (KPI-only, no register)
status: done
depends_on: []
---

# 101 — Move attendance KPI insights into Attendance & Shifts as a tab (KPI-only, no register)

## Source
Supersedes [[100-attendance-insights-admin-dashboard]] (kept in `done/` as history — do not
edit it). The user reviewed task 100's result and asked for a different placement and a
narrower scope (2026-09-07):
- **Revert** task 100's change: the top-level sidebar "Insights" nav item (`resource:
  "REPORT"`) goes back to being an unwired placeholder. It's meant for a separate, broader
  "Reports & Analytics" feature (see `permissions.py:53`: "REPORT | Insights · Reports &
  Analytics · Audit Log") — overloading it for attendance-only stats was the wrong home.
  **Done**: `git checkout -- frontend/src/dashboards/hrAdmin/index.tsx` (confirmed clean,
  file matches pre-task-100 state).
- **Instead**: inside the existing "Attendance & Shifts" admin screen
  (`frontend/src/dashboards/hrAdmin/AttendanceShifts.tsx` →
  `AttendanceShifts_components/index.tsx`), add two tabs: **"Policy config"** (the screen's
  current content — shift list + shift editor, unchanged) and **"Insights"** (new).
- **"Insights" shows only the KPI stats — explicitly NOT the employee register/login list.**
  Present/late/on-leave/absent/yet-to-checkin counts, the attendance-analytics band (logged
  hours, timely/late logins, punctuality %), and exception counts — no per-employee table,
  no employee drawer, no CSV export (export is a register/employee-level action).

## Current state (verified against the live code, 2026-09-07)
- `AttendanceShifts_components/index.tsx` (337 lines) has no tabs today — it's a single view:
  a breadcrumb "New shift" button (`useSetBreadcrumbControls`, line 105) plus the shift
  list/editor (`ShiftDefaults`, `ShiftsList`-style rows, lines 122-337). This whole thing
  becomes the "Policy config" tab's content, unchanged.
- The KPI/analytics/exceptions markup already exists, built and proven, inside
  `frontend/src/dashboards/hrManager/Attendance.tsx`:
  - KPI row: lines 574-640 (`KpiTile` components — Present/Late arrivals/On leave/Absent/Yet
    to check in/Attendance %, sourced from `AttendanceAnalytics` via
    `getManagerAttendanceSummary`).
  - Analytics band: lines 642-694 (`MetricTile` components + `PeriodToggle` — Total logged
    hours/Timely logins/Late logins/Average logged hours/Punctuality %/Attendance %, same
    `AttendanceAnalytics` object, re-fetched on period change per the comment at line 153-159:
    the KPI row is date+department+shift scoped only, the analytics band also varies with
    `period`).
  - Exceptions band: lines 696-747 (pill buttons showing `AttendanceExceptionCounts` via
    `getManagerAttendanceExceptions`, currently clickable to filter the register table below
    — **not applicable here since there is no table; render as static/read-only tiles**).
  - The register table starts at line 749 (`{/* ── Register table ── */}`) — everything from
    there down (table, sort, search, pagination, `EmployeeDrawer`, CSV export) is exactly
    what must NOT be reused.
  - Component defs to mirror the look of: `KpiTile` (951-963), `MetricTile` (965-976),
    `PeriodToggle` (978-995).
- **Decision: build a new, self-contained component rather than extracting a shared one out
  of `Attendance.tsx`.** `Attendance.tsx` is a large (1068-line), already-tested, live HR
  Manager screen; refactoring it to share a subcomponent risks regressing it for a
  moderate reuse payoff. The KPI/analytics/exceptions section is a self-contained ~200 lines
  driven by two API calls (`getManagerAttendanceSummary`, `getManagerAttendanceExceptions`)
  plus two lookup calls (`getEmployeeDepartments`, `listShifts`) — cheap to rebuild
  standalone, matching CLAUDE.md's steer against premature abstraction.
- Backend: no changes. Same two endpoints (`/attendance/analytics`, `/attendance/exceptions`)
  already gated `RequirePermission("READ", "ATTENDANCE")`, which Admin already holds
  (`app/modules/roles/defaults.py`).

## Files
- New: `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/
  AttendanceInsights.tsx` — exports `AttendanceInsights()` (no props needed; it's
  self-contained, same as `Attendance.tsx`'s own data-fetching). Contents, adapted from
  `Attendance.tsx`:
  - Date nav (prev/today/next) + department dropdown + shift dropdown (drives the KPI row,
    analytics band, and exceptions — all three, same as today) + `PeriodToggle` (drives only
    the analytics band, same split-loading behavior as the source: `kpiLoading` vs
    `analyticsLoading`).
  - KPI tile row (present/late/on-leave/absent/yet-to-checkin/attendance %).
  - Analytics band (logged hours/timely/late logins/average/punctuality/attendance %).
  - Exceptions band as **read-only** tiles (no `onClick`, no active/selected styling, no
    `filter` state at all — just `{label} · {count}`).
  - No search box, no status-pill filter row, no Export button, no table, no drawer.
  - Import `Icon` from `../../../shell` (same relative depth as `ShiftsList.tsx` in the same
    `components/` folder).
- Edit: `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/index.tsx`
  - Add local `const [tab, setTab] = useState<"policy" | "insights">("policy")`.
  - Render a small tab switcher ("Policy config" / "Insights") above the existing content.
  - Gate the existing breadcrumb "New shift" button (`useSetBreadcrumbControls`) to only show
    when `tab === "policy"` — it's meaningless on the Insights tab.
  - Wrap the existing return content (lines 122-337 today) under `tab === "policy"`; render
    `<AttendanceInsights />` under `tab === "insights"`.
  - Leave `useShifts`/shift-list loading/skeleton behavior untouched — it only affects the
    Policy config tab.
- No backend files touched.

## Acceptance criteria
- [x] Top-level sidebar "Insights" nav item (HR Admin dashboard) is back to its original
      unwired-placeholder behavior — confirmed via `git diff` (empty on
      `frontend/src/dashboards/hrAdmin/index.tsx`) and live: clicking it renders "Insights —
      this module is coming soon."
- [x] "Attendance & Shifts" screen shows a "Policy config" / "Insights" tab switcher; "Policy
      config" renders exactly what the screen showed before this task (shift list + editor,
      "New shift" button present); switching to "Insights" hides the "New shift" button, and
      switching back to "Policy config" brings it back.
- [x] "Insights" tab shows present/late/on-leave/absent/yet-to-checkin counts, the analytics
      band (logged hours/timely/late logins/average/punctuality/attendance %), and exception
      counts, with date/department/shift/period controls — and does **not** show a
      per-employee table, drawer, search box, status-pill row, or export button (confirmed
      via live page-text dump: no employee rows/names, no "Export attendance" button).
- [x] Exception tiles on the Insights tab are static spans, not buttons — no `onClick`, no
      `filter` state in the new component at all (there is no table for them to filter).
- [x] No backend changes; `git diff --short` touches only
      `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/index.tsx` (modified) and
      adds `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/
      AttendanceInsights.tsx` (new, untracked).
- [x] `npx tsc --noEmit` clean; `npx eslint` on both files shows only two pre-existing-pattern
      `react-hooks/set-state-in-effect` errors that mirror the identical, already-live
      pattern in `hrManager/Attendance.tsx` (3 instances there) — not a regression introduced
      by this task, and one pre-existing unrelated `ShiftsList` unused-import warning
      (present before this task too, confirmed via `git stash`).
- [x] HR Manager's own Attendance tab (`frontend/src/dashboards/hrManager/Attendance.tsx`)
      is untouched — confirmed via `git status`.

Verified: 2026-09-07 (`npx tsc --noEmit` clean, manual browser walkthrough as HR Admin
against the local dev stack — placeholder confirmed for the reverted top-level Insights nav
item, tab switcher and both tab contents confirmed live, no console errors beyond unrelated
pre-existing Quill warnings).
Completed: 2026-09-07
