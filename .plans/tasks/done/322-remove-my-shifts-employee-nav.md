---
task: 322
title: Web — Remove the "My Shifts" nav item and page from the Employee dashboard
status: done
depends_on: [320, 321]
---

# 322 — Web: Remove My Shifts from the Employee dashboard

## Scope
Once its three tabs have a new home (Calendar -> Home calendar, task 321; Requests / request form -> My Attendance, task 320), delete the standalone page:
- Remove the `myShifts` nav item (`index.tsx` line ~35), its `views.myShifts` entry (~103), the `"myShifts"` entry in `CUSTOM_VIEWS` (~200) and the `MyShifts` import (line 7).
- Delete `Employee/MyShifts.tsx` after confirming nothing else imports it (`grep -rn "MyShifts" frontend/src`). The "My Shifts" assigned-list tab is **dropped** with it — its info is on the Home calendar day detail.
- Anything that navigates to key `myShifts` (e.g. notification links, `onNavigate("myShifts")`) must be repointed to `attendance` — grep and fix.
- Keep the `api.ts` shift functions/types (still used by 320/321).

**Decided (2026-11-02):** the sidebar menu item goes. The separate Home card titled "My Shifts" (assigned list via `listMyShifts`, `EmployeeHome.tsx` ~line 898) is not part of this task and stays.

Not covered: backend (no endpoint is removed), mobile app.

## Files
`frontend/src/dashboards/Employee/index.tsx`, `frontend/src/dashboards/Employee/MyShifts.tsx` (delete), any caller found by grep.

## Acceptance criteria
- [x] `tsc --noEmit` clean, eslint clean on `index.tsx`; no remaining references to `MyShifts.tsx` / the `myShifts` nav key (the Home card's `listMyShifts` is a different thing and stays)
- [x] Employee sidebar no longer lists "My Shifts"; no dead route (verified in code: nav item, view and CUSTOM_VIEWS entry removed; NOT looked at in a browser)
- [x] Task 309 note added pointing at 320/321/322 (309 itself is moved to `dropped/` by whoever closes it)

Completed: 2026-11-02
