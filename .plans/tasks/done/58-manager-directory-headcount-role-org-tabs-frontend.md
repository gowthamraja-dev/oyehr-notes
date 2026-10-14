---
task: 58
title: Employee Directory — Headcount, Role and Organization tabs
status: done
depends_on: [53, 57]
---

# 58 — Employee Directory — Headcount, Role and Organization tabs

## Discussion

Design prompt §4/§14–§16 call for four directory tabs — **Employees** (built in [[57]]),
**Headcount**, **Role**, **Organization** — as stateful tabs on the same directory screen, not
separate nav items. Today's `shared/EmployeeDirectory.tsx` has no tab concept at all — it's a
single department-sidebar + table layout. This task adds the tab strip (Employees / Headcount /
Role / Organization) above the existing content, defaulting to Employees, and builds the three
new read-oriented views against [[53]]'s aggregate endpoints. Keep [[57]]'s department-sidebar +
table layout as the Employees tab's content unchanged — these three are new, additive views
alongside it, not a replacement.

### Headcount tab (design prompt §14)

Consumes `GET /employees/headcount`. Show: total, active, inactive, on-leave as KPI tiles (reuse
this dashboard's existing KPI-tile visual pattern — check `RegularizationInbox.tsx` or
`hrManager/Attendance.tsx` for the established tile shape rather than inventing a new one), plus
a per-department breakdown (bar or simple ranked list with `count`/`share`) using
`by_department`. This is read-only — no interactions beyond viewing.

### Role tab (design prompt §15)

Consumes `GET /employees/roles`. A simple table/list: designation, employee count, active count.
No "open/vacant positions" column or field anywhere — [[53]]'s `RoleAggregateOut` deliberately
has no such field since no recruitment/position data backs it in this codebase; do not add a
placeholder or "coming soon" column for it either, per the design prompt's "do not infer
vacancies from employee counts" rule.

### Organization tab (design prompt §16)

Consumes `GET /employees/organization`, a recursive tree (`OrganizationNodeOut`: id, name,
designation, department, direct_report_count, reports[]). Render as an expandable/collapsible
tree (start collapsed below 2 levels deep for a large org — check the root node's total
descendant count before deciding default expansion, so a large CDP doesn't render a giant
expanded tree on first paint). Clicking a node should open that employee's quick-view drawer
(reuse `EmployeeDetailDrawer` from [[57]] — same component, don't build a second one) rather than
navigating away, matching design prompt §7's row-click convention for the Employees tab.

### Tab state

Add `activeTab: "employees" | "headcount" | "role" | "organization"` to `EmployeeDirectory`'s
existing top-level state (alongside `dept`/`search`/`status` from [[57]]) so it's preserved the
same way search/filter state already is when the drawer opens/closes. Each tab fetches its own
data lazily (on first activation), not all four eagerly on mount — the Employees tab's paginated
list is the only one that needs to load immediately.

## Files

- `frontend/src/dashboards/shared/EmployeeDirectory.tsx` — tab strip + three new tab bodies (as
  new components in the same file or extracted to `EmployeeHeadcountTab.tsx`/`EmployeeRoleTab.tsx`/
  `EmployeeOrganizationTab.tsx` under `shared/` if the file gets unwieldy — match whatever this
  dashboard's existing convention is for splitting large screen components, e.g. how
  `AttendanceShifts_components/` is organized)
- `frontend/src/lib/api.ts` — `getHeadcount`, `getRoleAggregates`, `getOrganizationTree` wrappers

## Manual verification

Verified live against the `beta` seed tenant (HR Manager role), backend run locally the same way
as [[57]] (Docker's `api` image still can't rebuild — expired CodeArtifact token, no AWS creds in
this environment — so `uv run uvicorn` against the same dev Postgres, then the Docker container
was restarted afterward). The Chrome extension's `computer` `type` action silently failed to
reach React-controlled inputs this session (typed text never appeared in the DOM — confirmed via
`document.querySelectorAll('input')[...].value` reading back empty) and `Page.captureScreenshot`
continued to time out (both are the same tooling issues noted in [[57]]'s completion record, not
related to this task's code); login and every interaction below were instead driven via
`javascript_tool`, setting input values through the native-setter + `input`-event dispatch pattern
React's controlled inputs require, then reading state back through `get_page_text` /
`read_network_requests` / `read_console_messages`.

- [x] Switching tabs preserves the Employees tab's search/filter/page state — confirmed: sorted/
      filtered Employees-tab state untouched after visiting Headcount → Role → Organization and
      back (the fetch effect has no `activeTab` dependency, so it never re-runs on tab switch).
- [x] Headcount tile totals match the Employees tab for the same data: Employees tab (default
      `status=Active`) showed "5 shown"; Headcount tab showed `Active: 5`, `Total: 5`,
      `On leave: 0`, `Inactive: 0` on the same seeded data — matches exactly.
- [x] Role tab shows designation/employee-count/active-count only — no vacancy/open-position
      column or text anywhere (confirmed via `get_page_text`).
- [x] Organization tree renders as a forest (root "Beta Manager" with 3 reports, plus two
      unmanaged roots "Sample Employee"/"Manager One", matching the seeded data's actual
      reporting lines) with zero console errors; clicking a node (Priya Nair) opened the same
      `EmployeeDetailDrawer` the Employees tab uses, not a navigation.
- [x] Basic caching confirmed via network log: visiting Headcount → Role → Organization each
      fired exactly one request pair (doubled only by React StrictMode's dev-mode double-effect,
      not a caching bug); returning to Employees then back to Headcount fired **zero** new
      requests — the cached data rendered instantly from the parent-held cache state.
- [x] Each tab shows its own shimmer skeleton while loading (reviewed in code — `HeadcountSkeleton`/
      `RoleSkeleton`/`OrganizationSkeleton`, not the whole-page `DirectorySkeleton`); not
      independently screenshot-verified due to the tooling issue above, but confirmed structurally
      distinct from `DirectorySkeleton` and gated correctly (`cache === null` before first load).

## Acceptance criteria

- [x] All three new tabs render real, API-backed data — no `812`-style hardcoded figures (verified
      live: 5/5/0/0 headcount, 3 real designations, a real 5-node reporting forest).
- [x] Tab switching doesn't refetch data already loaded for a tab visited earlier in the session —
      implemented as three `useState<T | null>` caches (`headcountCache`/`rolesCache`/`orgCache`)
      held in `EmployeeDirectory` itself (not inside the tab components, which unmount when
      inactive and would lose a component-local cache) and passed down as `cache`/`onLoaded` props;
      confirmed via network log (see above), no query library needed since none is already in use.

## Completion notes

- Reused, not reinvented: the KPI tile shape from `hrManager/Attendance.tsx`'s `KpiTile` (copied,
  since it's a private, unexported component in that file) and the segmented-control tab-strip
  visual from that same file's `PeriodToggle` — this codebase had no dedicated shared tab-strip
  component to import, so `DirectoryTabStrip` was added locally in `EmployeeDirectory.tsx`.
- Organization tab's default-expansion rule: forests with ≤15 total nodes expand fully; larger
  ones expand only depth 0 (roots) and depth 1 (their direct reports), leaving depth ≥2 collapsed
  until clicked — computed once via `countNodes`/`defaultExpanded` in `EmployeeOrganizationTab.tsx`
  right after the tree loads, exactly as this task's discussion specified.
- Files added: `frontend/src/dashboards/shared/{EmployeeHeadcountTab,EmployeeRoleTab,
  EmployeeOrganizationTab}.tsx` (kept out of the already-large `EmployeeDirectory.tsx`, per the
  task's own suggested split); `frontend/src/lib/api.ts` gained `getHeadcount`,
  `getRoleAggregates`, `getOrganizationTree` plus their response types.
- The sidebar department list (task 57) is now conditionally rendered only for the Employees tab
  — the other three tabs use the full width instead, since a department-filtered sidebar has no
  meaning for a CDP-wide aggregate/tree view.

Completed: 2026-08-19
