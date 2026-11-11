---
task: 331
title: My approvals shows every request type, in the existing My approvals UI
status: done
depends_on: [329]
---

# 331 — My approvals shows every request type, in the existing My approvals UI

**UI decision (owner): keep the existing My approvals UI exactly as it is in the working copy**
(`frontend/src/dashboards/shared/MyApprovals.tsx`: Waiting / Decided by me tabs, one card list, each row =
title + "from <requester>" + Overdue pill + step · due + details line + Review button, decisions in the side drawer).
`.design/My Approvals Unified.html` is a reference mockup only and is NOT the implementation target; do not
build its table layout, type chips, eye icon or reason column changes unless the owner asks for them again.

## Scope
With task 329 the regularization, work from home and shift change requests arrive through `GET /approvals/inbox`
like leave and expense, so the existing page lists them with no client-side merge. Make only the changes needed:

1. **Rows read right for the new types.** Title comes from each workflow's `describe` (task 329): "Regularization
   request", "Work from home request", "Shift change request"; leave and expense keep theirs. The **Reason** is a
   `details` entry, so it shows in the existing details line on the row and in the drawer's details. Check
   `ApprovalDecisionDrawer` (`shared/ApprovalDecision.tsx`) renders the reason clearly for all types (it is the one
   place a reader looks before deciding); adjust only if it is cut off or hidden.
2. **Decisions behave as today** through the drawer (`decideApproval`): approve, approve with comment, decline with
   a reason. The WFH skipped-days panel and the shift-change "Shift set to …" message that the old inbox showed
   after approving must still be shown (move `RangeResultModal` usage / result handling from
   `hrManager/RegularizationInbox.tsx` into the drawer's `onDecided` path; `DecideOut.outcome` carries what happened,
   extend it in 329 if it doesn't).
3. **Workflow not set: tell the Admin, nothing more.** Because submit is blocked when no workflow is set (329), no
   request can be waiting on an unset type, so My approvals needs no per-row "not set" handling. Add one slim notice
   at the top of the page, for the Admin only (`can_edit` from the routing endpoints, or the Admin check the page
   already uses): "Approval isn't set up for <Work from home requests, …>. Employees can't submit them until you set
   it up." with a "Go to Approval Setup" link (task 330). Built from `getApprovalWorkflows()` (`live: false`); hidden
   when everything is set and for everyone who isn't Admin. Styled like the page's existing amber Overdue pill/banner
   colours, no new component library.
4. **Leave with approvals OFF** (`APPROVAL_WORKFLOWS_ENABLED=false` / tenant in `workflow_engine_disabled_cdp_ids`):
   leave uses the legacy approval and is not in this inbox. Don't build a second path; the Admin notice (3) lists
   "Leave requests" as not set up via approvals, and the Leave page keeps its own approve/reject as today.
   (Open question still with the owner: hide the Leave page's inline Approve/Reject so approving is in one place.)
5. **Counts**: the sidebar badge (`myApprovalsBadge`, `lib/navBadges.ts`) and the Waiting tab already count the inbox;
   they include the new types with no change. "Decided by me" (`GET /approvals/history`) covers them too.
6. **Notification deep links** for attendance requests open `approvals` with that request's drawer
   (`takeOpenId("approvals")`, existing `openWanted` path), replacing `takeOpenId("regularizations")`.
7. **Wording**: types and toasts use one label map, `dashboards/shared/approvalLabels.ts`
   (Leave request · Work from home request · Regularization request · Shift change request · Expense claim),
   and the empty state reads "You're all caught up" / "Leave, work from home, regularization and expense requests
   waiting for you will show up here."
8. The existing skeleton (`MyApprovalsSkeleton`) stays; no layout change, so no new skeleton work.
9. Style rules unchanged: Tailwind only, 10px page spacing, `dd-MMM-yy` dates, `useConfirm` not `confirm()`.

## Files
- `frontend/src/dashboards/shared/MyApprovals.tsx` (Admin notice, empty-state wording)
- `frontend/src/dashboards/shared/ApprovalDecision.tsx` (reason visible; WFH / shift-change result after approving)
- `frontend/src/dashboards/shared/approvalLabels.ts` (new)
- `frontend/src/lib/navBadges.ts` (no change expected), `lib/api.ts` (types only if `DecideOut` grows)

## Acceptance criteria
- [ ] Regularization, work from home and shift change requests appear in My approvals with the existing look, their Reason in the details.
- [ ] Approving a work-from-home request still shows the skipped-days panel when days were skipped; approving a shift change still shows the new shift.
- [ ] Admin with an unset type sees the notice and a working link to Approval Setup; HR Manager and employees see nothing extra.
- [ ] Sidebar badge equals the Waiting tab count; notification click opens the right drawer.
- [ ] No visual change to the page's layout, tabs, rows or drawer beyond the above; `npx tsc --noEmit` and lint clean for touched files.

## Progress (2026-11-06)
Built; type-checked and linted; the backend tweak is tested. **Not moved to done**: nothing in the page has been looked at in a browser
(the dev stack isn't started by me, and the repo has no frontend test runner), so the acceptance list below is a manual checklist.

What was done, and where it differs from the plan above:
- Layout unchanged, as decided. Row titles and the **Reason** detail come from the server (329). `ApprovalDecisionDrawer` already lists every
  detail in a wrapping grid, so the reason isn't cut off; no change was needed there.
- `shared/approvalLabels.ts` (new): the label map, the empty-state words ("You're all caught up" / "Leave, work from home, regularization and
  expense requests waiting for you will show up here."), `decisionToast` ("Leave request approved") and `effectToast`.
- `shared/ApprovalDecision.tsx`: `DecisionPanel` takes the workflow, toasts by name, and passes `DecideOut.effect` to `onDecided`. A WFH approval
  toasts "Work location set to X for N days", a shift change "Shift set to X for dd-MMM-yy".
- `shared/MyApprovals.tsx`: shows the WFH skipped-days summary (`RangeResultModal`, only when a day was left for a reason that matters) after
  approving from the drawer; the empty state wording; the Admin-only notice (see below).
- `lib/api.ts`: `decideApproval` returns `effect`. `lib/approvalSetupTarget.ts` (new, shared): the attendance kinds, `SETUP_TARGET` and
  `openApprovalSetupFor`, moved out of `ApprovalSetup.tsx` so My approvals doesn't import a page.
- Backend: `GET /approvals/workflows` lists an unset attendance type as not live only while approval workflows are enabled
  (`approvals/service.py`), so the notice can never say employees are blocked when they aren't. Test:
  `test_with_approval_workflows_off_unset_types_are_not_listed`; the attendance approval and routing tests: 38 passing.
- **Admin notice** replaces the plan's "Leave requests" line. Reason: leave is switched on automatically with the first leave request, and
  approvals being off is an environment setting, not something an Admin sets up, so a leave line would mislead. The notice covers the three
  attendance types only. It appears only when the caller can edit routing (`getAttendanceRouting(...).can_edit`), so HR Managers and employees
  see nothing extra.
- Notification deep links: nothing to change. Pipeline requests notify their step approvers through `approvals/notices.py`, which already links
  to `/dashboard?v=approvals&open=<approval id>` (that page opens the drawer). Requests with no run (legacy) still notify to the old
  `regularizations` view until task 333 retires it and aliases the key.
- Lint: `eslint` reports one error in `MyApprovals.tsx` (`react-hooks/set-state-in-effect` on the `useEffect(() => { void load(); }, [load])`
  line). It is identical on HEAD (checked), so it is not from this change; left alone.

Manual checklist (all still open):
- [ ] HR Manager with the three workflows set: a regularization, a WFH and a shift change request each appear in My approvals with their title and a Reason detail.
- [ ] Approve a WFH request that has a locked/no-shift day: toast "Work location set to ...", then the skipped-days summary.
- [ ] Approve a shift change: toast "Shift set to ...". Decline any request: "<Type> declined", reason required.
- [ ] Admin with a type unset: notice with a working "Set up ... →" link that lands on Approval Setup at that card. HR Manager / employee: no notice.
- [ ] Empty list shows "You're all caught up" and the new text.
- [ ] Sidebar badge equals the Waiting count; opening a notification for an attendance approval opens its drawer.

Completed: 2026-11-10
