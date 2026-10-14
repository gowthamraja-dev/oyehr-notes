---
task: 65
title: Manager Portal — employee Leave tab gains Ledger + Assignment History (read side)
status: done
depends_on: [64]
---

# 65 — Manager Portal — employee Leave tab gains Ledger + Assignment History (read side)

## Discussion

Closes `gaps.md` #9's remaining frontend half for the *read* side: *"no screen in any dashboard
renders ledger rows or a balance-history view."* Design doc §14/§24. Extends
`frontend/src/dashboards/shared/EmployeeLeaveTab.tsx` — read it in full first (117 lines today):
it currently renders `BalanceCards` (balances) + a flat "Recent requests" list, explicitly
documented as read-only (line 48's comment: *"No Approve/Reject buttons here"*). This task adds
two more read-only sections below "Recent requests"; it does **not** touch the write/creation
flow ([[66]] owns "Assign Leave").

**Out of scope, explicitly:** `frontend/src/dashboards/shared/EmployeeDetailDrawer.tsx`'s own
`LeaveSummarySection` (a smaller slide-over preview, same balances+requests data, no ledger).
Design doc §14's enhancement targets "Employee Directory → Employee Profile → Leave", i.e. the
full profile page's tab, not the drawer preview — leave the drawer unchanged.

## Files

`frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`:

1. New `isAdmin: boolean` prop on `EmployeeLeaveTab` (threaded from
   `frontend/src/dashboards/shared/EmployeeProfileView.tsx`'s call site, line 164:
   `<EmployeeLeaveTab employeeId={detail.id} isAdmin={me.is_admin} />` — mirrors this same
   file's existing `me.is_admin` gate at line 203 for the Attributes section). Used here to show
   the per-row "Cancel" action only for admins; [[66]] reuses it to gate the "Assign Leave"
   button.

2. **Ledger section** — fed by `getEmployeeLedger(employeeId)` (from [[64]]). Table columns per
   design doc §24: `Date | Leave Type | Description | Credit | Debit | Balance`. Row rendering:
   - `Date` = `effective_date` (reuse this file's existing `formatDateLabel`).
   - `Leave Type` — the ledger row only carries `leave_type_master_id`; resolve the display name
     client-side from the already-loaded `balances` array (`balances.find(b =>
     b.leave_type_master_id === row.leave_type_master_id)?.name`) rather than adding a new join —
     the balances call already runs on this same tab.
   - `Description` = `remarks` (fall back to a human label for `txn_type` — reuse
     `vocabularies.md` §7's display strings: Opening→"Opening balance", Accrual→"Accrued",
     Availed→"Availed", Reversal→"Reversed", CarryForward→"Carried forward",
     Encashment→"Encashed", LapseExpiry→"Lapsed", Adjustment→"Adjustment" — hardcode this small
     lookup in the component, it's a fixed backend vocabulary, not DB-driven data per CLAUDE.md's
     Tailwind-styling section's carve-out (this is a label map, not a styling value, so a plain
     object constant is fine, no `.module.css` involved either way).
   - `Credit`/`Debit` — `quantity > 0` → show `+quantity` under Credit, `—` under Debit; else the
     reverse (reuse this file's existing `fmtDays` helper).
   - `Balance` = `balance_after`.
   - When `row.assignment_id` is set, the row is visually marked (small link icon) and clicking
     it scrolls to/expands the matching row in the Assignment History section below (pure
     client-side anchor — both sections are already loaded in the same tab, no navigation to a
     separate page needed).

3. **Assignment History section** — fed by `listLeaveAssignments(employeeId)` (from [[64]]).
   Each row shows: leave type name (same client-side resolution as above), a human `source_type`
   label (`Policy → "Policy entitlement"`, `Manual → "Manual adjustment"`,
   `OpeningBalance → "Opening balance"`, `CarryForward → "Carry forward"`), `assigned_units`,
   effective period (reuse `formatDateRange`, `effective_to` may be null → show "onwards"),
   a status pill (`Active`/`Cancelled`, reuse this file's existing pill style pattern from
   `REQUEST_STATUS_STYLE`), and — **only when `isAdmin && status === 'Active'`** — a "Cancel"
   action. Clicking Cancel opens a small inline confirm asking for `cancellation_reason` (plain
   text input, required — mirror the minimal-friction pattern this codebase uses for other
   single-field confirms, not a full modal), then calls `cancelLeaveAssignment` and reloads the
   tab's data (`load()`) on success.

4. Both new sections get their own shimmer skeleton (`animate-pulse` on `bg-ink-100` divs sized
   to the real row layout), matching this file's existing `BalancesSkeleton`/`RequestsSkeleton`
   pattern exactly — per CLAUDE.md's "Loading states" convention, no spinner/"Loading…" text.

5. Extend this tab's `load()` to fetch ledger + assignments alongside balances/requests
   (`Promise.all` of four calls instead of two), and its error/retry UI stays the single shared
   block already there.

## Acceptance criteria

- [x] Manager viewing a direct report's profile → Leave tab sees Ledger and Assignment History
      sections populated from real API data (no sample/hardcoded rows).
- [x] Manager (non-admin) sees no Cancel action anywhere in Assignment History.
- [x] Admin sees Cancel on `Active` rows only; cancelling refreshes all four data sources and the
      cancelled row's status updates in place without a full page reload.
- [x] A ledger row with a non-null `assignment_id` visibly links to its assignment row.
- [x] `EmployeeDetailDrawer.tsx`'s `LeaveSummarySection` is unchanged.
- [x] Skeletons shown immediately while the four calls are in flight; no layout shift once data
      arrives.

Completed: 2026-08-19

Note: verified by `npx tsc --noEmit` (clean) and `npx eslint` (no new violations — the one
pre-existing `set-state-in-effect` warning already existed in this file and in
`EmployeeProfileView.tsx` before this change) plus careful manual tracing of the component logic
against [[64]]'s API contract. **A live browser click-through was attempted but not completed**:
the `claude-in-chrome` tool drives the user's actual separate browser, which cannot reach ports
bound only inside this sandboxed dev environment — a temporary backend/frontend stood up here
for testing was unreachable from that browser (every request came back 503 even though the same
endpoints returned 200 via direct `curl` from this sandbox). Standing up a fully separate,
independently-reachable environment was out of scope for this task. This is a tooling/environment
limitation, not a code issue — flagged explicitly per CLAUDE.md's "if you can't test the UI, say
so" guidance rather than claiming a visual check that didn't happen.

