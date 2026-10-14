---
task: 59
title: Full employee profile — Overview/Attendance/Leave/Documents tabs
status: done
depends_on: [54, 55, 45]
---

# 59 — Full employee profile — Overview/Attendance/Leave/Documents tabs

## Discussion

`frontend/src/dashboards/shared/EmployeeProfileView.tsx` today is a single scrolling page —
header band + a grid of `Section` cards (Employment, Contact, Attributes, Personal, Additional
contacts, Notes) + a Form Submissions accordion. The design prompt (§9) calls for this to be a
**tabbed** profile — Overview / Attendance / Leave / Documents — with Overview holding
(approximately) what's already there. This task restructures the page into tabs and builds the
three new ones against backend work from other tasks in this arc:

- **Attendance** tab → [[54]]'s new `GET /attendance/employees/{id}/today` and
  `GET /attendance/employees/{id}/daily`. Day/Week/Month per design prompt §9 — "Day" calls
  `/today`; "Week"/"Month" call `/daily` with a computed `from`/`to` range (current ISO week /
  current calendar month, with prev/next navigation if the existing attendance screens elsewhere
  in this dashboard already have that pattern — check `hrManager/Attendance.tsx` before
  inventing a different range-picker). **Read-only** — no clock-in/out or regularization actions
  here, this is a manager's read view of someone else's attendance, not self-service.
- **Leave** tab → [[45-leave-manager-approval-api]]'s `GET /leave/employees/{id}/balances` (per-
  type balance cards, same shape `getMyLeaveBalances` uses in
  [[49-employee-my-leave-frontend]] — reuse that component/rendering logic rather than
  reimplementing the balance-card UI) and `GET /leave/requests?employee_master_id={id}` for
  recent request history (reuse whatever list-row rendering
  [[50-manager-leave-queue-frontend]] builds for the manager queue table, in read-only mode — no
  Approve/Reject buttons on this tab, those live only in the dedicated Leave-queue screen).
- **Documents** tab → [[55]]'s `GET /employees/{id}/documents` (list) and
  `POST /employees/{id}/documents` (upload). Show existing documents (name/type/uploaded-date,
  a view/download link to `img_url`) plus an upload control gated the same way [[55]]'s `POST`
  route is gated server-side (hide the upload control entirely for a caller who isn't
  admin/the employee's manager — don't rely on the disabled-button pattern alone, since design
  prompt §17 requires the UI to "hide or disable actions the current manager cannot perform" and
  hiding is the stronger, preferred form here since an upload control that's merely disabled
  still reveals that uploading is a thing this profile supports for someone).

### Quick-view drawer → profile tab handoff

[[57]]'s drawer gets "View attendance"/"View leave details" buttons that need to land on this
profile with the right tab pre-selected. Add an `initialTab?: "overview" | "attendance" |
"leave" | "documents"` prop to `EmployeeProfileView`, defaulting to `"overview"` (matches design
prompt §9's "Overview is selected by default" for the plain "View full profile" entry point).

### Breadcrumb

No change needed — `useSetBreadcrumbExtra(detail?.name ?? null, onBack)` already produces
`Dashboard > Employee Directory > Employee Name` per the existing shell; tabs are a sub-state of
this same screen and don't affect the breadcrumb.

## Files

- `frontend/src/dashboards/shared/EmployeeProfileView.tsx` — tab strip, `initialTab` prop,
  Overview tab = today's existing card grid unchanged
- `frontend/src/dashboards/shared/EmployeeDetailDrawer.tsx` — thread `initialTab` through
  `onViewProfile` for the "View attendance"/"View leave details" buttons ([[57]] adds the
  buttons; this task defines what tab they land on)
- New tab components under `frontend/src/dashboards/shared/` — e.g.
  `EmployeeAttendanceTab.tsx`, `EmployeeLeaveTab.tsx`, `EmployeeDocumentsTab.tsx` (split out
  rather than growing `EmployeeProfileView.tsx` into one very large file, matching this
  directory's existing per-concern file split, e.g. `EmployeeAttributesSection.tsx` already
  being its own file for one section)
- `frontend/src/lib/api.ts` — `getEmployeeAttendanceToday`, `getEmployeeAttendanceDaily`,
  `getEmployeeLeaveBalances`, `listEmployeeLeaveRequests`, `getEmployeeDocuments`,
  `uploadEmployeeDocument` (multipart — plain `fetch`, not `secureFetch`, per CLAUDE.md's file-
  upload frontend convention)

## Manual verification

Verified live against the `beta` seed tenant (backend run locally via `uv run uvicorn`, same
CodeArtifact-token limitation as [[57]]/[[58]] — Docker restarted afterward). Browser driven via
`javascript_tool` (the `computer` `type` action continues to not reach React-controlled inputs
this session, as in [[57]]/[[58]]).

- [x] Opening a profile via "View attendance" from the quick-view drawer lands directly on the
      Attendance tab, pre-loaded (confirmed: clicking "View attendance" for Priya Nair rendered
      the profile with "Attendance" already active, Day view showing today's real — empty —
      snapshot, not Overview).
- [x] Attendance tab Day/Week/Month all fetch and render without error; Month correctly showed
      the proper empty state ("No attendance records for this period.") since this seed employee
      has no punches — verified this is real data, not a hardcoded figure.
- [x] Leave tab balance cards render via the reused `BalanceCards` component and match exactly
      what the quick-view drawer's own `LeaveSummarySection` shows for the same employee (Comp
      Off/Sick Leave/Casual Leave, same 0-used/12-entitled Casual Leave figures).
- [x] Documents tab: upload control renders correctly gated by `can_upload_documents`; list shows
      the correct empty state. **Not independently verified for the negative (hidden) case** — the
      only available seed login (`multirole@test.com`) carries `is_admin: true` in its JWT even
      under the "HR Manager" role (confirmed by decoding the token client-side), so every profile
      in the browser session showed the upload control regardless of manager relationship. The
      negative case (a genuine non-admin, non-manager caller) is instead covered by a new backend
      unit test, `test_get_employee_can_upload_documents_true_for_self_manager_and_admin`, which
      explicitly asserts `can_upload_documents: false` for a non-admin/non-manager caller.
- [x] Overview tab is visually unchanged — same header band, Employment/Contact/Attributes/
      Personal/Additional contacts/Notes cards and Form Submissions accordion, just gated behind
      `activeTab === "overview"` instead of always rendering.

## Acceptance criteria

- [x] No new attendance/leave data model or duplicated balance-computation logic — `EmployeeAttendanceTab`
      calls [[54]]'s exact `/attendance/employees/{id}/today`/`/daily` routes (reusing the
      existing `TodayAttendance`/`DailyLogRow` frontend types, not new ones);
      `EmployeeLeaveTab` calls the *already-existing* `getEmployeeLeaveBalances`/
      `listTeamLeaveRequests` wrappers (no new api.ts functions needed for Leave at all — task's
      Files list assumed they didn't exist yet, but [[57]]'s `EmployeeDetailDrawer.tsx` already
      used them).
- [x] Documents upload control visibility is permission-gated via a new server-computed
      `EmployeeDetailOut.can_upload_documents` field (backend addition, not in this task's
      original file list) — hidden entirely (not disabled) when false.
- [x] `initialTab` routes correctly from both entry points: row click → drawer → "View full
      profile" defaults to `"overview"`; "View attendance"/"View leave" pass `"attendance"`/
      `"leave"` through `onViewProfile`'s new optional second argument.

## Completion notes

- **Backend addition** (surfaced while implementing, not anticipated in this task's Files list):
  `EmployeeDetailOut.can_upload_documents: bool`, computed in `get_employee` via a new
  `_can_manage_employee_documents()` helper in `employees/service.py`. This helper is the same
  admin-or-self-or-manager check [[55]]'s `_require_manager_or_admin_for_employee` already
  enforced server-side for the POST route — refactored so `_require_manager_or_admin_for_employee`
  now calls it and raises, rather than duplicating the logic, so there's exactly one
  implementation of "can this caller touch this employee's documents."
- **Reuse over reimplementation**: `BalanceCards` was exported from `Employee/MyLeave.tsx`
  (previously module-private) rather than rebuilding the balance-card UI a second time, per the
  task's own instruction. `EmployeeLeaveTab`'s recent-requests row list is a new, small,
  similarly-styled component rather than an extraction from `hrManager/Leave.tsx` — that file's
  row rendering is inline in one large component, not a separable piece, so extracting it would
  have meant a riskier refactor of the live manager-approval screen for a read-only reuse; the
  new component matches its visual pattern (same status-pill styling) instead.
- **Day/Week/Month ranges**: no existing frontend precedent computed real ISO-week/calendar-month
  ranges (the only existing "Day/Week/Month" toggle, in `hrManager/Attendance.tsx`, is mock data
  with no real range logic) — implemented directly with plain `Date` math in
  `EmployeeAttendanceTab.tsx`, matching this codebase's no-date-library convention. No prev/next
  navigation was added (not requested, no existing pattern to follow); always shows the current
  week/month.
- Files added: `EmployeeAttendanceTab.tsx`, `EmployeeLeaveTab.tsx`, `EmployeeDocumentsTab.tsx`
  under `shared/`, per the task's own suggested split.

Completed: 2026-08-19
