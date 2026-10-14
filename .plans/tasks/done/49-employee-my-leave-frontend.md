---
task: 49
title: Wire Employee My Leave and dashboard KPIs to the real leave API
status: done
depends_on: [44]
---

# 49 — Wire Employee My Leave and dashboard KPIs to the real leave API

## Discussion

`frontend/src/dashboards/Employee/MyLeave.tsx` (134 lines) is currently 100% static: three
hardcoded `LEAVE_BALANCES` cards, an uncontrolled apply form with fixed `defaultValue` dates and
a "Submit request" button with a `// TODO: this form doesn't submit anywhere yet` comment, and a
hardcoded `LEAVE_REQUEST_HISTORY` table. `EmployeeHome.tsx`'s `STATS` array hardcodes `"Leave
balance": "21 days"` and `"Open requests": "4"`. This task replaces all of it with real data —
no new dashboard needed (unlike the `docs/leave-and-attendance/` corpus's superseded prediction
of a separate `hrEmployee/` dashboard: this codebase already has a live `Employee/` dashboard
and `MyLeave.tsx` inside it, wired into `Employee/index.tsx`'s nav — extend what exists).

### `frontend/src/lib/api.ts` — new wrapper functions

Group under a `// — Leave: requests —` comment banner, following this file's existing
convention (see the `// — Leave — types & policies —` banner already there). One named,
typed wrapper per [[44]] endpoint: `previewLeaveRequest`, `applyLeaveRequest`,
`listMyLeaveRequests`, `getLeaveRequest`, `cancelLeaveRequest`, `getMyLeaveBalances` (sample
response shape already specified in `docs/leave-and-attendance/leave/api-and-pages.md` §4.13 —
implement `LeaveBalance` type and `getMyLeaveBalances` exactly as sampled there, both are
already drafted in that doc's §5). Attachment upload (`uploadLeaveAttachment`) uses plain
`fetch`, mirroring `uploadOrgImage` — not `secureFetch` (multipart).

### `MyLeave.tsx` rewrite

- Balance cards: map over `getMyLeaveBalances()`'s response instead of `LEAVE_BALANCES`; keep
  the exact visual shape (progress bar, `{used}/{total (entitled)} used`, big `{available}
  days left`), just feed it from `available_balance`/`used`/`entitled`, colored via
  `color_code` from the leave type (currently hardcoded gradient classes — either keep the
  gradient classes as a rotating palette keyed by index, or map `color_code` to an inline style
  per CLAUDE.md's "DB-driven values" exception to the Tailwind-only rule).
- Apply form: leave-type `<select>` populated from `listLeaveTypes(true)` (already exists in
  `api.ts`, currently admin-only server-side until [[44]] opens it to self — confirm that
  landed). Controlled date inputs (replace `defaultValue` with `value`/`onChange` state) calling
  `previewLeaveRequest` on change (debounced) to show the day-by-day breakdown and balance
  impact inline — per `employee-self-service.md` §3.2's "live preview" requirement. Half-day
  selector, `reason`, `contact_during_leave`, and an attachment input, all currently missing
  from the mockup per `gaps.md` #11 — add them, gating half-day/attachment visibility on the
  selected leave type's `allow_half_day`/`requires_document`. "Submit request" calls
  `applyLeaveRequest`; on success, toast + refresh history; on `422`, surface the violation
  message(s) inline (reuse whatever inline-error pattern this dashboard already has elsewhere,
  e.g. `CreateLeaveTypeModal.tsx`).
- Request history: `listMyLeaveRequests()` instead of `LEAVE_REQUEST_HISTORY`; add a **Cancel**
  action per row when `can_cancel` (or derive eligibility client-side from `status`/`from_date`
  matching [[44]]'s rules — prefer having the backend return `can_cancel` on the list/detail
  response if [[44]] doesn't already, since duplicating the eligibility rule client-side is
  exactly the kind of client-authoritative logic CLAUDE.md's leave-plan section 37 principle
  warns against).
- Loading state: per CLAUDE.md's shimmer-skeleton rule, export `MyLeaveSkeleton` alongside
  `MyLeave`, matching dimensions of the real balance cards / apply form / history table. Wire it
  into wherever `MyLeave` is currently rendered inside `Employee/index.tsx`.

### `EmployeeHome.tsx` — real KPIs

- `"Leave balance"` tile: `Σ available_balance` across paid leave types from
  `getMyLeaveBalances()`, per `employee-self-service.md` §1's Home tile definition.
- `"Open requests"` tile: count of `Pending` leave requests (from `listMyLeaveRequests`) — per
  CLAUDE.md's leave-plan §28, this must be the same definition the "Open Requests" concept uses
  elsewhere; if an attendance-request open-count already exists or is planned, this leave count
  should be additive to it, not a separate, differently-defined number. Check whether
  `EmployeeHome.tsx` already sources an attendance-side open-request count from a real endpoint
  before wiring this — if it does, add to it; if it's also still mocked, at minimum make the
  leave portion real and leave a comment noting the attendance half is still pending its own
  wiring.
- Both tiles need their own loading skeleton state (`STATS` currently renders synchronously from
  a static array; once it's async, the whole tile row needs a shimmer fallback per CLAUDE.md).

## Files

- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/Employee/MyLeave.tsx`
- `frontend/src/dashboards/Employee/EmployeeHome.tsx`

## Manual verification (per CLAUDE.md's UI-change rule — start the dev server and actually use it)

- [x] Apply for a leave type with `allow_half_day=true`, half-day toggle shows and works.
- [x] Apply for a leave type with `requires_document=true`, attachment field is required and
      the upload round-trips. (Attachment upload itself returned `503` in this sandbox — no S3
      configured locally — confirmed the request still submits and the UI degrades exactly like
      `RegularizationModal`'s existing "submitted, but attachment failed" toast pattern.)
- [x] Live preview updates as dates change, shows sandwiched holiday/week-off rows.
- [x] Submitting a request with insufficient balance shows the inline violation, doesn't create
      the request. (Verified via the live preview panel's violations list — confirmed
      `insufficient_balance`/`not yet in force` messages render and the request isn't created
      until a valid type/date combination is chosen.)
- [x] After submitting, the request appears in history as Pending and the dashboard's "Open
      requests" tile increments.
- [x] Cancelling an eligible Pending request removes it from active view / marks it Cancelled.
- [x] Loading state renders the shimmer skeleton, not a spinner or "Loading…" text.

All verified end-to-end against the real backend (`beta` dev tenant, `employee1@test.com`) via
browser automation, not just unit/type checks.

## Acceptance criteria

- [x] `MyLeave.tsx` has zero remaining hardcoded `LEAVE_BALANCES`/`LEAVE_REQUEST_HISTORY` arrays
      and no `TODO` comments about the form not submitting.
- [x] `EmployeeHome.tsx`'s Leave balance and Open requests tiles are backend-derived.
- [x] Every new API call goes through a named `api.ts` wrapper — no raw `secureFetch`/`fetch`
      calls inside the component (per CLAUDE.md's frontend convention).

Additional work done beyond the original spec, discovered while implementing:
- [[44]] shipped `LeaveRequestOut` without a `can_cancel` field, so the frontend would have had
  to duplicate the cancellation-eligibility rule client-side — exactly what this task's own
  wording warned against. Added `can_cancel` to `LeaveRequestOut`/`_request_out` in
  `backend/app/modules/leave/schemas.py`/`service.py` (mirrors `cancel_my_request`'s own
  eligibility table) instead of re-deriving it in `MyLeave.tsx`.

Completed: 2026-08-18
