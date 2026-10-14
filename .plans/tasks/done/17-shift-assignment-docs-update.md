---
task: 17
title: Update leave-and-attendance shifts docs for the per-date assignment migration
status: done
depends_on: [13, 14, 15, 16]
---

# 17 — Update `docs/leave-and-attendance/shifts/` docs

## Scope

Tasks 13-16 migrate the Manager Portal's shift roster from `employee_shift_details`
(effective-dated) to `employee_shift_assignments` (per-date) — this task brings the doc set that
describes that flow back in sync, per `CLAUDE.md`'s documentation convention. Docs-only, no code.

## Files

### `docs/leave-and-attendance/shifts/manager-scheduling.md`

Rewrite §4 ("Shift scheduling") to state the new reality:

- Each cell's assignment now writes a real per-date `employee_shift_assignments` row (task 13),
  not a new `employee_shift_details` row — the "seven one-day rows per employee per week" line
  (previously a *workaround inside* the effective-dated model) is now simply how the model
  natively works, not a degenerate special case. Update the intro paragraph's claim that
  `ShiftScheduling.tsx` calls `listTeamEmployeeShifts`/`assignEmployeeShift` — it now calls
  `listShiftAssignments`/`createShiftAssignment`/`updateShiftAssignment`/`cancelShiftAssignment`
  against `GET/POST /shifts/assignments`, `PUT/DELETE /shifts/assignments/{id}` (task 14).
- Document the new filters/view-toggle/legend/richer-modal behavior from task 16 (department/role/
  employee-search, All/By-department/By-role, Off/"Rest day" shifts, unassign, toasts).
- Remove the "Publish roster" mention from the grid description, or mark it explicitly still
  absent — task 15's bulk endpoint exists but has no UI in this task set (no "publish" action was
  built).
- Update the "Deferred on this screen" table: the *"Open shifts: 12"* KPI and the shift-swap
  section are still deferred (unchanged, still no table for either). Remove *"Coverage %, Shifts
  this week"* from "deferred" if task 16 doesn't compute them — check task 16's actual delivered
  KPIs and state truthfully whichever ended up shipped vs still deferred.

### `docs/leave-and-attendance/shifts/api-and-pages.md`

Add the five new endpoints from tasks 14-15 to the endpoint index, matching whatever section
format the file already uses for the existing `/shifts/*` routes:

```text
GET    /api/v1/shifts/assignments             — roster query (from, to, department, role, employee_master_id)
POST   /api/v1/shifts/assignments             — create/assign a shift for one employee+date
PUT    /api/v1/shifts/assignments/{id}        — change the shift on an existing assignment
DELETE /api/v1/shifts/assignments/{id}        — soft-cancel an assignment
POST   /api/v1/shifts/assignments/bulk        — all-or-nothing bulk assign (no frontend consumer yet)
```

### `docs/leave-and-attendance/shifts/domain-model.md`

Add `employee_shift_assignments` and `shift_assignment_audits` to the table inventory, alongside
the existing `shift_masters`/`employee_shift_details`/`shift_week_off_details` entries — one
paragraph each per this doc's existing per-table format (owner, unique key, lifecycle: mutable
with soft-cancel via `status`, for the assignment table; append-only, for the audit table). Note
`shift_masters.is_day_off` in its existing entry.

### `docs/leave-and-attendance/shifts/gaps.md`

- **Update #3** ("Per-day rostering is degenerate, and 'Open shifts' is impossible") — record the
  resolution actually taken: **the "add a roster table" branch was chosen** for the Manager
  Portal specifically — `employee_shift_assignments` (task 13) is a real per-day table, so
  rostering is no longer degenerate *for that screen*. The *"Open shifts"* KPI is still impossible
  (no table holds a shift with no employee) — that half of the gap stays open. Keep the gap number
  (#3) but rewrite its body to reflect this partial resolution rather than deleting it — gap
  numbers are never renumbered per this file's own header note.
- **Add a new gap**, numbered per this corpus's existing global numbering scheme (check
  `../README.md` for the next free number before writing): **`employee_shift_assignments` and
  `employee_shift_details` are two independent, unsynced datasets.** A manager's per-date
  assignment (new table) does not feed the attendance assembler's effective-shift resolution
  (`docs/leave-and-attendance/05-attendance-assembler.md` §3, still reads only
  `employee_shift_details`) or the HR Admin "Attendance & Shifts" screen's `assigned_count` (tasks
  09-11, also `employee_shift_details`-only). Whether to dual-write, migrate the assembler onto the
  new table, or deliberately keep them separate forever is an open decision for whoever wires
  per-date manager scheduling into actual attendance calculation — explicitly out of scope for
  tasks 13-17.
- Note in passing (near #20, "No constraint on overlapping `employee_shift_details` date ranges")
  that this gap is specific to `employee_shift_details` and does **not** apply to the new
  `employee_shift_assignments` table — its `UniqueConstraint(employee_master_id,
  assignment_date)` makes date-range overlap structurally impossible there.

### `docs/leave-and-attendance/shifts/admin-configuration.md`

Add one line noting `shift_masters.is_day_off` (task 13) — a nullable-with-default boolean,
settable today only via direct API call (no toggle in `AttendanceShifts.tsx` yet); flag that
wiring an admin-UI control for it is a natural, still-open follow-up.

## Acceptance criteria

- [x] `manager-scheduling.md` accurately describes the per-date API calls, new filters/legend/
      modal behavior, and the accurate (not aspirational) state of "Publish roster"/KPIs, verified
      against what tasks 14-16 actually shipped (not this task file's original plan — task 16's
      own "Discussion" section was used as the ground truth for what actually landed, since it
      differs from this task's original spec after reconciling with the real `.dc.html` mockup).
- [x] `api-and-pages.md` lists all five new endpoints with correct methods/paths, in both the §3.1
      (admin) and §3.2 (manager) tables, plus notes that the pre-task-16 `/employee-shifts*` /
      `/team/employee-shifts` endpoints are unchanged and still serve other callers.
- [x] `domain-model.md` documents both new tables (`employee_shift_assignments` §2.6,
      `shift_assignment_audits` §2.7) and the `is_day_off` column on `shift_masters`.
- [x] `gaps.md` #3 is rewritten to record the partial resolution (roster table added, "Open
      shifts" KPI still impossible); a new gap entry (#43 — next free number past the 42-item
      original survey, per `../README.md`) documents the `employee_shift_assignments` vs
      `employee_shift_details` sync gap; the note that gap #20 is `employee_shift_details`-specific
      is added.
- [x] `admin-configuration.md` notes `is_day_off` and that no admin-UI toggle exists yet; also
      corrected its §6 "Employee shift assignment" section, which previously implied the Manager
      Portal still shares this table (it doesn't, as of task 16).
- [x] No code files touched — confirmed via `git status` (docs/ is gitignored in this repo, so
      these edits don't appear there at all; the only files `git status` shows are the ones already
      attributable to tasks 13-16).

Completed: 2026-08-17
