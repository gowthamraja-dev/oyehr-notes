---
task: 251
title: Requests inbox — WFH rows, approve / reject
status: done
depends_on: [247]
---

# 251 — Requests inbox — WFH rows, approve / reject

Part of `.plans/shift-wfh-plan.md`. Backend contract: task 247 (`GET /attendance/requests?request_type=`,
`POST /requests/{id}/approve` returning the range result, `POST /requests/{id}/reject` with a reason).

## Scope
Managers (direct reports) and admins (tenant) see WFH requests next to Regularization in the existing inbox and
approve or reject them. Plan §7 assumes **one combined inbox with a type filter**; keep the page name unless the
team agrees to rename it ("Requests inbox").

## Files
- `frontend/src/dashboards/hrManager/RegularizationInbox.tsx` (+ the manager dashboard registration in
  `hrManager/index.tsx` if the label changes) — type filter (All / Regularization / WFH), WFH row: type chip,
  employee, from–to range (dd-MMM-yy), reason, Approve / Reject. Reject requires a reason (reuse the existing
  reject dialog). No punch comparison panel for WFH (that is Regularization's recorded-vs-requested view).
- After Approve: toast "Work location set to <remote site> for N days", and when some days were skipped
  (locked / outside employment / no standing shift) open a summary built from `RangeResultBody`
  (`dashboards/shared/ShiftRangeResult.tsx`) — week-off / already-set are routine and don't open it.
- If the tenant has no remote site the server refuses the approval; show its message, leave the request Pending.
- `frontend/src/lib/api.ts` — widen manager request types and the approve result.
- Shimmer skeleton uses shared primitives; Tailwind only; `useConfirm` for any destructive confirm.

## Acceptance criteria
- [x] Inbox lists WFH requests (scoped as the API scopes them) with a working type filter
- [x] Approve shows the toast and the skipped-days summary; reject needs a reason; actioned rows update in place
- [x] No-remote-site refusal is shown clearly and leaves the request Pending
- [x] `tsc` + ESLint clean on changed files; headless-browser smoke against a local DB (raise → approve → roster shows
      the remote badge + WFH marker; raise → reject → nothing changes on the roster)

## Implementation notes (24-Oct-26)
- **`lib/api.ts`**: `ManagerRequestRow` is now `(RegularizationRequest | WfhRequest) & {employee}`; `ManagerRequestDetail` is a union
  (regularization + recorded/requested, or the WFH row alone); `WfhApproveResult` + `isWfhApproveResult`; `approveRequest` returns
  `ApproveResult | WfhApproveResult`. `listManagerRequests(status, requestType)` default stays `"Regularization"` (so nothing else
  changed behaviour); the inbox passes its filter, and the **HR Admin dashboard's "N attendance requests awaiting your approval"**
  card now passes `"All"` so it counts WFH too (verified: 2 with one regularization + one WFH pending).
- **`RegularizationInbox.tsx`**: the disabled type select is now a working filter (All types / Regularization / Work from home,
  default All); WFH rows show "Work from home", the range (`formatRangeLabel`) and "N days"; Details modal for WFH ("Work-from-home
  request", Days instead of Punch, no comparison table, an effect note); approve (inline or from Details) toasts "Work location set to
  <site> for N days" and opens `RangeResultModal` only when `hasNotableSkips` (locked / outside employment / no standing shift /
  manual) — "week off" and "unchanged" are routine; reject unchanged (reason required); server refusals (e.g. no remote site) arrive as
  the existing error toast / inline error and leave the request Pending. Date column widened so a range doesn't wrap.
- **`shared/ShiftRangeResult.tsx`**: `RangeResultBody` / `hasNotableSkips` take a `RangeResultLike` (`assigned_count` + `per_employee`) so
  the WFH approval doesn't have to fake the other counts.
- Page name unchanged ("Regularization Inbox" in nav + title) per the plan's open decision — it now lists WFH too; renaming it is a
  one-line change in `hrManager/index.tsx` if the team wants it.
- Verification: `tsc` clean; ESLint on the inbox has no errors. Headless-browser smoke against a local DB (never the shared one) **19/19**:
  type filter all/WFH/regularization, WFH detail (no Recorded / Punch — checked case-insensitively, the header is CSS-uppercased), inline approve
  (toast, no panel, DB: request Approved, the 3 days moved, neighbours untouched, no attendance or punch rows), approve from Details with a locked
  day and a no-shift day (panel names both, only the middle day moved), reject (reason required, locations untouched, shows under Rejected),
  no remote site (server message, stays Pending, nothing moved), regularization detail unchanged. Screenshots `60`–`64-inbox-*.png`.
- Docs: `attendance/manager-approvals.md` (filters / WFH approval paragraph), `attendance/api-and-pages.md` (inbox page row).
- Not done: the employee notification on approve/reject (Regularization has none either).
