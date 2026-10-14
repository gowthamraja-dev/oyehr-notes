---
task: 16
title: "Manager Portal: rework ShiftScheduling.tsx onto the per-date assignment API"
status: done
depends_on: [14]
---

# 16 — Manager Portal: rework `ShiftScheduling.tsx` onto the per-date assignment API

## Scope

Go throuh the - [text](<../../../.design/Manager Portal.dc.html>) to get the exact ui fo the shift assignment screen
Rework the real, already-shipped `frontend/src/dashboards/hrManager/ShiftScheduling.tsx` (not a
mock — see task 11 precedent for `AttendanceShifts.tsx`) to consume task 14's per-date
`/api/v1/shifts/assignments*` endpoints instead of the effective-dated
`/api/v1/shifts/employee-shifts` / `/api/v1/shifts/team/employee-shifts`, and to close the
manager-portal UX gaps from `.design/prompts/hrms_shift_assignment_apis_ui_walkthrough.md` §14
(filters, view toggle, legend, richer modal, states, responsive layout). Does not touch task 15's
bulk endpoint (no bulk UI in this task) or any HR Admin screen.

`ShiftScheduling.tsx` is confirmed (via repo-wide grep) the **only** frontend caller of
`assignEmployeeShift`/`updateEmployeeShift`/`listTeamEmployeeShifts` — safe to remove those
call-sites and their `api.ts` wrappers without breaking anything else. The backend endpoints they
call (`employee_shift_details`-backed) are left running (task 13's Discussion) for any other
consumer.

## Part 1 — extract the shared shift-accent utility

`frontend/src/dashboards/hrAdmin/AttendanceShifts_components/utils/constants.ts` already has a
canonical `accentFor(color, code)` (explicit `shift.color` palette key wins, falls back to a
legacy code-keyed map, then a flat default) plus `Accent`/`ACCENTS`/`FALLBACK_ACCENT`/
`COLOR_PALETTE`. `ShiftScheduling.tsx` instead reinvents a hash-keyed-by-id `PALETTE`/
`accentForShift` that ignores the shift's actual `color` field. Fix by sharing one utility:

- **New** `frontend/src/dashboards/shared/shiftAccent.ts` — move `Accent`, `ACCENTS`,
  `FALLBACK_ACCENT`, `COLOR_PALETTE`, `accentFor` here **verbatim** from
  `hrAdmin/AttendanceShifts_components/utils/constants.ts`.
- **Edit** `hrAdmin/AttendanceShifts_components/utils/constants.ts` — remove those five exports;
  keep `FILTERS`/`NEW_SHIFT_ID`/`GRID` (admin-screen-specific, stay put). Re-export the moved
  symbols from the new shared module (`export * from "../../../shared/shiftAccent"`) so the three
  files below don't need their import paths touched — or update each import path directly,
  whichever is fewer total diff lines; either is fine as long as `ShiftsList.tsx`, `index.tsx`, and
  `ShiftDefaults.tsx` keep working unchanged in behavior.
- No behavior change for the HR Admin screen — this is a pure move.

## Part 2 — `frontend/src/lib/api.ts`

Add a new section `// ── Shifts: per-date assignments (Manager Portal roster) ──`, pattern-matched
on the existing `listShifts`/`createShift` (all via `secureFetch`, `/shifts` is an
`EncryptedRoute`):

```ts
export type ShiftAssignment = {
  id: number;
  employee_master_id: number;
  assignment_date: string; // "YYYY-MM-DD"
  shift_master_id: number;
  status: "ASSIGNED" | "CANCELLED";
  note: string | null;
};

export type ShiftAssignmentInput = {
  employee_master_id: number;
  assignment_date: string;
  shift_master_id: number;
  note?: string | null;
};

export type ShiftAssignmentPatchInput = { shift_master_id?: number; note?: string | null };

export type EmployeeRoster = {
  employee_master_id: number;
  emp_id: string | null;
  name: string;
  department: string | null;
  role: string | null;
  assignments: ShiftAssignment[];
};

export type ShiftRoster = {
  data: EmployeeRoster[];
  meta: { from_date: string; to_date: string; total_employees: number };
};

export async function listShiftAssignments(
  from: string, to: string,
  filters?: { departmentId?: string; role?: string; employeeMasterId?: number },
): Promise<ShiftRoster> {
  const token = sessionStorage.getItem("token");
  const params = new URLSearchParams({ from, to });
  if (filters?.departmentId) params.set("department", filters.departmentId);
  if (filters?.role) params.set("role", filters.role);
  if (filters?.employeeMasterId != null) params.set("employee_master_id", String(filters.employeeMasterId));
  const { ok, data } = await secureFetch<ShiftRoster>(`/api/v1/shifts/assignments?${params.toString()}`, { token });
  if (!ok) throw new Error("Failed to load shift roster");
  return data;
}

export async function createShiftAssignment(input: ShiftAssignmentInput): Promise<ShiftAssignment> {
  const token = sessionStorage.getItem("token");
  const { ok, data } = await secureFetch<ShiftAssignment>("/api/v1/shifts/assignments", {
    method: "POST", token, jsonBody: input,
  });
  if (!ok) throw new Error(_detailMessage(data, "Failed to assign shift"));
  return data;
}

export async function updateShiftAssignment(id: number, patch: ShiftAssignmentPatchInput): Promise<ShiftAssignment> {
  const token = sessionStorage.getItem("token");
  const { ok, data } = await secureFetch<ShiftAssignment>(`/api/v1/shifts/assignments/${id}`, {
    method: "PUT", token, jsonBody: patch,
  });
  if (!ok) throw new Error(_detailMessage(data, "Failed to change shift"));
  return data;
}

export async function cancelShiftAssignment(id: number): Promise<void> {
  const token = sessionStorage.getItem("token");
  const { ok } = await secureFetch<null>(`/api/v1/shifts/assignments/${id}`, { method: "DELETE", token });
  if (!ok) throw new Error("Failed to cancel shift assignment");
}
```

Match the exact `sessionStorage.getItem("token")` + `secureFetch` call shape already used by the
adjacent `listShifts`/`createShift`/`updateShift` functions in this file (~line 499-535) rather
than inventing a new pattern.

**Remove** (dead once Part 3 lands — confirmed sole consumer was `ShiftScheduling.tsx`):
`assignEmployeeShift`, `updateEmployeeShift`, `listTeamEmployeeShifts`, and their types
(`EmployeeShift`, `EmployeeShiftInput`, `EmployeeShiftPatchInput`, `TeamEmployeeShifts`). Leave
`listShifts`/`createShift`/`updateShift`/`archiveShift`/`getShiftWeekOffs`/`replaceShiftWeekOffs`
untouched — still used by `hrAdmin/AttendanceShifts.tsx`.

## Part 3 — `frontend/src/dashboards/hrManager/ShiftScheduling.tsx`

1. **Data loading** — `Promise.all([listShifts(), listShiftAssignments(fromIso, toIso)])` on
   mount and whenever the week changes. Department/role/employee-search filters (below) are
   applied **client-side** over the already-fetched roster, not as query params — the manager's
   dataset (direct reports only) is small, and there is no `department_master`/role-master table
   to filter against server-side anyway (see `CLAUDE.md`'s "master table doesn't exist yet"
   convention — `department`/`designation` on `EmployeeMaster` are plain strings).
2. **Delete** `shiftForDate` and the effective-date resolution comment block — the API now returns
   already-resolved per-date rows (`EmployeeRoster.assignments`, one entry per
   `(date, status="ASSIGNED")` in range); look a cell up with
   `row.assignments.find(a => a.assignment_date === dateIso)` instead.
3. **Filters bar** (new, above the roster table): Department select, Role select, Employee search
   text input, and an "All / By department / By role" view toggle. Populate the department/role
   select options from `Array.from(new Set(rows.map(r => r.department).filter(Boolean)))` (and
   same for `role`) — no new endpoint. "By department"/"By role" groups the employee rows under a
   section header per distinct value (plus an "Unassigned" bucket for `null`); "All" is today's
   flat list. Employee search does a case-insensitive substring match on `name`/`emp_id`.
4. **Shift legend** — new compact row above the table: one chip per fetched shift, using
   `accentFor(s.color, s.code)` from the new shared `shiftAccent.ts` (Part 1) for its swatch, plus
   name and time range — or "Rest day" instead of a time range when `s.is_day_off`.
5. **Cell rendering** — resolve via `row.assignments.find(...)` (step 2); render using
   `accentFor(shiftMaster?.color, shiftMaster?.code)` instead of the old hash-based
   `accentForShift`; "—" for no assignment.
6. **`AssignShiftModal` rework** — highlight the current shift with a checkmark; clicking a shift
   still assigns immediately (see Discussion below for why this stays a one-click flow rather than
   a two-step Save/Change).

## Discussion — reconciling with the real mockup, not just the generic API-walkthrough prompt

Mid-task, `.design/Manager Portal.dc.html` (the actual Shift Scheduling markup + mock data/JS,
lines ~1355-2020 and ~2775-2810) turned out to be the authoritative UI reference — closer to the
house style than `.design/prompts/hrms_shift_assignment_apis_ui_walkthrough.md`'s generic
walkthrough, which was written without seeing this repo's mockups. Reading it changed several
Part 3 decisions below; the parts of the original spec that were **dropped** are recorded here
so a future session doesn't reintroduce them as "missing":

- **The Assign-shift modal has no Save/Cancel/note field/Unassign button in the mockup** — it is a
  plain list of shift options; picking one applies it immediately (`onPick` in the mock's JS
  mutates state and closes the modal in the same call). This exactly matches what was **already
  shipped** before this task (click a shift → immediately calls the assign API → closes). Kept
  that one-click interaction rather than building the walkthrough doc's two-step
  select-then-"Save shift"/"Change shift" flow. Only additions: (a) the currently-assigned shift
  now shows a checkmark (`op.active` in the mock — the old code had no such indicator at all),
  and (b) the click now calls `createShiftAssignment`/`updateShiftAssignment` (task 14's per-date
  API) instead of the old effective-dated `assignEmployeeShift`.
- **No note field, no Unassign/Cancel-assignment action.** Since there's no explicit "clear" flow
  in the mockup, the only way to make a date look unworked is to assign it a tenant-configured
  `is_day_off` shift (task 13) — this reuses the existing pick-list instead of adding a new
  affordance. `cancelShiftAssignment` (task 14) remains available on the backend for a future
  power-user action (e.g. right-click), just not wired to any control in this task.
- **No employee-search text input on this screen.** The `.dc.html` file's only per-employee search
  UI ("Search Employees" filter modal, with Employee ID/Name/Mobile/Gender/etc. tabs) is a
  different, shared component used elsewhere (Employee Directory) — it is not part of the Shift
  Scheduling view. Dropped from this task's filter bar; only the view toggle
  (All/By department/By role) plus one **conditionally shown** select (department select only
  under "By department", role select only under "By role" — matching `shiftShowDept`/
  `shiftShowRole` in the mock, not "always visible" as originally planned) were built.
- **KPI cards** — the mock shows four: "Shifts this week", "Open shifts", "Coverage", "Swap
  requests". `docs/leave-and-attendance/shifts/gaps.md` #2/#3 already document that "Open shifts"
  (no table for an unfilled slot), "Coverage %", and "Swap requests" (no table at all) have **no
  backing data** — showing them would mean fabricating numbers. Kept the two cards that were
  already shipped and real (relabeled "Assigned shifts this week" → "Shifts this week" to match
  the mock's copy); did not add the other three.
- **No "Publish roster" button and no "Swap & login-swap requests" section** — the former has no
  bulk-assignment UI to drive it (task 15 is backend-only, deliberately no frontend consumer yet);
  the latter is gap #2, explicitly deferred (no table, undefined `Recommended` status, two-tier
  approval that contradicts single-step approval elsewhere in this codebase).
- **Responsive** — the mockup itself has no mobile/tablet-specific layout (it's a fixed-width
  desktop prototype, consistent with every other `.dc.html` file in this repo). Given the filter
  bar shrank to just the view-toggle pill group plus one conditional select (not the original
  four-control bar that would have genuinely needed a "collapse into a button" treatment), a plain
  `flex-wrap` on that row is enough to stay usable at narrow widths. Did **not** build a separate
  mobile employee-accordion or a "Filters" popover button — neither exists in the mockup, and
  inventing them isn't needed once the filter bar is this small. The grid's existing
  `overflow-x-auto` horizontal scroll (already shipped) is the only narrow-viewport handling, same
  as before this task.
- **Leave-conflict-specific messaging** — still not built. No leave module exists in this
  codebase (confirmed: no `leave_request`-type model), so the backend cannot produce that signal;
  a `409` (duplicate assignment) shows the same generic `saveError` banner as any other failure.
  Tracked as a known gap in task 17's docs update, not an oversight.

## Acceptance criteria

- [x] `ShiftScheduling.tsx` no longer imports `assignEmployeeShift`/`updateEmployeeShift`/
      `listTeamEmployeeShifts`/`shiftForDate`; it loads and renders the roster from
      `listShiftAssignments`.
- [x] `hrAdmin/AttendanceShifts_components/utils/constants.ts` no longer defines
      `Accent`/`ACCENTS`/`FALLBACK_ACCENT`/`COLOR_PALETTE`/`accentFor` itself (re-exports them from
      the new shared module); both the admin screen and `ShiftScheduling.tsx` render shift
      swatches via `dashboards/shared/shiftAccent.ts`, using the shift's real `color`/`code` (not
      a hash of its id).
- [x] View toggle (All/By department/By role) with the matching conditional select works
      client-side over the manager's direct-report roster, matching the mock's
      `shiftShowDept`/`shiftShowRole` conditional-visibility behavior.
- [x] Shift legend renders every fetched shift, including a "Rest day" label for any `is_day_off`
      shift.
- [x] Clicking a cell opens the modal with the current assignment (if any) shown with a checkmark;
      picking a shift assigns immediately via `createShiftAssignment`/`updateShiftAssignment`
      (POST when the cell had no prior assignment, PUT when it did), closes the modal, and shows a
      success toast.
- [x] A save failure keeps the modal open and shows the backend message inline (`saveError`
      banner) without losing the cell context.
- [x] "No employees found" + "Clear filters" appears when the view/department/role filter narrows
      the team to zero matches; the distinct "No direct reports found for your account" message
      still covers the zero-reports case.
- [x] `is_day_off` is plumbed end-to-end into the frontend `Shift`/`ShiftInput` types (also fixed a
      compile error this surfaced in `hrAdmin/AttendanceShifts_components/index.tsx`'s draft-shift
      object, which is now a required field on the type).
- [x] `npx tsc --noEmit` — clean, no errors.
- [x] `npx eslint .` — clean for every touched/new file; the one warning eslint reports elsewhere
      (`AttendanceShifts_components/index.tsx`: unused `ShiftsList` import) is pre-existing and
      confirmed via `git diff` to be untouched by this task (this task's only change to that file
      is the one-line `is_day_off: false` addition to the draft-shift object).
- [x] **Not visually verified in a browser** (browser automation tool use was declined twice
      across sessions on this task — accepted as out of reach here per explicit instruction).
      Verified instead by exercising the exact backend calls `ShiftScheduling.tsx` makes, live
      against the running dev API and real dev DB, as the seeded manager account
      (`multirole@test.com` / `Test@123`, subdomain `beta`, direct report `EmployeeMaster.id=283`):
      `GET /shifts/assignments` (roster load) → `POST /shifts/assignments` (assign, `201`) →
      `PUT /shifts/assignments/{id}` (change, `200`) → `GET /shifts/assignments` again (confirmed
      the cell reflects the change) → `DELETE /shifts/assignments/{id}` (cleanup, `204`). This
      confirms the create/update/list round-trip the frontend depends on works end-to-end; it does
      not confirm pixel-level rendering (toast copy, checkmark placement, view-toggle interaction).

Completed: 2026-08-17
