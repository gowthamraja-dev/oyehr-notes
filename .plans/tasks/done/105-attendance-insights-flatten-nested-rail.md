---
task: 105
title: Flatten the Attendance Insights nested rail — three left sidebars into two
status: done
depends_on: [103-attendance-insights-register-rail, 104-insights-headcount-view]
---

# 105 — Flatten the Attendance Insights nested rail — three left sidebars into two

## Source
Bug reported by the user (2026-09-09) with a screenshot: the Insights → Attendance screen
showed **three** stacked left sidebars — the app shell's own sidebar, the outer Insights
screen's metrics rail (Headcount/Attendance/Attrition/Diversity/Recruitment, from task 103/104),
and `AttendanceInsights.tsx`'s own inner rail (Overview/Register, also from task 103) — all
full-height, all in a row. Confirmed by inspecting the referenced screenshot directly.

## Fix
`AttendanceInsights.tsx`'s inner "Overview"/"Register" rail is replaced with a small pill/tab
switcher (`inline-flex rounded-[9px] border border-border bg-ink-50 p-[3px]`) — the same visual
pattern already used elsewhere in this file for `PeriodToggle` and in the pre-101
`AttendanceShifts_components/index.tsx` "Policy config"/"Insights" switcher. Same two views,
same behavior (exception-pill click still switches to Register pre-filtered, `registerFilter`
still resets to "all" on a plain tab click) — only the chrome changed from a second `<aside>`
rail to a tab row. This also let the whole `useIsNarrow`/`railOpen` overlay machinery in this
component be deleted outright: a tab row has no narrow-viewport collapse problem the way a
fixed-width side rail does, so `hrms-responsive-side-panel` no longer applies to this file at
all — only the *outer* Insights screen's own metrics rail (`Insights_components/index.tsx`)
still needs it, and still has it, unchanged.

## Files
- Edit: `frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsights.tsx`
  — removed the `<aside>` rail, `useIsNarrow` import/state, and the mobile trigger button;
  added the tab-pill row; renamed the `RailView` type/`railView` state/`selectRailView` function
  to `View`/`view`/`selectView` (no longer a "rail" once it's a tab switcher).
- No other files touched. No backend changes.

## Acceptance criteria
- [x] Insights → Attendance shows exactly two left-hand columns: the app shell sidebar and the
      Insights metrics rail — confirmed live via screenshot (was three).
- [x] Overview/Register switch, exception-pill drill-down into Register pre-filtered, and the
      Register table (search/sort/filter/pagination/export/drawer) all still work — confirmed
      live, no console errors.
- [x] `npx tsc --noEmit` clean; `npx eslint` shows only the same pre-existing
      `react-hooks/set-state-in-effect` pair already present before this fix (2 instances in
      this file — `fetchSummary`/`fetchExceptions`; the register's own `fetchTable` instance
      lives in the untouched `AttendanceInsightsRegister.tsx`).
- [x] `git status` touches only `AttendanceInsights.tsx`.

Verified: 2026-09-09 (`npx tsc --noEmit` clean, `npx eslint` clean save for the pre-existing
pattern, live browser walkthrough via Chrome automation — screenshot confirms two sidebars,
Register/exception-drilldown re-verified working).
Completed: 2026-09-09
