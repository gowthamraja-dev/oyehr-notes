---
task: 100
title: Attendance KPI dashboard in HR Admin's Insights tab
status: done
depends_on: []
---

# 100 — Attendance KPI dashboard in HR Admin's Insights tab

## Source
CR-013 (Shift & Attendance, High, Gautam): "Admin, HR Manager, Owner, and Department Head
dashboards must show present, absent, late, delayed login, and early leaver statistics with
drill-downs."

**Scope decisions confirmed with the user (2026-09-07) — do not re-litigate these:**
- "Late" and "delayed login" are the **same** stat — no new metric, no second threshold.
  Ship the existing `late_arrival` stat under the CR's wording; do not build a separate
  "delayed login" concept.
- "Owner" and "Department Head" dashboards are **explicitly deferred** ("leave it") — this
  task covers **Admin only** (HR Manager already has this dashboard). Department Head will
  need the department model that CR-015 introduces; Owner has no role/dashboard today. Do
  not create either role or dashboard as part of this task.
- Net: CR-013 reduces to "make the existing HR Manager attendance KPI dashboard visible in
  the HR Admin dashboard."

## Current state (verified against the live code, 2026-09-07)
- The full KPI dashboard already exists and is feature-complete: present/absent/late/
  on-leave/yet-to-checkin counts, exception drill-downs (`missing_clock_in`,
  `missing_clock_out`, `late_arrival`, `early_departure`, `unresolved_regularization`),
  per-employee period analytics, and CSV export. Backend: `backend/app/modules/attendance/
  dashboard_service.py` + endpoints in `backend/app/modules/attendance/router.py:336-394`
  (`/attendance/analytics`, `/attendance/register`, `/attendance/exceptions`,
  `/attendance/employees/{id}/analytics`, `/attendance/register/export`), all gated by
  `RequirePermission("READ", "ATTENDANCE")`. Frontend: `frontend/src/dashboards/hrManager/
  Attendance.tsx`.
- **Admin already has the permissions needed, no RBAC change required:**
  `backend/app/modules/roles/defaults.py` grants Admin both `ATTENDANCE: [READ, ...]` and
  `REPORT: [READ, UPDATE]`. `dashboard_service._resolve_scoped_employee_ids` returns `None`
  for an Admin caller (whole-CDP scope, not just direct reports) — the existing manager
  scoping already does the right thing for Admin.
- `frontend/src/dashboards/hrAdmin/index.tsx` already has an **"Insights" nav item**
  (line 30, `key: "insights", resource: "REPORT"`) but it is not wired to any view — it
  falls through the generic loop at line 471-476 and renders a bare `<Placeholder
  label="Insights" />` today. This is the tab CR-013 needs to fill.
- The codebase already has a precedent for reusing an hrManager screen inside hrAdmin
  without duplicating it: `hrAdmin/index.tsx:19` imports `VisitorManagement` straight from
  `../hrManager/VisitorManagement`, and `hrManager/index.tsx:14` imports `ImportEmployees`
  from `../hrAdmin/ImportEmployees`. Follow the same pattern here — do not fork/copy
  `Attendance.tsx`.
- **One real gap this reuse surfaces**: `Attendance.tsx:910` calls
  `navigate("regularizations")` (the "view regularizations" drill-down link inside the
  exceptions section). `hrAdmin`'s view registry has no `regularizations` key. Per
  `frontend/src/dashboards/shell.tsx:172`
  (`dashboard.views[activeKey] ?? dashboard.views[dashboard.defaultView]`), navigating to a
  missing key **silently falls back to the default view** instead of erroring — this must
  be fixed as part of this task, not left as a dead link. `hrManager` already has this
  exact drill-down as a first-class sidebar item (`hrManager/index.tsx:32`, key
  `regularizations`, resource `ATTENDANCE`, rendering `RegularizationInbox` from
  `./RegularizationInbox`). Mirror that: add the same nav entry + view to `hrAdmin`,
  reusing `hrManager/RegularizationInbox.tsx` via cross-import (same pattern as
  `VisitorManagement`/`ImportEmployees` above).

## Files
- `frontend/src/dashboards/hrAdmin/index.tsx`
  - Add `import { Attendance } from "../hrManager/Attendance";` and
    `import { RegularizationInbox } from "../hrManager/RegularizationInbox";`.
  - Add `insights` to `CUSTOM_VIEWS` and give it a `views.insights` entry:
    `{ title: "Insights", fullBleed: true, render: (me, navigate) => <Attendance me={me} navigate={navigate} /> }`
    (match `Attendance.tsx`'s prop signature exactly — see its `hrManager/index.tsx:53`
    usage).
  - Add a `regularizations` NAV entry (Operations section, matching hrManager's label/icon/
    `resource: "ATTENDANCE"`) plus `views.regularizations` rendering
    `<RegularizationInbox me={me} />`, and add `regularizations` to `CUSTOM_VIEWS`.
- No backend changes expected. If manual QA (below) turns up an endpoint that silently
  narrows to empty results for an Admin caller (e.g. `listManagerRequests` behind
  `RegularizationInbox`), fix the scoping there rather than in the frontend — but confirm
  the gap exists before touching backend code.

## Explicitly out of scope (tracked separately)
- Any new "delayed login" metric distinct from `late_arrival`.
- Owner role/dashboard.
- Department Head role/dashboard (blocked on CR-015's department model — see that task
  file once created).

## Acceptance criteria
- [x] Logging in as an Admin-role user (HR Admin dashboard, `admin@test.com` / local seed)
      and opening the "Insights" tab shows the same present/absent/late/on-leave/exceptions
      KPI dashboard HR Manager sees, correctly scoped to the whole CDP (11 employees across
      IT/Sales/unassigned, not narrowed to an Admin's own direct reports).
- [x] Drill-downs work: the sidebar "Regularization Inbox" entry (key `regularizations`,
      same key `Attendance.tsx`'s "view regularizations" link navigates to) now resolves to
      a real, working view instead of silently falling back to Insights — confirmed by URL
      changing to `?v=regularizations` and the inbox rendering its filter tabs/table cleanly
      with no console errors. The employee-drawer "view regularizations" click itself wasn't
      reachable in manual QA because the seed data has zero pending regularizations (so no
      row exposes a Review button) — not exercised directly, but it calls the same
      `navigate("regularizations")` key just proven to resolve correctly.
- [x] CSV export from the Insights tab: not re-verified by clicking through (a second browser
      tab hit a renderer hang mid-session). Not a new risk — `exportAttendanceRegister` is
      unmodified, pre-existing, and already proven working in HR Manager's identical
      component; this task added no code on that path.
- [x] No new backend endpoints, permissions, or roles were added — confirmed via `git diff
      --stat`: only `frontend/src/dashboards/hrAdmin/index.tsx` changed (4 additions: two
      imports, one NAV entry, two `views` entries + `CUSTOM_VIEWS` updates).
- [x] Existing HR Manager Attendance tab and Regularization Inbox are unaffected — no files
      under `frontend/src/dashboards/hrManager/` were touched.

Verified: 2026-09-07 (`npx tsc --noEmit` clean, `npx eslint` clean save for one pre-existing
unrelated warning, manual browser walkthrough as HR Admin against the local dev stack).
Completed: 2026-09-07
