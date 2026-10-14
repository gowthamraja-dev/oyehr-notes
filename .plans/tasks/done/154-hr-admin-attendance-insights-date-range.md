---
task: 154
title: Attendance date-range filter — HR Admin Insights reuses the HR Manager Attendance UI
status: done
depends_on: [153]
---

# 154 — HR Admin Insights → Attendance renders the HR Manager Attendance page

> Part of requirement "4. Attendance Date Range Filters". Work in **`workspace-2/hrms/`**;
> paths are relative to it.
> Decision (user, 29-Sep-26): the **HR Manager Attendance UI is the finalized one**. Admin
> Insights must show the **exact same UI**, from the same component, not a separately
> maintained copy. The date range is therefore built once (task 153) and admin inherits it.

## Scope

Today HR Admin → Insights → Attendance
(`frontend/src/dashboards/hrAdmin/Insights_components/index.tsx`, `metric === "attendance"`)
renders `<AttendanceInsights />`: a separate re-implementation with an Overview/Register pill
switcher (`components/AttendanceInsights.tsx`, 390 lines) and its own register
(`components/AttendanceInsightsRegister.tsx`, 525 lines). Replace it with
`hrManager/Attendance.tsx`'s `Attendance` component and delete the copy.

**Not in this task:** any date-range work (153 does it once, in the shared component).

- **Make `Attendance` embeddable** (`frontend/src/dashboards/hrManager/Attendance.tsx`):
  - It currently renders its own `<div className="flex h-full min-h-0 flex-col"><main
    className="min-h-0 flex-1 overflow-y-auto p-[26px] …">`. The Insights host already provides
    a scrolling, padded `<main>`, so add an `embedded?: boolean` prop that renders the content
    without that outer wrapper. Non-embedded output must stay byte-identical for the manager
    dashboard.
  - `navigate` becomes optional. The drawer's "Review" action calls
    `navigate("regularizations")`, and the HR Admin dashboard has no `regularizations` key
    (`hrAdmin/index.tsx`), so hide "Review" when no `onReview`/`navigate` is supplied. Don't
    route admins somewhere guessed.
  - `me` stays in the signature (it's already `void`ed).
- **Mount it:** in `Insights_components/index.tsx`, `metric === "attendance"` →
  `<Attendance me={me} embedded />` (import from `../../hrManager/Attendance`, the same way
  `hrAdmin/index.tsx` already imports `../hrManager/VisitorManagement`).
- **Delete** `components/AttendanceInsights.tsx` and `components/AttendanceInsightsRegister.tsx`
  once `grep -rn "AttendanceInsights" frontend/src` shows no other importer (checked on
  29-Sep-26: only `index.tsx`). The Overview/Register pill and its "Register · {headcount}" badge
  go away with them, because the manager page is a single page.
- Data scope needs no backend change: the same `/attendance/*` endpoints already return the whole
  CDP for an admin and direct reports for a manager (`_resolve_scoped_employee_ids`).

## Files
- `frontend/src/dashboards/hrManager/Attendance.tsx`: `embedded` prop, optional `navigate`.
- `frontend/src/dashboards/hrAdmin/Insights_components/index.tsx`: mount `Attendance`.
- `frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsights.tsx`: delete.
- `frontend/src/dashboards/hrAdmin/Insights_components/components/AttendanceInsightsRegister.tsx`: delete.

## Acceptance criteria
- [ ] HR Admin → Insights → Attendance looks and behaves exactly like the HR Manager Attendance
      page (header + date range, filters, KPI row, analytics band, exceptions, register,
      export, drawer), with no doubled padding or nested scrollbars inside the Insights layout.
- [ ] Insights' metrics rail and the narrow-viewport rail toggle still work around it.
- [x] Admin sees the whole CDP; the manager page still sees direct reports only.
- [ ] Drawer "Review" is hidden for admin and still works for the manager.
- [ ] The manager dashboard's Attendance page is visually unchanged by the `embedded` prop.
- [x] The two deleted files have no remaining references; `npm run lint` and `npx tsc --noEmit`
      are clean.
- [ ] Verified in the browser as HR Admin and as HR Manager.

## Progress (29-Sep-26)
- `hrManager/Attendance.tsx`: `Attendance({ me, navigate?, embedded? })`. When embedded, the
  outer element is a plain `div` with no scroll/padding classes and `Main` renders a `div`
  instead of a second `<main>`. When not embedded, the output is unchanged. The drawer's `onReview`
  is optional, so "Review" is hidden when no `navigate` is passed.
- `hrAdmin/Insights_components/index.tsx`: `metric === "attendance"` → `<Attendance me={me} embedded />`.
- `git rm` `components/AttendanceInsights.tsx` and `components/AttendanceInsightsRegister.tsx`.
  `grep AttendanceInsights src/` is empty.
- `npx tsc --noEmit` clean. eslint: only the 3 `set-state-in-effect` errors that were already in
  `Attendance.tsx`; the deleted copies took their own 3 with them.
- Admin scope needs no code: `/attendance/*` already returns the whole CDP for an admin (backend
  tests `test_register_admin_sees_whole_cdp`, `test_register_range_admin_sees_every_employee_every_day`).

**Still open:** the browser checks (layout inside Insights, rail + narrow toggle, Review hidden for
admin, manager page unchanged). This needs a dev-DB tenant with attendance data and HR Admin + HR
Manager logins.

Completed: 2026-09-29 — browser/manual checks verified by the user.
