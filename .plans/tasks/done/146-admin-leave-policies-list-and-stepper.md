---
task: 146
title: HR Admin Leave Policies — list + create/edit stepper
status: done
depends_on: [145]
---

# 146 — HR Admin Leave Policies list + stepper

## Scope
Role: **HR Admin**, "Leave Policies" tab of 145.

List: Policy Name · Code · Leave Types (chips) · Scope · Status · Effective From · Effective To ·
Updated · Actions (View, Edit, New version, Archive, Activate/Deactivate). "Show archived" toggle
(reveals archived + `LEGACY_V<n>` policies, read-only). Primary CTA **Create Leave Policy**.

Stepper (create + edit):
1. **Basic info** — name* (≤150), code* (≤50), description, status, effective from, termination
   date (both optional).
2. **Leave rules** — add leave types; **one rule per leave type** (a type already in the policy
   isn't offered again). Each rule collapses to a one-line summary ("Casual Leave · 12 days ·
   Yearly · Max 12 · No carry forward") and expands to: accrual frequency (default Yearly),
   quantity, max balance, carry forward (+ max), encashable (+ max), prorate on joining, reset
   month, status, dates. Reuse `leaveEntitlement.ts` (annualTotal / quantityHint / projectionText).
3. **Scope** — per rule: All corps / Specific corp. Only one scope per rule (DB key). Show a hint:
   "A specific-corp rule covers only that corp's employees. For different rules per corp, create a
   separate policy and assign it to that corp at a higher priority" (link to 147).
4. **Review & save** — client-side validation mirroring 139's rules, then one create call (edit:
   header PATCH + per-detail calls); server 409/422 shown inline on the right step.

Edit changes rules in place — the confirm step says so ("applies to future accruals and requests;
past ledger entries keep their values"). **New version** action opens a small modal (new name,
code, effective date, "move assignments" checkbox) → `createLeavePolicyVersion`.

View = read-only render of the same steps + the policy's assignments count (link to 147).

## Acceptance criteria
- [ ] Create "Standard Employee Leave Policy" with CL/SL/EL end to end in the browser.
- [ ] Adding the same leave type twice is impossible in the UI and 409 from the API is surfaced.
- [ ] New version with moved assignments works; archive / activate / deactivate with confirm dialog.
- [ ] Skeletons, spacing, dates per conventions; `tsc`/lint clean.

## Progress (2026-09-29) — code complete, browser check pending
- New `hrAdmin/Leave_components/LeavePolicies.tsx`: list (Policy name + assignment count ·
  Code · Leave types chips · Scope · Status · Effective from/to · Updated · Actions: Edit, New
  version, Activate/Deactivate, Archive — each confirm-guarded where destructive, gated with
  `usePermission`), "Show archived" toggle (reveals archived + LEGACY policies, read-only),
  "Create Leave Policy" in the breadcrumb controls, skeleton with the same grid.
- Editor modal with the 4 steps (Basic information · Leave rules · Scope · Review & save) used for
  create, edit and view (policy name → view; view has "Edit policy"). Leave rules: one per leave
  type (only unused types are offered), collapsed one-line summary, expand for frequency /
  quantity / max balance / leave-year start / prorate / active / carry forward (+max) /
  encashable (+max per leave year). Scope step: per rule All corps / Only <corp>, with the
  "separate policy + higher priority" hint. Edit saves = header PATCH + status + per-rule
  add / in-place update / archive (removed rows); the review step says edits apply to future
  accruals only. New-version modal (name, code, effective date, move assignments).
- `hrAdmin/Leave.tsx` is now only the area shell; the old per-leave-type screen and
  `LeaveTypeWizard.tsx` are deleted (no other importers). Frontend no longer calls the per-type
  bridge endpoints (`/leave/types/{id}/policy[ies]`) — nor does the mobile app.
- `tsc --noEmit` + `eslint` clean.

## Follow-ups
- Retire the backend bridge routes + their `lib/api.ts` clients (`createLeavePolicy`,
  `listLeaveTypePolicies`, `getLeaveTypePolicy`); ~30 `test_leave.py` tests use the bridge create
  as a fixture and need moving to `POST /leave/policies` first.

## Remaining before moving to done
- [ ] Browser check as HR Admin: create "Standard Employee Leave Policy" with CL/SL/EL; edit a rule;
      new version with moved assignments; archive / activate / deactivate.

Completed: 2026-09-29 — browser/manual checks verified by the user.
