---
task: 240
title: Shift Scheduling grid shows work location + location filter + WFH count
status: done
depends_on: [239]
---

# 240 — Shift Scheduling grid shows work location + location filter + WFH count

## Scope
Reported: "Shift is showing as General only — unable to see to whom WFH is applied." The roster API
already returns `work_location_master_id` per day (`ResolvedDayOut`); the grid cell
(`ShiftScheduling.tsx`) only renders the shift code. Frontend only:
- Load `listWorkLocations()`; show a location badge (location `code`, else first 3 letters of
  `name`) under the shift code in each cell; "—" cells and OFF cells show none.
- Cell `title`/tooltip: `GEN · 09:00–18:00 · <Location name>`.
- A **Location** filter next to Role (All / each location / "Not set"), client-side over the
  already-fetched week.
- Metric tile "At non-default location this week" (count of assigned cells whose location is not
  the org-default location, `is_org_default`) — this is the WFH proxy until task 246 decides what
  WFH is. Label the tile neutrally ("Off-site this week") only if a location is clearly remote;
  otherwise "Other location".
- Legend: location badge key.
- Update `ShiftSchedulingSkeleton` to mirror any new tile/filter (shared `Shimmer*` primitives).
NOT in scope: changing assignment (task 242/243), an explicit WFH/remote flag (task 246).

## Files
`hrms/frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, possibly `hrms/frontend/src/lib/api.ts`
(WorkLocation already has `is_org_default`? verify; add to the type if missing).

## Acceptance criteria
- [x] Each assigned cell shows shift code + location badge; tooltip has the location name
- [x] Location filter narrows employees to those with ≥1 cell at that location in the week (incl. "Not set")
- [x] Metric tile ("At other locations", shows "—" when the org has no default location) + skeleton mirrors it; legend lists locations used in the viewed week
- [x] Tailwind only; `tsc` + eslint clean (2026-10-24)
- [x] Browser smoke: employee with a WFH-named location assignment is visibly distinguishable

## Browser smoke (2026-10-24)
Headless Chrome (playwright-core) against a local stack — API :8001 on a fresh local postgres:18 migrated + `seed_dev.py` + RBAC defaults for the 'beta' tenant, Next copy on :3001 with `NEXT_PUBLIC_API_URL` overridden (the shared remote backend was never touched). Logged in as the seeded HR Manager.
- Arjun Rao Sat 24-Oct set to 'Work From Home' → cell shows `GEN` + `WOR`, tooltip `General · 09:00–18:00 · Work From Home`, 'At other locations' tile 0 → 1 (Head Office set as org default), legend lists WOR / HEA, Location filter 'Work From Home' → 1 and 'Not set' → 2 (only days that have a shift count).
- Nit: the badge is the first 3 letters of the name (`WOR`) because the location has no `code`; a code on the location (or the WFH meaning, task 246) would read better.
