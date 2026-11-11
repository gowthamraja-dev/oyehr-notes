---
task: 330
title: Admin sets approval workflows for attendance requests in Approval Setup
status: done
depends_on: [329]
---

# 330 — Admin sets approval workflows for attendance requests in Approval Setup

## Scope
`frontend/src/dashboards/hrAdmin/ApprovalSetup.tsx` renders one card per workflow today (`LeaveRoutingCard`,
`ExpenseRoutingCard`), edited by the organisation's Admin only. Add the same for the three attendance request types
from task 329 so the Admin can decide who approves each one, and see clearly which are not set.

- Three cards (or one card with three sections): Regularization requests, Work from home requests, Shift change requests.
  Model on `ExpenseRoutingCard.tsx` / `LeaveRoutingCard.tsx` and the backend `leave/approval_routing.py` pattern:
  `GET/PUT /approvals/attendance-routing/{type}` returning `{ configured, version_no, published_at, published_by, can_edit, steps }`,
  `can_edit` true only for the Admin (same gate as leave routing). Steps offered: Reporting manager, Department head,
  HR, optionally both (reporting manager then HR). Keep to what the existing pipeline policy supports.
- **Not-set state is explicit**: a card whose type has no live version shows an amber "Not set" pill and the line
  "Employees can't submit <type> requests until you choose who approves them." with a primary "Set approval" action.
  Set state shows the steps, version, who published and when, plus the existing "Check who would approve"
  simulation (`ApprovalTryIt`, `tryIt("ATTENDANCE_…")` by workflow code).
- Non-Admin viewers (HR Manager etc.) who open the page see the cards read-only with "Ask your Admin to change this."
- Deep link: My approvals' "Set up workflow" button (task 331) opens this page scrolled to the right card
  (`?type=wfh` style param or the existing openTarget mechanism).
- Saving publishes a new version only for new requests; requests already running keep the version they started on.
- Activity log: publishing writes `log_activity` like the leave routing save does (`hrms-activity-logging`).
- Tailwind only, shimmer skeleton from shared primitives, no native `confirm()`.

## Files
- `frontend/src/dashboards/hrAdmin/ApprovalSetup.tsx`, new `AttendanceRoutingCard.tsx`
- `frontend/src/lib/api.ts` (`getAttendanceRouting`, `saveAttendanceRouting`)
- `backend/app/modules/attendance/approval_routing.py` (new), `backend/app/modules/approvals/router.py` (routes)
- `backend/app/tests/modules/test_attendance_approval_routing.py`

## Acceptance criteria
- [ ] Admin can set, change and see each of the three workflows; the card shows Not set until then.
- [ ] A non-Admin gets read-only cards and the API refuses their PUT with 403.
- [x] Publishing a new version doesn't alter requests already in flight.
- [x] Simulation works for each live type.
- [x] Tests: happy path, 403 for non-Admin, tenant scoping, validation of steps.

## Progress (2026-11-06)
Built; backend tested. **Not moved to done**: the Approval Setup page itself hasn't been looked at in a browser (needs the dev stack,
which I don't start), and two criteria are only covered at the API level.
- Backend: `attendance/approval_routing.py` (new, modelled on `leave/approval_routing.py`), `GET/PUT /approvals/attendance-routing/{kind}`
  in `approvals/router.py`, `AttendanceRoutingIn/Out` in `approvals/schemas.py`, a `slug` on each `approval_pipeline.Kind`.
  Saving publishes the type's workflow through `approval_seed.republish` (the first save sets the type up). Admin only
  (`finance_roles` duty `APPROVAL_ROUTING`); viewing needs Approval Setup access (SETTING READ or Admin). Logged as
  `ATTENDANCE_ROUTING_CHANGED`. The response carries `enforced` (false while approval workflows are off, so the card doesn't claim
  employees are blocked).
- Frontend: `hrAdmin/AttendanceRoutingCard.tsx` (new), three cards in `hrAdmin/ApprovalSetup.tsx` (Not set pill and "Employees can't
  submit ... until you set who approves them" when unset; read-only with "Ask your Admin" for non-Admins; confirm dialog before
  publishing), `getAttendanceRouting` / `saveAttendanceRouting` in `lib/api.ts`. "Check who would approve" no longer asks for leave-style
  facts on attendance workflows. `npx tsc --noEmit` and eslint are clean for the touched files.
- Deep link: `openApprovalSetupFor(kind)` (now in `lib/approvalSetupTarget.ts`, moved there by task 331) scrolls to and rings the card; My
  approvals' Admin notice calls it. It only works inside the HR Admin dashboard (the only one with an Approval Setup page).
- Tests: `app/tests/modules/test_attendance_approval_routing.py`, 13 passing (with the 24 from 329: 37). Covers not-configured reading,
  Admin-only save + log, no access without Approval Setup, first save lets employees submit, new version and in-flight requests keep their
  route, simulation per type, publishing refused while workflows are off, unknown kind 404, the routes (401/200/404/403).
- Still open:
  - [ ] Look at Approval Setup as an Admin and as a non-Admin in the browser (Not set pill, three cards, save, read-only state).
  - [ ] Role 22 (Admin) reaching Approval Setup in the real HR Admin dashboard: tested through the service with a role-22 principal, not
    through a logged-in session.

Completed: 2026-11-10
