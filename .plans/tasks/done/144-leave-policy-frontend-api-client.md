---
task: 144
title: Frontend API client for leave policies, assignments, resolution, encashment
status: done
depends_on: [139, 140]
---

# 144 — Frontend API client

## Scope
Types + functions in `hrms/frontend/src/lib/api.ts`, all via `secureFetch` (encrypted router):
- Policies: `listLeavePolicies`, `getLeavePolicy`, `createLeavePolicy` (master + details),
  `updateLeavePolicy`, `setLeavePolicyStatus`, `archiveLeavePolicy`, `createLeavePolicyVersion`.
- Details: `addLeavePolicyDetail`, `updateLeavePolicyDetail`, `setLeavePolicyDetailStatus`,
  `archiveLeavePolicyDetail`.
- Assignments: `listPolicyAssignments`, `createPolicyAssignment`, `updatePolicyAssignment`,
  `setPolicyAssignmentStatus`, `archivePolicyAssignment`, `listAssignmentProviders`,
  `getEmployeePolicyResolution`.
- Self-service / other: `getMyLeaveLedger`, `getMyLeavePolicy` (148), encashment get/post (142).
- Types mirror the DBML: nullable `effctv_dt`/`trmntn_dt`; `LeaveType.applicable_after_days:
  number | null`; no `employee_type_master_id` anywhere.
- Remove clients for the per-type bridge endpoints once 145/146 stop using them.

## Acceptance criteria
- [x] `tsc --noEmit` and `npm run build` clean.

## What was built (`hrms/frontend/src/lib/api.ts`)
- Policies: `listLeavePolicyMasters(includeArchived)`, `getLeavePolicyMaster`,
  `createLeavePolicyMaster` (master + rules), `updateLeavePolicyMaster`,
  `setLeavePolicyMasterStatus`, `archiveLeavePolicyMaster`, `createLeavePolicyVersion`,
  `addLeavePolicyRule`. Rule edit/status/archive stay `updateLeavePolicy` /
  `setLeavePolicyStatus` / `archiveLeavePolicy` (already on `/leave/policy-details/{id}`).
- Assignments: `listPolicyAssignments({providerType, policyId, includeArchived})`,
  `createPolicyAssignment`, `updatePolicyAssignment`, `setPolicyAssignmentStatus`,
  `archivePolicyAssignment`, `listAssignmentProviders(type, q)`, `POLICY_PROVIDER_LABELS`.
  A 409 conflict throws `AssignmentConflictError` (extends `ApiError`, carries
  `conflicting: PolicyAssignment`) — same pattern as `UnpayableEmployeesError`.
- `getEmployeePolicyResolution(employeeId, asOf?)`, `getLeaveEncashmentEligibility`,
  `recordLeaveEncashment`.
- Every new call throws `ApiError` (HTTP status kept) via a shared `_leaveCall` helper.
- Types follow the DBML: `LeaveType.applicable_after_days` / `effctv_dt` and
  `LeavePolicy.effctv_dt` are nullable; no `employee_type_master_id` anywhere.

## Decisions / deviations from the scope above
- **Names:** the task listed `listLeavePolicies` / `createLeavePolicy` etc., but those names already
  belong to the *rule* (leave_policy_details) functions the current Leave screen uses. Master-level
  functions are named `…LeavePolicyMaster…` to avoid breaking that screen; 145/146 can rename once
  the old screen is gone.
- `getMyLeaveLedger` / `getMyLeavePolicy` are **not** here — their endpoints don't exist yet; task
  148 adds both endpoints and their clients together.
- The per-type bridge clients (`createLeavePolicy`, `listLeaveTypePolicies`, `getLeaveTypePolicy`)
  are kept until 145/146 stop calling them.
- Old admin screen (`hrAdmin/Leave.tsx`) made null-safe for the nullable dates (empty date field ↔
  `null`, "no probation gate" shows as 0 as before).

## Verification
- `tsc --noEmit` clean, `eslint` clean on the touched files, `npm run build` succeeds (Next 16
  isolates dev output in `.next/dev`, so the running dev servers were unaffected — checked 200).

Completed: 2026-09-29
