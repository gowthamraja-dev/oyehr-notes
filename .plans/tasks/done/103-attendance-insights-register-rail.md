---
task: 103
title: Attendance insights move to a real top-level "Insights" screen, with an Overview/Register split
status: done
depends_on: []
---

# 103 — Attendance insights move to a real top-level "Insights" screen, with an Overview/Register split

## Source
Supersedes [[101-attendance-insights-under-shifts-tab]] (kept in `done/` as history — do not
edit it). The user asked (2026-09-08) to bring the per-employee register back into the
Attendance insights (originally KPI-only, no register per 101), in a "real table" form.

**This task went through two placement decisions during the same session — the second
reverses the first. Both are recorded here so a future reader doesn't re-litigate an already-
settled question, and doesn't mistake the first for the final answer:**

1. First pass (confirmed via AskUserQuestion): keep 101's placement — everything stays inside
   the existing "Attendance & Shifts" → "Insights" tab, which gains its own left rail
   ("Overview" / "Register"). Built, verified live. See git history for this intermediate
   state if needed; it is **not** the shipped result.
2. **Final instruction from the user, after seeing that build**: "remove that from attendance
   and shift section keep it in the insight section" + a screenshot of the design canvas's
   generic org-wide "Insights" screen (`.design/Admin Console.dc.html`'s `isIns` panel — a
   left rail of Headcount/Attendance/Attrition/Diversity/Recruitment) as "the initial ui", with
   "after clicking attendance tile the designed screen should come." This **reverses** both
   101's placement decision and this task's own first pass: the top-level sidebar "Insights"
   nav item (`resource: "REPORT"`) — which 101 had deliberately reverted to an unwired
   placeholder — is now wired up as this feature's first real slice, and "Attendance & Shifts"
   goes back to having no Insights content at all (pre-101 shape, single view, no tabs).

**Shipped architecture:**
- `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/index.tsx` — reverted byte-for-
  byte to its pre-101 form (recovered from `git show <pre-101-commit>^:...`): no tab state, no
  `AttendanceInsights` import, single view (shift list/editor), "New shift" breadcrumb button
  unconditional again.
- `frontend/src/dashboards/hrAdmin/Insights_components/` (new) — the top-level "Insights" nav
  item's screen (`index.tsx` exports `Insights({ me })`, registered in `hrAdmin/index.tsx`'s
  `views`/`CUSTOM_VIEWS` with `fullBleed: true`, matching the OrgSettings/AttendanceShifts
  "owns its own rail + content layout" convention). Left rail: Headcount / **Attendance** /
  Attrition / Diversity / Recruitment (same five, same order, as the design-canvas mock).
  Default selection is Headcount, matching "the initial ui" screenshot's layout — but its
  content is the shared `Placeholder` ("Headcount — this module is coming soon.") from
  `dashboards/shell.tsx`, **not** the mock's fabricated numbers/charts (78 Nursing, 4.2%
  attrition, etc.) — there is no backing endpoint for headcount-by-department, attrition,
  diversity, or recruitment analytics, and shipping invented numbers in a real admin screen
  would be actively misleading. Only **Attendance** is wired to a real view.
  - `components/AttendanceInsights.tsx` and `components/AttendanceInsightsRegister.tsx`
    (moved as-is from `AttendanceShifts_components/components/`, no changes needed — same
    relative import depth to `dashboards/shell` and `dashboards/shared/EmployeeAttendanceTab`)
    — this is "the designed screen" the user's instruction refers to: clicking "Attendance" in
    the outer Insights rail renders `<AttendanceInsights />` unchanged, which itself carries
    its own **inner** rail ("Overview" / "Register") — see below. Rail-inside-rail was a
    deliberate choice, not an oversight: it's literally what was already built and verified
    live in pass 1, and the user's instruction ("the designed screen should come" after
    clicking Attendance) reads as "show that whole built thing," not "flatten it."
- `AttendanceInsights.tsx` (the inner component): left rail "Overview" (KPI row + analytics
  band + period toggle + exceptions band, unchanged from 101's content) / "Register" (full
  employee-level table). Exception pills are clickable again (101 made them read-only) —
  clicking one switches the inner rail to Register pre-filtered to that exception type.
  Date/department/shift context controls are shared above both inner-rail views; `period`
  only affects the Overview analytics band.
- `AttendanceInsightsRegister.tsx` (new, sibling file — split out because the full register
  doesn't fit cleaningly inside `AttendanceInsights.tsx` alongside the Overview content): full
  parity with `hrManager/Attendance.tsx`'s register — search, status-pill filter, sortable
  columns, pagination, CSV export, row-click → employee drawer (`EmployeeAttendanceTab`
  reused directly). The one deliberate gap: the drawer's "Regularization pending" banner has
  no "Review" action button here (HR Admin has no regularization-approvals inbox to send it
  to — that screen only exists on the HR Manager dashboard) — shown read-only instead.
  `hrManager/Attendance.tsx` itself is untouched; both new components are self-contained
  copies, same "don't refactor the already-live, already-tested manager dashboard for a
  moderate reuse payoff" call 101 made.
- Both the outer `Insights` rail and the inner `AttendanceInsights` rail follow the
  `hrms-responsive-side-panel` convention (`useIsNarrow()` from `@/hooks/useIsNarrow`,
  overlay + backdrop + trigger button below 1000px) — copied from `OrgSettings.tsx`'s
  settings-groups nav, the canonical example of this exact pattern in this codebase.
- Backend: **no changes**, in either pass. `/attendance/register` and
  `/attendance/register/export` are already gated `RequirePermission("READ", "ATTENDANCE")`,
  which Admin already holds — same reasoning 101 used for `/attendance/analytics` and
  `/attendance/exceptions`.

## Design reference
`.design/Attendance & Shifts — Insights (rail + register).html` — the static mock built and
browser-verified for pass 1 (Overview/Register rail + full register table + drawer). Its
*content* (the KPI/analytics/exceptions/register composition) carried over unchanged into the
final architecture; only its *placement* (inside Attendance & Shifts) did not. Left as-is under
`.design/` as a working reference for that composition — not moved or renamed, since renaming
would break the "first try modifying the .design html" trail if anyone revisits why it exists.

## Acceptance criteria
- [x] Top-level sidebar "Insights" nav item now opens a real screen: a left rail of
      Headcount/Attendance/Attrition/Diversity/Recruitment, Headcount selected by default,
      showing the shared "coming soon" `Placeholder`.
- [x] Clicking "Attendance" in that rail renders the full attendance insights screen: its own
      inner "Overview"/"Register" rail, KPI row, analytics band + period toggle, clickable
      exceptions band that drills into Register pre-filtered, and the Register view (search,
      status filter, sort, pagination, CSV export, row-click employee drawer).
- [x] "Attendance & Shifts" (`AttendanceShifts_components/index.tsx`) is back to its pre-101
      shape: no tab switcher, single view, "New shift" breadcrumb button unconditional —
      confirmed via diff against `git show <pre-101-commit>^:...` (byte-identical) and live
      (no "Policy config"/"Insights" tabs render, "New shift" button present).
- [x] `hrManager/Attendance.tsx` is untouched — confirmed via `git status`.
- [x] No backend changes.
- [x] `npx tsc --noEmit` clean.
- [x] `npx eslint` on every touched/added file shows no new warnings/errors — only the
      pre-existing `react-hooks/set-state-in-effect` pattern (3 instances, matching
      `hrManager/Attendance.tsx`'s identical pattern exactly) and two pre-existing, unrelated
      warnings (`ShiftsList` unused import in `AttendanceShifts_components/index.tsx`, `me`
      unused in `hrAdmin/index.tsx`'s `ControlCenter`) confirmed via `git stash` to exist at
      the base commit already.
- [x] Manual browser walkthrough as HR Admin against the local dev stack: sidebar Insights →
      Headcount placeholder → Attendance → Overview (real KPI/analytics/exceptions data) →
      exception pill click → Register (pre-filtered) → row click → drawer with
      `EmployeeAttendanceTab` → CSV export — all confirmed working, no console errors at any
      step. Attendance & Shifts screen confirmed reverted (no tabs, "New shift" button back).

Verified: 2026-09-08 (`npx tsc --noEmit` clean, live browser walkthrough via Chrome automation
against the local dev stack logged in as HR Admin — `admin@test.com` / `acme` tenant).
Completed: 2026-09-08
