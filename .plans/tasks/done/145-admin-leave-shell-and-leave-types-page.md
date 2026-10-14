---
task: 145
title: HR Admin Leave area — secondary nav shell + Leave Types page
status: done
depends_on: [144]
---

# 145 — HR Admin Leave shell + Leave Types page

## Scope
Role: **HR Admin** (`dashboards/hrAdmin`, existing nav item `leave`, resource `LEAVE`). Restructure
`hrAdmin/Leave.tsx` into a fullBleed area with secondary module navigation, following the
OrgSettings/AttendanceShifts rail pattern (`hrms-responsive-side-panel` below 1000px):
`Leave Policies · Leave Types · Policy Assignments`. Default: Leave Policies. Breadcrumb +
primary action via `useSetBreadcrumbControls`.

Leave Types page:
- Table: Name · Code · Paid · Unit · Approval · Document · Half Day · Status (archived hidden).
- Create/edit modal with every leave-type column: name, code, paid/unpaid, unit (Day/Hour), allow
  half day (defaults on — matches the new DB default), requires approval, requires document,
  document required after (days), max consecutive days, min notice days, allow negative balance,
  gender applicability, applicable after days (blank = no gate), exclude week-offs, exclude
  holidays, display order, color, effective / termination date (`DateField`, both optional).
- Field lengths mirror the DB: name ≤ 120, code ≤ 30, color ≤ 10.
- **No accrual/entitlement fields here** — they live on policies (146). Remove the per-type policy
  editor from `Leave.tsx` / `LeaveTypeWizard.tsx` once 146 covers it; reuse their type-field pieces.
- Archive via `useConfirm`.
- Shimmer skeletons (table header + rows), 10px page spacing, dd-MMM-yy dates, Tailwind only.

## Acceptance criteria
- [ ] Tabs switch without full reload; narrow-viewport overlay works.
- [ ] Create / edit / archive a leave type against the API.
- [ ] `tsc`/lint clean.

## Progress (2026-09-29) — code complete, browser check pending
- `hrAdmin/Leave.tsx` → `Leave` is now the area shell: a tab strip (Leave Policies · Leave Types ·
  Policy Assignments), breadcrumb trailing crumb via `useSetBreadcrumbExtra` (clicking "Leave"
  returns to Leave Policies). The old per-leave-type screen is renamed `LeaveRulesByType` and
  hosted under **Leave Policies** until 146 replaces it; **Policy Assignments** shows the shell's
  `Placeholder` until 147.
- New `hrAdmin/Leave_components/LeaveTypes.tsx`: table (Name · Code · Paid · Unit · Approval ·
  Document · Half day · Status · Actions), `ShimmerTable` skeleton with the same grid, 10px page
  spacing, "Create Leave Type" in the breadcrumb controls, create/edit modal with every
  leave-type column (no accrual fields), archive via `useConfirm`, buttons gated with
  `usePermission(CREATE|UPDATE|DELETE, "LEAVE")`.
- `tsc --noEmit` + `eslint` clean.

## Decision — tab strip, not a second side rail
The task said "rail pattern". While the Leave Policies tab still hosts the old screen (which has
its own 272px leave-type rail), a second rail beside it would squeeze the content badly; a tab
strip is the secondary navigation instead. On narrow screens it scrolls horizontally, so the
side-panel overlay machinery isn't needed for it (the old screen keeps its own overlay). 146 can
revisit once the old screen is gone.

## Remaining before moving to done
- [ ] Browser check as HR Admin: tabs switch; Leave Types list/create/edit/archive; narrow width.

Completed: 2026-09-29 — browser/manual checks verified by the user.
