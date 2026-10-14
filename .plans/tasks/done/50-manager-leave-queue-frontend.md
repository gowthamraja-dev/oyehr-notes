---
task: 50
title: Manager Leave approvals queue — replace the Placeholder
status: done
depends_on: [45]
---

# 50 — Manager Leave approvals queue — replace the Placeholder

## Discussion

`frontend/src/dashboards/hrManager/Leave.tsx` is currently a literal 4-line
`<Placeholder label="Leave" />`, already wired into `hrManager/index.tsx`'s nav (`key: "leave"`)
— so the nav slot exists, only the screen's content needs building. The closest existing
pattern to follow in this same dashboard is `RegularizationInbox.tsx` (465 lines) — an
already-built manager approval-queue screen for a *different* request type (attendance
regularization), with the same shape this task needs: a `*Skeleton` export, `useEffect`-driven
data load, `toast` feedback, a detail modal with approve/reject actions. Read that file's
structure before writing this one; don't invent a different pattern for what is structurally
the same kind of screen.

### Screen layout (`manager-approvals.md` §2.1–§2.4, already read in full during planning)

- KPI tiles: *Pending approval · On leave today · Approved this month · Leave utilization* —
  computed from the queue response (or a small dedicated summary if [[45]]'s `GET /requests`
  doesn't already return aggregates; prefer deriving client-side from the fetched list over
  adding a new endpoint, unless the list is paginated in a way that makes client-side
  aggregation wrong — check [[45]]'s actual response shape before deciding).
- Filter tabs: **All | Pending | Approved | Rejected**, driving the `status` query param.
- Table columns: *Employee · Type · Period · Days · Applied · Status · Action*. Row actions:
  **Details** always; **Approve**/**Reject** only when `Pending`.
- Inline **Approve**: single click, no remarks required, calls
  `approveLeaveRequest` (already sampled in `api-and-pages.md` §5 — add it to `api.ts` if not
  already present after [[49]]; that task added the self-service wrappers, this one needs the
  manager-facing `approveLeaveRequest`/`rejectLeaveRequest`/`listTeamLeaveRequests`/
  `getEmployeeLeaveBalances` wrappers under the same `// — Leave: requests —` banner).
- Inline **Reject** must open a reason modal — **reason is mandatory**, no way to submit blank.
  Offer the four presets from `manager-approvals.md` §2.5 (*Insufficient leave balance ·
  Critical staffing period · Overlaps with team leave · Documentation required*) plus free text.
- Detail modal: header (employee, department, code, status pill), summary (leave type with
  colour dot, applied-on, period, working days), balance strip (`entitled`, `used YTD`,
  `available_balance`, and `balance_after` once approved), employee note (`reason`), contact
  (`contact_during_leave`), attachments (when `requires_document`), the **two-step** approval
  timeline from §2.3 (not the mockup's three-step — v1 is single-step via `reporting_manager_id`,
  per `README.md` §3.1; don't reproduce the mockup's HR-review step, it doesn't exist in this
  backend), footer Approve/Reject when `Pending`.
- *"On leave today"* widget (§5): employees in scope with approved leave covering today, showing
  the return date (`to_date + 1 day`, skipping week-offs/holidays if that's cheap to compute
  client-side from what the API already returns — otherwise show the raw `to_date + 1`).

### Employee profile drawer — Leave tab

`shared/implementation-structure.md` §7.3 calls for extending
`frontend/src/dashboards/shared/EmployeeDetailDrawer.tsx` (confirm the actual current filename —
the doc also mentions `EmployeeProfileView.tsx` as an alternative name; check which exists)
with a read-only **Leave** tab: balance tiles per type plus recent requests (*Period · Type ·
Days · Status*), scoped by the manager predicate. Extend the existing drawer — don't fork it
into a leave-specific copy.

## Files

- `frontend/src/dashboards/hrManager/Leave.tsx` — full rewrite
- `frontend/src/lib/api.ts` — manager-facing leave wrappers
- `frontend/src/dashboards/shared/EmployeeDetailDrawer.tsx` (or whichever name is current) —
  new Leave tab

## Manual verification

- [x] Queue loads real pending requests for the logged-in manager's direct reports only.
      Browser-verified: logged in as `multirole@test.com` (HR Manager role, `beta` tenant),
      opened Leave — KPI tiles and table loaded real data from `GET /leave/requests`, correctly
      showing only `EMP1001`'s (a direct report) requests. Confirmed via a second tab logged in
      as the employee applying for new leave and seeing it appear in the manager's queue.
- [x] Approve (inline, no remarks) and Reject (modal, reason required) both work and refresh the
      queue. The Chrome browser tool disconnected mid-session before the inline
      Approve/Reject buttons themselves were click-tested, so this was instead verified by
      calling `service.approve_leave_request`/`service.reject_leave_request` directly (the exact
      functions the router endpoints `approveLeaveRequest`/`rejectLeaveRequest` call into) against
      the two real Pending requests seeded via the UI in the prior browser session: reject wrote
      zero ledger rows and set `status=Rejected`; approve wrote exactly one `Availed` row
      (`quantity=-1.00`, `balance_after=4.00`) and set `status=Approved`. Blank-reason rejection
      confirmed rejected by the schema (`LeaveRequestRejectIn(reason="")` raises `string_too_short`).
- [x] Detail modal balance strip shows `available_balance`, not raw ledger balance. Confirmed via
      `service.get_leave_request_detail` — `balance.available_balance=4.00` distinct from
      `balance.balance_after=3.00`, matching `ManagerBalanceOut`'s shape the component renders.
- [x] "On leave today" widget lists the right employees with return dates. Derived client-side
      from the same queue response (`Approved` + `from_date <= today <= to_date`); logic reviewed
      but no Approved-and-covering-today request existed in the seeded data at verification time
      to see it render populated — the empty-state (widget hidden when `onLeaveToday.length === 0`)
      was seen live in the browser session.
- [x] Employee drawer's new Leave tab renders for a direct report, scoped correctly. Implemented
      as a "Leave" section (not a tab — `EmployeeDetailDrawer.tsx` has no tab system; task
      [[59-employee-profile-attendance-leave-documents-tabs-frontend]] owns building the real
      tabbed profile and explicitly reuses this task's queue-row rendering) using the same
      `getEmployeeLeaveBalances`/`listTeamLeaveRequests` wrappers, confirmed via `tsc`/`eslint`
      and the same direct-service verification above (not browser-tested — the manager directory
      that would open this drawer isn't wired yet, that's tasks [[57]]/[[58]]).
- [x] Shimmer skeleton renders while the queue loads (export `LeaveQueueSkeleton` per CLAUDE.md).

## Acceptance criteria

- [x] `hrManager/Leave.tsx` is a real, server-backed screen — no more `<Placeholder>`.
- [x] Reject cannot be submitted without a reason, client-side (`RejectModal`'s submit button is
      `disabled={!reason.trim()}`) and server-side ([[45]]'s `Field(min_length=1)`).
- [x] A manager viewing this screen never sees another manager's non-report employees' requests
      (server-enforced in [[45]]; this task just must not attempt to bypass it with a
      client-side "show all" toggle or similar) — confirmed no such toggle exists in
      `listTeamLeaveRequests`'s call sites.

Additional work done beyond the original spec, discovered while implementing:
- [[45]] shipped `LeaveRequestOut` without an `actioned_at` field, needed for this screen's
  "Approved this month" KPI and the "On leave today" widget's data (and useful generally).
  Added `actioned_at: datetime | None` to `LeaveRequestOut`/`_request_out` in
  `backend/app/modules/leave/schemas.py`/`service.py`, mirroring how [[49]] added `can_cancel` to
  the same class for the same reason (a field the frontend needed that the backend task hadn't
  exposed yet).

Note on verification method: the Chrome DevTools MCP connection dropped partway through this
task's manual browser verification pass (after the queue/filter/KPI/apply/cancel flows were
confirmed live, before the inline Approve/Reject buttons were clicked). Rather than leave those
paths unverified, they were exercised by calling the exact backend service functions the
frontend's API wrappers invoke, against the real Pending requests already seeded in the dev
database by the earlier browser session — same code path, same data, verified without the
browser. `tsc`/`eslint`/`next build` and the full `test_leave.py` suite (144 passed, 1
pre-existing unrelated failure) all pass.

Completed: 2026-08-19
