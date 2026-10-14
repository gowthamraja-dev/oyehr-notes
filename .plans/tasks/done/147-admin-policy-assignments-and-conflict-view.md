---
task: 147
title: HR Admin Policy Assignments + employee resolution (conflict) view
status: done
depends_on: [145]
---

# 147 — HR Admin Policy Assignments + conflict view

## Scope
Role: **HR Admin**, "Policy Assignments" tab of 145.

Assignments table: Leave Policy · Provider ("Employee Type → Doctor", "All employees") · Priority
· Effective From · Termination · Status · Actions (Edit, Activate/Deactivate, Archive); filters by
provider type and policy. The backfilled "Default Leave Policy → All employees, priority 0" row
appears here like any other.

Create/edit modal: Provider Type (Employee / Department / Employee Type / Corp / All employees),
Provider (searchable picker from `listAssignmentProviders`; hidden for All employees), Leave Policy
(active, non-archived, non-LEGACY only), Priority (≥ 0, with helper "higher wins"), effective /
termination dates (optional), status. A 409 conflict shows the conflicting assignment inline.

"Check an employee" panel: employee search → `getEmployeePolicyResolution` → ranked candidates
(policy, provider, priority, dates, ✓ Selected) and the winning policy's rule per leave type,
with "not covered by the selected policy" shown for types the winner lacks (winner takes all).
Reused from the employee profile Leave tab (148).

Shimmer skeletons, 10px spacing, dd-MMM-yy dates, `useConfirm` for archive, Tailwind only.

## Acceptance criteria
- [ ] Create / edit / archive assignments in the browser; 409 conflict displayed.
- [ ] Resolution panel renders the Doctor / Clinical / Standard example correctly, incl. a
      "not covered" type.

## Progress (2026-09-29) — code complete, browser check pending
Built in the top-level `hrms/` clone (branch `feature/gowtham_LeaveMasters`, uncommitted, next to
140–146) — by decision, since workspace-2 has none of the leave-policy work.
- New `hrAdmin/Leave_components/PolicyAssignments.tsx`, wired into the Leave shell's
  "Policy Assignments" tab (replaces the `Placeholder`). Table: Leave policy (+code) · Provider
  ("Employee Type → Doctor" / "All employees") · Priority · Effective from · Termination · Status ·
  Actions (Edit, Activate/Deactivate with confirm, Archive via `useConfirm`), gated with
  `usePermission(CREATE|UPDATE|DELETE, "LEAVE")`. Filters: provider type, policy, "Show archived".
  "Create Assignment" in the breadcrumb controls. `PolicyAssignmentsTableSkeleton` = same grid.
- Create/edit modal: provider type → provider picker (`Combobox`, employees searched server-side,
  debounced; hidden for All employees, whose single provider is auto-picked), leave policy (active,
  non-archived, non-`LEGACY_V`; an edited row keeps showing its current policy), priority ≥ 0 with
  the "higher wins / tie → more specific" helper, optional dates, status. Edit sends only changed
  fields (the server re-validates policy/provider only when patched); a status change is ordered
  deactivate-before / activate-after the patch. A 409 shows the conflicting assignment inline;
  a 409 on row re-activation shows it in the page error.
- New shared `dashboards/shared/PolicyResolutionPanel.tsx` (+ `PolicyResolutionPanelSkeleton`,
  `providerText`) — for 148's "Why this policy?" too. Summary (winner / "No leave policy applies",
  as-of, notes), ranked candidates with ✓ Selected / Outranked, and per leave type the winner's
  rule or "Not covered by the selected policy — not available". "Check an employee" section on the
  assignments tab hosts it with an employee search + optional as-of date.
- `shared/Combobox.tsx`: optional `onInputChange` prop (server-side search; disables client filter).
  Existing callers unchanged.
- `tsc --noEmit` + `eslint` clean.

## Remaining before moving to done
- [ ] Browser check as HR Admin (the API uses the shared remote hrms_dev DB, so this wasn't run
      automatically): create / edit / archive an assignment; force a 409 (same provider + priority,
      overlapping dates) and see it inline; set up Doctor (Employee Type) / Clinical (Department) /
      Standard (All employees) assignments and check a doctor in "Check an employee" — Doctor policy
      selected, the others outranked, a type Doctor's policy lacks shown as not covered.

Completed: 2026-09-29 — browser/manual checks verified by the user.
