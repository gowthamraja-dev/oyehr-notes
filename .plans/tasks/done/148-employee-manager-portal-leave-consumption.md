---
task: 148
title: Employee & Manager portals consume resolved policy, rules and ledger
status: done
depends_on: [144]
---

# 148 — Employee & Manager portal consumption

## Scope
Read-only — no policy configuration in these portals; no logic duplicated from the backend.
- **Backend** (self-service, ungated — the caller's own record): `GET /leave/me/ledger` (own
  ledger rows: Accrual, CarryForward, LapseExpiry, Encashment, Availed, Reversal, Adjustment) and
  `GET /leave/me/policy` (resolved policy name + per-type rules: paid, unit, half day, notice, max
  consecutive, document rule, accrual frequency/quantity, max balance, carry forward, leave-year
  start). Tests incl. cross-tenant and "no policy" (empty rules, not an error).
- **Employee portal** (`employee_portal`, `dashboards/Employee/MyLeave.tsx`, nav "My Leave"): add
  a "Leave rules" card (policy name + per-type rules) and "Leave history" (ledger rows with typed
  labels) beside the existing balances + requests. The apply form shows rule hints (half day
  allowed, notice, document threshold) from `/me/policy`; types not covered by the policy aren't
  offered.
- **Manager portal** (`hr_manager`): shared `EmployeeLeaveTab` (employee profile) shows the
  applied policy name + a "Why this policy?" link opening 147's resolution panel (read-only)
  above balances. Approval detail (`RequestDetailModal`) shows the requester's balance for that
  type — check what it already shows before adding. Leave calendar: reuse the existing team-leave
  view if there is one; if not, record a follow-up task instead of building it here.

## Acceptance criteria
- [ ] Employee sees rules + history; manager sees the applied policy on a report's profile.
- [ ] Manager portal exposes no policy write actions (RBAC: manager default grid has no
      CREATE/DELETE on LEAVE config screens).

## Progress (2026-09-29) — code complete, browser check pending
Built in the top-level `hrms/` clone (branch `feature/gowtham_LeaveMasters`, uncommitted, with 140–147).
- **Backend** (self-service, ungated): `GET /leave/me/policy` (`assignment_service.get_my_policy`,
  via `resolution.explain` — winner takes all; per live leave type the type's own rules + the
  winner's accrual rule, `covered=false` when the winner has none; types restricted to another
  gender are omitted; no policy = 200 with nulls) and `GET /leave/me/ledger`
  (`service.get_my_ledger`). Both find the caller's employee row **in the token's tenant**
  (`service._require_self_employee_in_tenant`, 403 if none). Ledger rows (self + the existing
  admin/manager ledger) now carry `leave_type_code` / `leave_type_name` (additive).
  New schemas `MyLeavePolicyOut` / `MyLeaveRuleOut`. Tests: `test_leave_my_policy.py` (9 —
  Doctor/Clinical/Standard winner-takes-all incl. "not covered", no policy, no employee record,
  401, cross-tenant for both routes, ledger labels incl. archived type, encrypted round-trip);
  all 318 leave tests pass.
- **Employee portal** (`Employee/MyLeave.tsx`): "Leave rules" card (policy name pill; per covered
  type: accrual/cap/carry-forward/leave-year text + apply hints; "Not covered by your policy: …")
  and "Leave history" card (ledger newest first, typed labels, +/− days, balance, dd-MMM-yy) as a
  second row under balances + apply/requests; skeleton extended to match. `ApplyLeaveForm` takes
  an optional `policy`: only covered types are offered, the selected type's hints show under the
  picker (half day, notice, document threshold, max consecutive, no approval). The page waits for
  the policy (it gates the form); a failed policy load degrades to the old unfiltered form. The
  ledger loads independently.
- **Manager portal**: shared `EmployeeLeaveTab` shows the applied policy ("Leave policy" strip +
  skeleton) above balances, with "Why this policy?" opening 147's `PolicyResolutionPanel` in a
  read-only modal; hidden if the caller can't see the resolution. Ledger rows use the row's own
  type name. `TXN_TYPE_LABEL` now lives once in `MyLeave.tsx` (exported). `RequestDetailModal`
  already shows the requester's balance for the type (entitled / used / available / after) — no
  change. No team-leave calendar exists → follow-up **157**.
- RBAC: HR Manager default grid is `LEAVE: READ, UPDATE, APPROVE` (no CREATE/DELETE), every
  policy/assignment write also calls `_require_admin`, and no manager/employee dashboard imports
  the leave config screens — no write actions exposed.
- Mobile skill (`.claude/skills/hrms-mobile-api-integration`) lists the two new `/me` endpoints.
- `tsc` clean; eslint clean on `MyLeave.tsx`; `EmployeeLeaveTab.tsx` still has its pre-existing
  `set-state-in-effect` error on the `employeeId` reset effect (present at HEAD too).

## Remaining before moving to done
- [ ] Browser check (the API uses the shared remote hrms_dev DB, so not run automatically):
      employee sees Leave rules + Leave history and the apply form offers only covered types with
      hints; manager opens a report's profile → Leave tab shows the policy and "Why this policy?".

Completed: 2026-09-29 — browser/manual checks verified by the user.
