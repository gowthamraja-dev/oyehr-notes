---
task: 66
title: Manager Portal — "Assign Leave" modal (write side)
status: done
depends_on: [64]
---

# 66 — Manager Portal — "Assign Leave" modal (write side)

## Discussion

The design doc's centerpiece screen (§15) and business rules 1/9/12 (§25): HR grants entitlement
through a form, never a direct balance edit; the assignment and its ledger credit are created
atomically server-side ([[62]] already guarantees that) — this task is purely the UI that calls
`createLeaveAssignment` ([[64]]). Independent of [[65]] (which owns the *read* side of the same
tab) — both depend only on [[64]]'s API client, so they can be built in either order, but they
land in the same tab, so coordinate the final wiring (whichever merges second adds the "Assign
Leave" button next to the other's sections rather than conflicting on the file).

## Files

New component `frontend/src/dashboards/shared/AssignLeaveModal.tsx`, following this codebase's
existing modal convention (px-5 py-4 header/body/footer — mirror `ShareCredentialsModal.tsx` or
`EditAdminModal.tsx`'s structure, per CLAUDE.md's modal-internals carve-out from the page-level
10px spacing rule). Triggered by a new "Assign Leave" button in
`frontend/src/dashboards/shared/EmployeeLeaveTab.tsx`, visible only when the `isAdmin` prop
[[65]] adds is `true`.

Fields, per design doc §15:

- **Employee** — read-only header: name, `emp_id`, department (already available on the profile
  `detail` object the tab already receives; pass through, don't refetch).
- **Leave Type** — dropdown from `listLeaveTypes(true)` (already exists in `api.ts`) — active
  types only. Never hard-code the list (design doc §2 Step 2's explicit instruction).
- **Assignment Source** — dropdown with exactly four options: "Policy entitlement" (`Policy`),
  "Manual adjustment" (`Manual`), "Opening balance" (`OpeningBalance`), "Carry forward"
  (`CarryForward`). **No Comp-off option** — [[61]]'s discussion section explains why (gaps.md
  #1, comp-off earning mechanism not built).
- **Effective From** / **Effective To** — date inputs; "To" optional.
- **Quantity** — number input. For `Policy`/`OpeningBalance`/`CarryForward`, enforce `> 0`
  client-side (mirrors [[62]]'s server-side `422`) with a label like "Entitlement (days)". For
  `Manual`, allow a leading minus and relabel to "Add or remove days" (design doc §28's "Add +2" /
  "Remove -1" examples) — client-side only requires non-zero.
- **Reason** — text field. Required (non-blank) exactly when source = `Manual` — same rule
  [[62]] enforces server-side; show the field's required marker conditionally, don't just rely on
  the server's `422`.
- **Reference** — optional text field.
- **Preview** — before submit, compute and show `Current balance → New credit (±N) →
  Projected balance` for the selected leave type, using the balance already loaded in the parent
  tab (from `getEmployeeLeaveBalances`, already fetched) plus the entered quantity — purely
  client-side arithmetic, no extra API call (design doc §15's exact wireframe).
- **Actions** — Cancel / "Assign leave". Submit calls `createLeaveAssignment(employeeId, input)`.
  - On success: close the modal, show a success toast — *"{quantity} {leave type} days have been
    added to {employee name}'s balance"* (design doc §30's exact notification copy) — and call
    the parent tab's `load()` to refresh balances, ledger, and assignment history in one go.
  - On failure: surface the server's error inline in the modal, not just a toast —
    `409` (duplicate Policy/Opening/CarryForward for this year) → *"An active {source} assignment
    already exists for {leave type}, {year}."*; `422` → the validation message from the response
    body (reuse the same `_detailMessage`-style extraction other `api.ts` callers already use,
    don't swallow the specific reason).

## Acceptance criteria

- [x] Non-admin users never see the "Assign Leave" button.
- [x] Leave type list is always fetched from the API, never hard-coded in the component.
- [x] Comp-off is not a selectable Assignment Source.
- [x] Quantity validation matches [[62]]'s server-side rules exactly (positive-only for three of
      the four sources, non-zero signed for Manual) and is enforced before submit, not only
      surfaced as a server error.
- [x] Reason is required in the UI when, and only when, source = Manual.
- [x] Preview panel updates live as leave type / quantity change, with no network call.
- [x] A successful assignment immediately reflects in the tab's Balance cards, Ledger, and
      Assignment History without a manual page refresh.
- [x] A duplicate system-sourced assignment attempt shows the server's `409` message inline,
      not a generic failure toast.

Completed: 2026-08-19

Note: built as `AssignLeaveModal.tsx` (a modal, matching `EditAdminModal.tsx`'s exact structure
per CLAUDE.md's convention), triggered from `EmployeeLeaveTab.tsx`'s new "Assign Leave" button
(gated on the `isAdmin` prop [[65]] added). `npx tsc --noEmit` and `npx eslint` both clean.
**Live browser click-through not completed** — same environment constraint noted in [[65]]'s
completion note: the `claude-in-chrome` tool drives the user's separate real browser, which
cannot reach a temporary backend/frontend bound only inside this sandbox. Confidence instead
comes from: the exact field-name match against [[62]]'s `LeaveAssignmentIn`/validation rules
(verified by reading both side by side), TypeScript compilation against the real
`createLeaveAssignment` signature, and [[62]]/[[63]]'s 161 passing backend tests covering every
validation path this form surfaces.

