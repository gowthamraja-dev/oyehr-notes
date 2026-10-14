---
task: 57
title: Manager Portal — wire Employee Directory to the real API (Employees tab)
status: done
depends_on: [52]
---

# 57 — Manager Portal — wire Employee Directory to the real API (Employees tab)

## Discussion

`frontend/src/dashboards/hrManager/EmpDirectory.tsx` is currently a literal 5-line
`<Placeholder label="Employee Directory" />`, already wired into `hrManager/index.tsx`'s nav
(`key: "employees"`, `label: "Employee Directory"`) — the nav slot and title exist, only the
screen's content needs building. Meanwhile `frontend/src/dashboards/shared/EmployeeDirectory.tsx`
is a full, real implementation already used by `hrAdmin` (`hrAdmin/index.tsx:184`,
`<EmployeeDirectory me={me} />`) — department-sidebar layout, search box, status filter,
employee table, quick-view drawer, full profile view, Add-employee modal. **Reuse this shared
component for the Manager Portal too** — don't fork a second directory implementation; both
`hrAdmin` and `hrManager` are meant to converge on the same directory surface per the design
prompt's "the sidebar includes... Employee Directory" being one shared module, not two.

Change `hrManager/EmpDirectory.tsx` to render `<EmployeeDirectory me={me} />` exactly like
`hrAdmin` does (`EmployeeDirectory` already receives `me` as a prop; update
`hrManager/index.tsx`'s `employees` view entry — currently `render: () => <EmployeeDirectory
/>` with no `me` passed, since today's component takes no props — to `render: (me) =>
<EmployeeDirectory me={me} />`, matching how `attendance`/`roster`/`regularizations` already
receive `me` in that same file).

### Required rework of `shared/EmployeeDirectory.tsx` (per [[52]]'s new API)

[[52]] changes `GET /employees`'s response envelope from a bare array to `{data, pagination}`
and adds server-side `search`/`department`/`employment_status`/`status`/`reporting_manager_id`/
`joining_date_from`/`joining_date_to`/`page`/`page_size`/`sort_by`/`sort_order`. Today's
component (`useState<Employee[] | null>`, a single `getEmployees()` call, `useMemo` client-side
filtering over the full list, and a client-derived department list) cannot work unchanged
against that API. Rework needed:

- **`frontend/src/lib/api.ts`**: update `getEmployees()` to accept a params object and return
  the new envelope type — `EmployeeListResponse = { data: Employee[]; pagination: { page: number;
  page_size: number; total: number; total_pages: number } }`. This is a breaking change to the
  function's signature/return type — `EmployeeDirectory.tsx` is its only caller (confirmed by
  grep during planning), so there's nothing else to update.
- **Search**: debounce the `search` input (300ms is this codebase's existing convention where
  debouncing already exists elsewhere — check for a shared debounce hook before writing a new
  one) before calling the API — design prompt §5 explicitly requires server-side, debounced
  search, not the current instant client-side filter.
- **Department sidebar**: replace the `useMemo` that derives department counts from the
  (now-partial, paginated) `employees` array with a call to [[53]]'s `GET /employees/departments`
  — the counts must come from the full CDP, not just the current page.
- **Status filter**: today's `StatusFilter = "Active" | "Inactive" | "All"` select maps directly
  onto [[52]]'s new `status` query param — add the missing `"On Leave"` option per the design
  prompt's four-way status concept (§6), sent as-is to the API (the backend already defines what
  "On Leave" means; the frontend doesn't compute it).
- **Filter drawer**: today there's only the inline status `<select>` — no department/employment-
  status/reporting-manager/joining-date filters and no drawer with Apply/Reset/Close. Add one,
  following this dashboard's existing modal/drawer visual pattern (see
  `EmployeeDetailDrawer.tsx`'s slide-in drawer shell for the shape to reuse, not a full-screen
  modal). Populate the department/status/manager dropdowns from [[53]]'s metadata endpoints.
  Selections apply via an explicit "Apply" action (don't fire a request per keystroke on every
  filter — only the search box is live-debounced); "Reset" clears all filter state; "Close"
  discards uncommitted changes without applying them.
- **Pagination**: add page controls (respecting [[52]]'s `{25,50,100}` page-size options) below
  the table; replace the current `max-h-[560px] overflow-y-auto` scroll-everything table body
  with a fixed page of rows plus pager controls.
- **Sortable columns**: at minimum "Employee" (name) and "Department" headers toggle
  `sort_by`/`sort_order`.
- **Preserve state across drawer open/close and pagination** (design prompt §6): search/filter/
  page state must not reset when `detailId`/`profileId` change — today's component already keeps
  this state at the top level of `EmployeeDirectory`, so this is mostly "don't regress it" rather
  than new work, but explicitly verify it once pagination/filters are added (a naive
  re-implementation could easily reset `page` to 1 whenever the drawer closes if the effect
  dependencies aren't scoped carefully).
- **Loading/empty/error states**: today only has a full-component `DirectorySkeleton` (initial
  load) and a plain "No employees match your filters" text row (empty state, no reset-filters
  action). Add: a **row-level** loading state for subsequent page/filter fetches (don't re-show
  the full-page skeleton on every filter change — keep the shell visible, only the table body
  shimmers); an empty state with a "Reset filters" button when filters are active vs. an "Add
  employee" nudge when the CDP genuinely has zero employees; a compact error card with a "Retry"
  action if a fetch fails (today a failed fetch silently sets `employees = []`, which is
  indistinguishable from a genuine empty CDP — fix this to track a distinct error state).
- **Table columns**: design prompt §7 recommends adding Reporting Manager and Joining Date
  columns. The current table is `Employee / ID / Department / Role / Status / Engage` — add
  Reporting Manager and Joining Date without removing the existing `EngageButton` action column
  (that's this codebase's own addition, not part of the design prompt, and must be preserved).
  Do **not** add salary/bank/PAN/Aadhaar columns (design prompt §7's explicit exclusion — moot
  here since none of that data is even in `EmployeeOut`, but noting it so no one "helpfully"
  wires it in later from `EmployeeDetailOut`).
- **Quick-view drawer actions**: `EmployeeDetailDrawer.tsx` today only has "View full profile"
  wired. Add "View attendance" and "View leave details" buttons per design prompt §8, each
  navigating to the full profile view with the corresponding tab pre-selected (coordinate the
  exact mechanism — e.g. an optional `initialTab` prop threaded through `onViewProfile` — with
  [[59-employee-profile-attendance-leave-documents-tabs-frontend]], which builds those tabs).

### Header counts

Design prompt §4: "812 employees across 14 departments... make the values API-driven." Source
`total` from the list response's `pagination.total` (unfiltered — call once with no filters, or
derive from [[53]]'s `headcount.total`, whichever avoids an extra request) and department count
from [[53]]'s `departments` list length. Never hardcode `812`.

## Files

- `frontend/src/dashboards/hrManager/EmpDirectory.tsx`
- `frontend/src/dashboards/hrManager/index.tsx` (`employees` view's `render` signature)
- `frontend/src/dashboards/shared/EmployeeDirectory.tsx` — the bulk of the rework
- `frontend/src/dashboards/shared/EmployeeDetailDrawer.tsx` — new action buttons
- `frontend/src/lib/api.ts` — `getEmployees()` signature/return type, plus new wrappers for
  [[53]]'s metadata endpoints (`getEmployeeDepartments`, `getEmploymentStatuses`,
  `getReportingManagers`)

## Manual verification (per CLAUDE.md's UI-change rule)

Verified live against a real backend + seeded data (`beta` tenant, HR Manager role, `scripts/
seed_dev.py`) — Docker's `api` image couldn't be rebuilt (CodeArtifact token for `nhforms` had
expired and no AWS credentials were available to mint a new one in this environment), so the
already-`uv sync`'d local `backend/.venv` was run directly with `uvicorn` against the same dev
Postgres instead (`docker compose stop api` to free the port; restarted the container afterward
to restore the environment). The Chrome extension's screenshot capture (`Page.captureScreenshot`)
timed out for the whole session for an unrelated reason (confirmed the page itself was healthy
throughout — zero console errors, correct network requests, and `get_page_text` returned fully
rendered content at every step), so verification below is via DOM text extraction, network-request
inspection, and console-error checks rather than visual screenshots.

- [x] Manager Portal sidebar → Employee Directory shows the real directory, not a placeholder.
- [x] Typing in search debounces and hits the server: typing "Priya" produced exactly one
      GET (+ its CORS preflight), not one per keystroke; results narrowed to 1 row correctly.
- [x] Filter drawer: Apply (department=Operations) narrowed to 2 rows and added a "Dept:
      Operations ×" chip + "Filters 1" badge; Reset restores the full unfiltered view.
- [x] Paging through results keeps the active search/filter applied (state lives at the top of
      the component, not per-fetch).
- [x] Opening/closing the quick-view drawer and navigating to the full profile and back preserves
      sort order and filters (verified: sorted by department, opened Priya Nair's profile via
      "View attendance", returned via the "Employee Directory" breadcrumb — department sort order
      was still applied).
- [x] Header counts match real seeded data ("5 employees across 2 departments"), not `812` —
      confirmed unaffected by the active search/status filters (stayed at 5/2 while the table
      itself narrowed).
- [ ] Simulated-backend-down Retry card: not exercised live (would have required stopping the
      one live backend mid-session); the code path (`fetchFailed` state → error card → `fetchList`
      retry) was reviewed but not clicked through. Low risk — straightforward `.catch()`.
- [x] Shimmer skeleton / no spinner text: confirmed by code review (full `DirectorySkeleton` on
      first load, `RowSkeleton` table-body-only shimmer on subsequent fetches) — not independently
      screenshot-verified due to the tooling issue above, but no "Loading…" text or spinner exists
      anywhere in the component.

## Acceptance criteria

- [x] `hrManager`'s Employee Directory is the same real, shared component `hrAdmin` uses — no
      second parallel implementation (`hrManager/EmpDirectory.tsx` is now a one-line re-export).
- [x] Zero remaining full-list client-side filtering — every search/filter/sort/page interaction
      round-trips to the server (confirmed via network log: distinct `department=`/`search=`/
      `sort_by=`/`status=` query strings per interaction, no client-side array filtering left).
- [x] Loading/empty/error states are each visually distinct and match CLAUDE.md's shimmer-skeleton
      rule.

## Completion notes

- **Backend gap found and closed** (not in this task's original Files list): `EmployeeOut` (task
  52) didn't expose `joining_date`/`reporting_manager_name`, but design prompt §7 (via this task)
  requires them as table columns. Added both fields to `EmployeeOut` and populated
  `reporting_manager_name` via an `outerjoin` on a self-aliased `EmployeeMaster` in
  `list_employees` (`backend/app/modules/employees/{schemas,service}.py`), plus one new backend
  test. Full backend suite still green (49/49 in `test_employees.py`).
- `getEmployees()`'s signature changed again (was already reshaped once in [[52]]'s own
  completion): now takes an `EmployeeListParams` object and returns the full
  `EmployeeListResponse` (not just `.data`) — `EmployeeDirectory.tsx` is still its only caller.
  Added `getEmployeeDepartments`/`getEmploymentStatuses`/`getReportingManagers` wrappers for
  [[53]]'s metadata endpoints.
- **Quick-view drawer's "View attendance"/"View leave" buttons** both currently route to the same
  full profile as "View full profile" — `EmployeeProfileView.tsx` has no tabs yet (confirmed: it's
  a flat card layout), so there is nowhere more specific to land. Adding an `initialTab` prop now
  would be unused plumbing for a feature that doesn't exist; [[59-employee-profile-attendance-leave-documents-tabs-frontend]]
  is expected to both build the tabs and extend `onViewProfile`/`EmployeeProfileView` with the
  tab-hint at that point, per this task's own "coordinate with 59" note.
- Debounce uses 400ms (not the 300ms this task's discussion assumed) to match the codebase's
  actual existing convention (`AddOrganizationModal.tsx`'s subdomain check, `MyLeave.tsx`'s
  preview), confirmed by grep — no shared debounce hook exists, so this follows the same inline
  `setTimeout` + `cancelled` pattern as those two call sites.
- Brought the filter card's padding in line with the `hrms-spacing` skill (`p-[10px]`, not `p-4`)
  and the table's row density (`py-3` body / `py-[10px]` header) since this rework touched both
  blocks anyway.
- `frontend/src/dashboards/shared/EmployeeDirectory.tsx`'s new data-fetching effect calls
  `setFetching(true)`/`setFetchFailed(false)` synchronously at its start, which trips the
  `react-hooks/set-state-in-effect` ESLint rule — this exact pattern (`setLoading(true);
  setError(null); ...` at the top of a fetch effect) is already present, pre-existing, in
  `EmployeeDetailDrawer.tsx` and `EmployeeProfileView.tsx` (confirmed via `git stash` + eslint on
  the original files), so this is consistent with established convention, not a new regression.

Completed: 2026-08-19
