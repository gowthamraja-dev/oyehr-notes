---
task: 25
title: Frontend API client wrappers for leave types & policies
status: done
depends_on: [22, 23]
---

## As-built deviations from the spec below

- **Decimal fields are `string` on the wire, not `number`.** `accrual_quantity`, `max_balance`,
  `max_carry_forward`, `max_encashment` are `Numeric`/`Decimal` columns; FastAPI/Pydantic
  serialize `Decimal` to a JSON **string** (confirmed: `LeavePolicyOut(...).model_dump_json()`
  emits `"accrual_quantity":"1.75"`, not `1.75`). Retyping these as `number` would silently lie
  about the wire shape. Matches the existing `OrgAddress.lttd`/`lgtd` precedent in this same
  file, which types its `Numeric` lat/long columns as `string | null` for the same reason.
  [[26-leave-policy-frontend]] must `Number(...)` these at render/compute time, never assume
  they arrive numeric.
- **`LeaveTypeWithPolicy` uses snake_case `{ leave_type, policy }`, not camelCase
  `{ leaveType, policy }`.** This file's own established convention (`ShiftRoster.meta`'s
  `from_date`/`to_date`/`total_employees`, `OrgAddress`'s fields, etc.) mirrors backend field
  names verbatim in wire-shaped types; camelCase is reserved for local function
  parameters/variables, not JSON-shaped type fields. The as-built type also matches the actual
  `LeaveTypeWithPolicyOut` response body (`{"leave_type": {...}, "policy": {...}}`).
- **`LeavePolicyInput` also omits `leave_type_master_id`**, not just `id`/`is_active` — that
  field is a URL path parameter (`POST /leave/types/{leave_type_id}/policies`), never part of
  the request body, so including it in the input type would be actively wrong, not just extra.
- **`getLeaveTypePolicy`'s `NO_POLICY` detection reads `data.detail.code`/`data.detail.leave_type`
  instead of top-level `data.detail`/`data.leave_type`.** Per [[23-leave-policy-api]]'s own
  as-built deviation note: FastAPI's `HTTPException` handler always wraps `detail` under a single
  `"detail"` key, so the actual body is `{"detail": {"code": "NO_POLICY", "leave_type": {...}}}`,
  not the flat two-key shape this file originally sketched.
- Reused the file's existing `_detailMessage(data, fallback)` helper for every mutation's error
  message (already handles "surface the backend's clean detail string, fall back to a generic
  message otherwise") instead of writing a second implementation of the same thing.

# 25 — Frontend API client wrappers for leave types & policies

## Scope

Typed wrapper functions in `frontend/src/lib/api.ts` for every endpoint from
[[22-leave-type-api]] and [[23-leave-policy-api]]. Per CLAUDE.md: components never call
`secureFetch` directly, and this is an encrypted router so plain `fetch` is never used either.
Follow the exact shape already used for shifts (`frontend/src/lib/api.ts:428-536` —
`Shift`/`ShiftInput`/`ShiftPatchInput` types, `listShifts`/`createShift`/`updateShift`/
`archiveShift` functions) — same file, same section style, add a new `// ---- Leave ----`
block rather than a new file.

## Files

- `frontend/src/lib/api.ts` — add types and functions below

## Types

```ts
export type LeaveType = {
  id: number;
  name: string;
  code: string;
  is_paid: boolean;
  unit: "Day";
  allow_half_day: boolean;
  requires_approval: boolean;
  requires_document: boolean;
  doc_required_after_days: number | null;
  max_consecutive_days: number | null;
  min_notice_days: number;
  allow_negative_balance: boolean;
  gender_applicable: "Male" | "Female" | "Other" | null;
  applicable_after_days: number;
  exclude_week_offs: boolean;
  exclude_holidays: boolean;
  display_order: number;
  color_code: string | null;
  is_active: boolean;
  effctv_dt: string;
  trmntn_dt: string | null;
  policy_summary: string | null;
};

export type LeaveTypeInput = Omit<LeaveType, "id" | "is_active" | "policy_summary">;
export type LeaveTypePatchInput = Partial<LeaveTypeInput>;

export type LeavePolicy = {
  id: number;
  leave_type_master_id: number;
  corp_master_id: number | null;
  employee_type_master_id: number | null;
  accrual_frequency: "Monthly" | "Quarterly" | "Yearly" | "OnJoining";
  accrual_quantity: number;
  max_balance: number | null;
  carry_forward: boolean;
  max_carry_forward: number | null;
  encashable: boolean;
  max_encashment: number | null;
  prorate_on_joining: boolean;
  reset_month: number | null;
  is_active: boolean;
  effctv_dt: string;
  trmntn_dt: string | null;
};

export type LeavePolicyInput = Omit<LeavePolicy, "id" | "is_active">;
export type LeavePolicyPatchInput = Partial<LeavePolicyInput>;

export type LeaveTypeWithPolicy = { leaveType: LeaveType; policy: LeavePolicy | null };
```

## Functions

```ts
export async function listLeaveTypes(activeOnly = false): Promise<LeaveType[]>
// GET /api/v1/leave/types?active_only=

export async function createLeaveType(input: LeaveTypeInput): Promise<LeaveType>
// POST /api/v1/leave/types

export async function updateLeaveType(id: number, patch: LeaveTypePatchInput): Promise<LeaveType>
// PATCH /api/v1/leave/types/{id}

export async function archiveLeaveType(id: number): Promise<void>
// DELETE /api/v1/leave/types/{id} — throw a catchable error (don't swallow) on 409 so the
// caller can show "This leave type has an active policy — deactivate it first"

export async function getLeaveTypePolicy(
  leaveTypeId: number, corpMasterId?: number,
): Promise<LeaveTypeWithPolicy>
// GET /api/v1/leave/types/{id}/policy?corp_master_id=
// On 404 with body {detail: "NO_POLICY", leave_type: {...}}: do NOT throw — return
// { leaveType: body.leave_type, policy: null } so callers render the empty state (prompt §30)
// without a try/catch. Any other non-ok status still throws.

export async function listLeaveTypePolicies(leaveTypeId: number): Promise<LeavePolicy[]>
// GET /api/v1/leave/types/{id}/policies

export async function createLeavePolicy(
  leaveTypeId: number, input: LeavePolicyInput,
): Promise<LeavePolicy>
// POST /api/v1/leave/types/{id}/policies

export async function updateLeavePolicy(
  id: number, patch: LeavePolicyPatchInput,
): Promise<LeavePolicy>
// PATCH /api/v1/leave/policies/{id}

export async function setLeavePolicyStatus(id: number, isActive: boolean): Promise<LeavePolicy>
// PATCH /api/v1/leave/policies/{id}/status
```

All follow the `secureFetch<T>(path, { token, method, jsonBody })` + `if (!ok) throw new
Error(...)` shape at `frontend/src/lib/api.ts:502-539`, token read via
`sessionStorage.getItem("token")` — except `getLeaveTypePolicy`'s special-cased `404` handling
above, which is the one deliberate deviation from "throw on !ok" and must be commented as such
inline so it doesn't look like an oversight later.

## Acceptance criteria

- [x] All types and functions above exist in `frontend/src/lib/api.ts`, exported
- [x] `getLeaveTypePolicy` returns `{ policy: null }` on `NO_POLICY` without throwing, and still
      throws on genuine errors (`401`/`403`/`500`)
- [x] `npx tsc --noEmit` (or the project's existing typecheck script) passes with no new errors
- [x] No component in the repo calls `fetch`/`secureFetch` directly for these endpoints —
      grep confirms only `api.ts` references `/api/v1/leave`

Verified: `npx tsc --noEmit` clean, `npx eslint src/lib/api.ts` clean, `grep -rl "/api/v1/leave" frontend/src` shows only api.ts.

Completed: 2026-08-17
