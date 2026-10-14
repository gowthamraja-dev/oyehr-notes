---
task: 64
title: Frontend API client — leave ledger + assignment wrappers
status: done
depends_on: [62]
---

# 64 — Frontend API client — leave ledger + assignment wrappers

## Discussion

`gaps.md` #9 names this exact gap: *"no `getEmployeeLedger`/`adjustLedger` wrapper exists in
`src/lib/api.ts`... an admin today would need a raw API client, not a screen."* This task adds
the wrappers [[65]] and [[66]] both need, following the exact `secureFetch` + `_detailMessage`
pattern every existing leave wrapper in `frontend/src/lib/api.ts` already uses (e.g.
`createLeaveType`, `listLeaveTypes` around lines 1590-1615) — read those before writing these,
don't invent a new call shape.

## Files

`frontend/src/lib/api.ts` — add:

```ts
export type LeaveAssignment = {
  id: number;
  employee_master_id: number;
  leave_type_master_id: number;
  leave_year: number;
  source_type: "Policy" | "Manual" | "OpeningBalance" | "CarryForward";
  assigned_units: string;       // Decimal serializes as string, matching LeaveBalance's fields
  effective_from: string;
  effective_to: string | null;
  reason: string | null;
  reference: string | null;
  status: "Active" | "Cancelled";
  employee_leave_balance_ledger_id: number;
  created_by_id: number;
  created_at: string;
  cancelled_at: string | null;
  cancellation_reason: string | null;
};

export type LeaveLedgerRow = {
  id: number;
  leave_type_master_id: number;
  leave_year: number;
  txn_type: string;
  quantity: string;
  balance_after: string;
  effective_date: string;
  remarks: string | null;
  created_at: string;
  assignment_id: number | null;
};

export type LeaveAssignmentInput = {
  leave_type_master_id: number;
  source_type: LeaveAssignment["source_type"];
  assigned_units: number;
  effective_from: string;
  effective_to?: string | null;
  reason?: string | null;
  reference?: string | null;
};
```

Functions (mirror `createLeaveType`/`listLeaveTypes`'s exact shape — token from
`sessionStorage`, `secureFetch`, throw `_detailMessage(data, "...")` on `!ok`):

- `getEmployeeLedger(employeeId: number, filters?: { leave_type_master_id?: number; from?: string; to?: string; txn_type?: string }): Promise<LeaveLedgerRow[]>`
  → `GET /api/v1/leave/employees/{employeeId}/ledger` with the filters as query params (only
  append params that are actually set, same pattern `listLeaveTypes`'s `active_only` query uses).
- `listLeaveAssignments(employeeId: number, filters?: { leave_type_master_id?: number; source_type?: string; status?: string }): Promise<LeaveAssignment[]>`
  → `GET /api/v1/leave/employees/{employeeId}/leave-assignments`.
- `createLeaveAssignment(employeeId: number, input: LeaveAssignmentInput): Promise<LeaveAssignment>`
  → `POST /api/v1/leave/employees/{employeeId}/leave-assignments`.
- `cancelLeaveAssignment(employeeId: number, assignmentId: number, cancellationReason: string): Promise<LeaveAssignment>`
  → `POST /api/v1/leave/employees/{employeeId}/leave-assignments/{assignmentId}/cancel`,
  `jsonBody: { cancellation_reason: cancellationReason }`.

## Acceptance criteria

- [x] All four functions exist, typed, following the existing `secureFetch`/`_detailMessage`
      convention — no raw `fetch` calls.
- [x] `LeaveAssignment`/`LeaveLedgerRow` field names match [[62]]'s `LeaveAssignmentOut`/
      extended `LeaveLedgerRowOut` exactly (snake_case, same as every other leave API type in
      this file).
- [ ] A manual smoke check (browser devtools network tab, or a quick script) confirms each
      wrapper hits the right path/method against the running dev API.

Completed: 2026-08-19

Note: `npx tsc --noEmit` passes clean with these additions. The third acceptance item (live
browser smoke check) is deferred to [[65]]/[[66]] — those tasks build the actual UI that calls
these wrappers, which is the real, meaningful exercise of them; the backend endpoints themselves
already have full pytest coverage from [[62]]/[[63]] (161 passed).

