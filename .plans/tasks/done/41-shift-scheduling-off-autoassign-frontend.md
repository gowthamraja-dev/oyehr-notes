---
task: 41
title: Roster grid — Mark Off action and Auto-assign button
status: ongoing
depends_on: [40]
---

# 41 — Roster grid: Mark Off action and Auto-assign button

## Discussion

Surfaces tasks 39-40 in the Manager Portal's Shift Scheduling roster
(`frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, backed today by
`listShiftAssignments`/`createShiftAssignment`/`updateShiftAssignment` from
`frontend/src/lib/api.ts`). Two additions, no new screen: a per-cell "Mark Off" action, and a
header-level "Auto-assign" action that generates the visible range in one call.

The cell-click handler already branches on whether the cell has an existing assignment
(`cell.assignment ? updateShiftAssignment(...) : createShiftAssignment(...)`, around line 143) —
follow that same existing/not-existing branch for "Mark Off", just sending `status: "OFF"` instead
of a `shift_master_id`.

## Files

### Edited

- `frontend/src/lib/api.ts`
  ```ts
  export type ShiftAssignment = {
    id: number;
    employee_master_id: number;
    assignment_date: string;
    shift_master_id: number | null;   // was: number
    status: string;                   // "ASSIGNED" | "OFF" | "CANCELLED"
    is_auto_assigned: boolean;
    note: string | null;
  };

  export type ShiftAssignmentInput = {
    employee_master_id: number;
    assignment_date: string;
    status?: "ASSIGNED" | "OFF";      // default "ASSIGNED" server-side
    shift_master_id?: number | null;  // required iff status is ASSIGNED/omitted
    note?: string | null;
  };

  export type ShiftAssignmentPatchInput = {
    status?: "ASSIGNED" | "OFF";
    shift_master_id?: number;
    note?: string | null;
  };

  export type AutoAssignShiftsInput = { from: string; to: string; employee_master_id?: number };
  export type AutoAssignShiftsResult = {
    assignments: ShiftAssignment[];
    assigned_count: number;
    off_count: number;
    unchanged_count: number;
    manual_skipped_count: number;
    no_standing_shift_count: number;
  };

  export async function autoAssignShifts(input: AutoAssignShiftsInput): Promise<AutoAssignShiftsResult> {
    const token = /* existing token lookup pattern used by createShiftAssignment above */;
    const { ok, data } = await secureFetch<AutoAssignShiftsResult>("/api/v1/shifts/assignments/auto-assign", {
      method: "POST", token,
      jsonBody: { from_date: input.from, to_date: input.to, employee_master_id: input.employee_master_id },
    });
    if (!ok) throw new Error(_detailMessage(data, "Failed to auto-assign shifts"));
    return data;
  }
  ```

- `frontend/src/dashboards/hrManager/ShiftScheduling.tsx`
  - Cell interaction: add a "Mark Off" choice to whatever picker currently lists shifts for a cell
    (read the component's existing cell-click/picker code around line 143 to match its actual
    structure before adding this — the task file's job is to name the behavior, not guess the
    exact JSX). On selecting it:
    ```ts
    if (cell.assignment) {
      await updateShiftAssignment(cell.assignment.id, { status: "OFF" });
    } else {
      await createShiftAssignment({ employee_master_id, assignment_date, status: "OFF" });
    }
    ```
  - Cell rendering: an `OFF` cell renders the same way the existing `is_day_off` shift rendering
    does today (`"Rest day"` label, lines ~266/430) — reuse that visual treatment, but drive it
    from `assignment.status === "OFF"` rather than requiring the assigned shift to itself be
    flagged `is_day_off`. A cell whose `is_auto_assigned` is `true` gets a subtle visual marker
    (e.g. a small dot or lighter tone) distinguishing "the system filled this in" from "a manager
    picked this" — check `hrms-spacing` conventions for how existing status pills are styled
    before inventing a new visual language.
  - Header/toolbar: add an "Auto-assign" button next to the existing date-range controls. On
    click, calls `autoAssignShifts({ from: <visible range start>, to: <visible range end> })`
    (optionally scoped to a single selected employee if the grid supports selecting one), then
    re-fetches `listShiftAssignments` for the same range to refresh the grid — do not try to
    patch the grid's local state from the returned `assignments` list piecemeal; a full refetch
    is simpler and this isn't a hot path.
  - Show the result summary (`assigned_count`, `off_count`, `unchanged_count`,
    `manual_skipped_count`, `no_standing_shift_count`) in whatever toast/banner mechanism this
    dashboard already uses elsewhere — do not introduce a new notification component for this
    alone.
  - Shimmer/loading state for the auto-assign action follows this repo's loading-state convention
    (CLAUDE.md "Loading states" section) — disable the button and show an inline spinner/label
    change, not a full-page skeleton (this is a button action, not a page load).

### Manual verification (required — this is a UI change)

Per CLAUDE.md's UI-change rule: start the dev server and exercise both flows in a real browser
before calling this done — mark a cell off, confirm it renders and survives a page refresh
(proves the task-39 visibility fix actually round-trips through this UI); run auto-assign over a
date range for an employee with a Sat/Sun-off shift and confirm the grid fills in correctly; re-run
auto-assign over the same range and confirm nothing visibly changes; manually override one day,
then re-run auto-assign over a range including it, and confirm that day is untouched.

## Acceptance criteria

- [ ] A manager can mark any roster cell `OFF` without needing a special `is_day_off`-flagged
      shift to exist.
- [ ] `OFF` cells are visually distinct from assigned-shift cells and from empty cells.
- [ ] "Auto-assign" fills the visible range from each employee's standing shift + week-off rules
      in one action, with a visible summary of what happened.
- [ ] Re-running auto-assign after a manual edit leaves the manual edit untouched — confirmed
      manually in the browser, not just by the backend tests from task 40.
- [ ] No regression in existing shift-swap/reassign cell behavior (manually smoke-tested).
