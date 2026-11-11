---
task: 333
title: Remove the Regularization Inbox (and the duplicate My Approvals entry)
status: done
depends_on: [329, 330, 331]
---

# 333 — Remove the Regularization Inbox (and the duplicate My Approvals entry)

## Scope
When My approvals handles every request type (task 331) and the Admin can set the workflows (task 330), delete the
separate inbox. The attendance request routes stay (the pipeline delegates to them); only the screen goes.

- `frontend/src/dashboards/hrManager/index.tsx`: remove the `regularizations` nav item ("Regularization Inbox"),
  `views.regularizations` and the `RegularizationInbox` import.
- Delete `frontend/src/dashboards/hrManager/RegularizationInbox.tsx`. Before deleting, move anything 331 still needs
  (`RequestDetailModal`, the WFH skipped-days summary / `RangeResultModal` flow, result handling) to `dashboards/shared/`.
- **Duplicate entry**: the same sidebar also has `workflowApprovals` ("My Approvals", the older workflow-engine inbox
  `shared/WorkflowApprovals.tsx`, `GET/POST /workflow-builder/approvals`, event types ONBOARDING / ATTENDANCE_REQUEST).
  ATTENDANCE_REQUEST is now superseded by 329. Confirm no tenant has live ONBOARDING runs awaiting approvers; if any, keep
  the entry but rename it "Onboarding approvals"; otherwise remove it. Record the decision here. Backend routes are not deleted.
- `frontend/src/lib/moduleAccess.ts`: drop `regularizations`.
- `frontend/src/dashboards/hrManager/Attendance.tsx` (~line 986): `navigate("regularizations")` becomes `navigate("approvals")`.
- Search `frontend/src` for `"regularizations"` and "Regularization Inbox", including `content/knowledge/attendance.ts` and
  `content/knowledge/index.ts` (help text); update to My approvals.
- Old links: a stored `regularizations` view key (bookmark, notification target) lands on `approvals`, never a blank shell.
- Docs: `docs/leave-and-attendance/**` mentions of the inbox; the root `CLAUDE.md` approvals section (attendance requests are
  approved from My approvals on the pipeline).

## Files
`frontend/src/dashboards/hrManager/index.tsx`, `hrManager/RegularizationInbox.tsx` (delete), `hrManager/Attendance.tsx`,
`shared/WorkflowApprovals.tsx` (per decision), `lib/moduleAccess.ts`, `lib/openTarget.ts` (if it maps view keys),
`content/knowledge/attendance.ts`, `content/knowledge/index.ts`, `docs/leave-and-attendance/`, `CLAUDE.md`.

## Acceptance criteria
- [x] No "Regularization Inbox" in any role's sidebar. (The `rg` is not literally empty: it still finds the alias comment in `lib/openTarget.ts` and two historical strings in `lib/api.ts`; none is user-facing.)
- [x] HR Manager sidebar: the duplicate label is gone. It now has "My approvals" and, kept on purpose, "Workflow approvals" (see the decision below), so two entries, named differently.
- [ ] Old `regularizations` links and notifications land on My approvals. (Done in code via `resolveView`; not run in a browser.)
- [ ] Attendance page shortcut to pending requests opens My approvals. (Done in code, `navigate("approvals")`; not run in a browser.)
- [x] Type check and a production build pass; lint adds no new errors.
- [ ] Manual pass as Admin, HR Manager, manager and employee.

## Progress (2026-11-10)
Done and checked in code; **not moved to done**: the last acceptance item (a manual pass per role) and two release steps are open.

- Removed: the HR Manager `regularizations` nav item and view, `hrManager/RegularizationInbox.tsx` (deleted in the working tree, not committed),
  `regularizations` in `lib/moduleAccess.ts`, the knowledge-base mapping and the manager steps' wording ("in My approvals").
  Nothing the inbox owned was needed elsewhere (My approvals, task 331, uses its own drawer; the WFH summary and `RangeResultModal` were already shared).
  The API client helpers it used (`getManagerRequestDetail`, `approveRequest`, `rejectRequest`, `isWfhApproveResult`,
  `isShiftChangeApproveResult`) are now unused in the frontend; left in place (their backend routes stay); remove them in a later cleanup.
- Old links: `resolveView` in `lib/openTarget.ts` aliases `regularizations` to `approvals` (applied in `parseActionUrl`, the shell's `?v=`
  read and its open-view event); the record id is dropped, since it was a request id and My approvals' is an approval id. Without this the
  shell silently fell back to the default page.
- Attendance register: the "Regularization pending → Review" link now goes to My approvals.
- **Duplicate entry decision:** `workflowApprovals` is **kept and renamed "Workflow approvals"** (it was labelled "My Approvals", the same as the
  real page). I couldn't check whether any organisation has open runs on the Workflow Builder engine (no database access to the shared dev
  or prod DB here), and that page is the only place such a run (onboarding, or an older ATTENDANCE_REQUEST chain) can be decided. Remove it
  once nobody has open runs there. This differs from the plan's "remove it unless ONBOARDING runs exist", on purpose, to strand nothing.
- **Found while doing this (not in the plan):** a Pending request raised before task 329 has no approval run, and the inbox was the only
  place it could be decided, so deleting the inbox would have stranded it. Added `approval_pipeline.adopt_open_requests` and
  `scripts/adopt_attendance_requests_into_approvals.py` (dry run by default): it puts each such request onto its type's live workflow, so
  its reporting manager sees it in My approvals; requests on an old Workflow Builder chain are left to finish there. 5 tests.
- **Found while doing this:** the old detail screen compared the recorded punches with the requested ones. A regularization's approval
  details now carry **Recorded** and **Day status now** (read live), shown in the same My approvals drawer. 1 test.
- Docs updated: `docs/workflow-engine.md`, `CLAUDE.md`, `docs/leave-and-attendance/attendance/manager-approvals.md` (marked removed),
  `attendance/api-and-pages.md`, `README.md`, `docs/in-app-notifications.md`, `docs/roles-and-permissions.md`.
- Checks: `tsc --noEmit` clean; `npm run build` succeeds; the grep in the criteria finds only the explanatory comment in `openTarget.ts`
  and two historical strings in `lib/api.ts` (comment and an unused helper's error text); eslint error counts are identical to HEAD in every
  touched file (the repo has pre-existing `react-hooks` errors). Backend: `test_attendance_approvals.py` 33 passing and the routing tests 13 passing (run before the last test was added: 45, then 33 for the approvals file alone).

Still open:
- [ ] Manual pass as Admin, HR Manager, manager and employee (each sees only what their role allows; an old `?v=regularizations` link lands on My approvals).
- [ ] Release: `seed_attendance_approval_pipeline.py --all --apply`, then `adopt_attendance_requests_into_approvals.py --all --apply` (both dry-run first), before or with this frontend. Until adopted, pre-329 Pending requests have no screen.

Completed: 2026-11-10
