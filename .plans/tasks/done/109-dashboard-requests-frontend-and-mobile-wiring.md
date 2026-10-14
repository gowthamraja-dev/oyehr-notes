---
task: 109
title: "Wire dashboard open-requests count + recent-history APIs into Employee Portal and the employee mobile app"
status: done
depends_on: [106]
---

# 109 — Wire dashboard open-requests count + recent-history APIs into Employee Portal and the employee mobile app

## Scope

Task 106 built `GET /api/v1/home/requests/count` and `GET /api/v1/home/requests/recent`
but explicitly left frontend/mobile wiring out of scope. This task wires both endpoints
into the two real, live consumers: the Next.js Employee Portal
(`hrms/frontend/src/dashboards/Employee/EmployeeHome.tsx`) and the React Native employee
app (`employeeapp/src/screens/HomeScreen/`).

## `hrms/frontend/` (Next.js)

- `src/lib/api.ts` — added `RequestsCount`/`RecentRequest` types and
  `getMyRequestsCount()` / `getMyRecentRequests(limit = 5)`, both via `secureFetch`
  (the `/home` router is `EncryptedRoute`), following the exact pattern of the existing
  `getHomeSummary()`.
- `src/dashboards/Employee/EmployeeHome.tsx`:
  - **Fixed a real double-counting bug** found while wiring this up: the "Open requests"
    stat tile was computing `openLeaveRequests (client-side listMyLeaveRequests({status:
    "Pending"}).length) + stats.open_requests_count`. Task 106 made
    `stats.open_requests_count` already include pending Leave, so this addition was
    double-counting every pending leave request. Removed the separate
    `listMyLeaveRequests({status:"Pending"})` call and the client-side add; the stat tile
    now reads `stats.open_requests_count` directly (single network round-trip, correct
    number).
  - Replaced the "My open requests" panel — previously rendering
    `reimb.claims.filter(c => c.status === "Pending")`, always empty because
    `reimbursements` is fully stubbed (no backing table) — with a new "Recent requests"
    panel backed by `getMyRecentRequests(5)`: any status, newest first, merged across
    Leave + Attendance regularization. Renamed the section header from "My open requests"
    to "Recent requests" since the new endpoint is a history (all statuses), not an
    open-only filter — an open question task 106 flagged explicitly, resolved here in
    favor of "history" to match what the endpoint actually returns.
  - Added `Rejected`/`Cancelled` entries to `STATUS_STYLES` (previously only had
    Pending/Open/In progress/Approved/Reimbursed — Leave/Regularization statuses weren't
    covered) and a per-`request_type` icon map (`REQUEST_TYPE_ICON`).
  - Removed the now-dead `getMyReimbursementSummary` import/call and `ReimbursementClaim`
    type usage from this file (still used elsewhere for `getReimbursementCategories` in
    the expense modal — untouched), and the now-unused `initials()` helper.
  - Added a matching shimmer-skeleton loading state for the new panel (`recentRequests
    === undefined`), per this project's loading-state convention.

## `employeeapp/` (React Native)

- `src/api/EndPoints.js` — added `HOME.REQUESTS_COUNT` / `HOME.REQUESTS_RECENT`.
- `src/screens/HomeScreen/HomeService.js` — added `getRequestsCount()` and
  `getRecentRequests(limit = 5)`, both through the existing `services/NetworkManager`
  axios instance (same one `getDashboardData()` already uses — the app has two competing
  `NetworkManager` implementations, `api/NetworkManager.js` (older, class-based) and
  `services/NetworkManager.js` (axios instance); left that pre-existing duplication
  alone and matched whichever this file already used).
- `src/screens/HomeScreen/HomeViewModel.js` — added passthrough wrappers for both.
- `src/screens/HomeScreen/components/RecentRequestsCard.js` — new component, styled to
  match the app's existing `RequestHistory.js` (LeaveScreen) status-chip conventions
  (`STATUS_COLORS` for Pending/Approved/Rejected/Cancelled) and `ComingSoonCard.js`'s
  card shell. Renders a loading spinner, an empty state, or up to 5 rows (icon by
  `request_type`, title, meta, status chip).
- `src/screens/HomeScreen/Home.js` — replaced the `<ComingSoonCard title="My Open
  Requests" icon="📋" />` placeholder with `<RecentRequestsCard requests={recentRequests}
  loading={recentRequestsLoading} />`, fetched via a new `loadRecentRequests()` effect
  alongside the existing `loadDashboard`/`loadProfile`/`loadShift`/`loadAttendancePct`
  calls. The "Open Requests" stat tile here already read `stats.open_requests_count`
  directly from `/home/summary` with no client-side addition — no double-counting bug on
  this side, nothing to fix there.

## Verification

- `hrms/frontend`: `npx tsc --noEmit` clean; `npx eslint` clean on touched files (one
  pre-existing unrelated warning, `parseIsoDateLocal` unused, untouched by this task).
- Seeded real data via `scripts/seed_realistic_dataset.py` (CDP 602 / subdomain `beta`,
  `ananya.sharma@test.com` / `Test1234!`, Employee role) and submitted a real Pending
  leave request through the live API. Logged into the running dev frontend
  (`localhost:3000/?subdomain=beta`) via Claude in Chrome and visually confirmed: "Open
  requests" stat tile shows the correct count (1, matching `/home/requests/count`, no
  double-count), and the new "Recent requests" panel renders the real Casual Leave
  request with correct dates/status.
- `employeeapp`: no working emulator/simulator available in this environment, and the
  project's `jest` config is currently broken (`Preset @react-native/jest-preset not
  found` — pre-existing, unrelated to this change). Verified instead by building a real
  Metro bundle end-to-end (`npx react-native bundle --entry-file index.js --platform
  android --dev true`), which resolves every import through
  `index.js → App.tsx → navigation → HomeScreen/Home.js → RecentRequestsCard.js` and
  succeeds with no errors — confirms the new files are syntactically valid and wired
  correctly, though it does not confirm on-device rendering.

## Explicitly out of scope

- Fixing the app's two-competing-`NetworkManager` duplication, or its broken `jest`
  preset — pre-existing, unrelated to this task.
- Reimbursement/Helpdesk request kinds — still no backing table (see task 106); both
  UIs already handle that honestly (0 count, absent from the recent list).
- On-device/emulator verification of the mobile app — no emulator available here.

Completed: 2026-09-16
