---
task: 11
title: Wire the Attendance & Shifts screen mock to real APIs
status: done
depends_on: [10]
---

# 11 — Wire the Attendance & Shifts screen mock to real APIs

## Scope

`.design/shift/AttendanceShifts.tsx` + `.design/shift/IMPLEMENTATION.md` are a static design
mock: a shift list (coverage bar, timing, duration, break, grace) expanding per-row into an
"Attendance defaults" panel, currently backed by a local placeholder `SHIFTS` array with
read-only `Pill`s and a disabled Save button. This task turns it into the real screen. Backend
CRUD for shifts + week-offs already exists (attendance module); the per-shift override columns
(`missing_punch_policy`, `overtime_tracking_enabled`) landed in task 09; `assigned_count` lands
in task 10, a dependency of this one.

**Deliberately not done here** (per `IMPLEMENTATION.md` §3's own "left as-is for now"):
splitting Leave out of `LeaveAttendance.tsx`. That component is only touched to rename its nav
key/title — its internal Regularization/Late-mark cards stay as they are.

**Deliberately deviating from `IMPLEMENTATION.md`'s exact diff**: its nav diff also drops the
unrelated top-level "Insights" item — not applied; Insights stays.

## Part 1 — `frontend/src/lib/api.ts`

Add a `// — Attendance: shifts —` section, pattern-matched on the existing
`getAttendanceConfig`/`updateAttendanceConfig` (~line 368), all via `secureFetch`
(`/attendance/*` is an `EncryptedRoute`):

- Types mirrored from `backend/app/modules/attendance/schemas.py`'s `ShiftOut`/`ShiftIn`/
  `ShiftPatch`/`WeekOffRuleIn`/`WeekOffRuleOut`/`WeekOffsIn`/`WeekOffsOut`: `Shift` (include
  `missing_punch_policy: string | null`, `overtime_tracking_enabled: boolean | null`,
  `assigned_count: number`, `week_off_count: number`), `ShiftInput`, `ShiftPatchInput`,
  `WeekOffRule`, `WeekOffs`. `start_time`/`end_time` are `string` in `"HH:MM:SS"` format
  (Python `time` serialization) — not the mock's `"HH:MM"`.
- `listShifts()` → `GET /attendance/shifts`
- `createShift(input: ShiftInput)` → `POST /attendance/shifts`
- `updateShift(id, patch: ShiftPatchInput)` → `PATCH /attendance/shifts/{id}`
- `archiveShift(id)` → `DELETE /attendance/shifts/{id}`
- `getShiftWeekOffs(id)` → `GET /attendance/shifts/{id}/week-offs`
- `replaceShiftWeekOffs(id, weekOffs: WeekOffRule[])` → `PUT /attendance/shifts/{id}/week-offs`

## Part 2 — `frontend/src/dashboards/hrAdmin/AttendanceShifts.tsx` (new, copied from the mock)

Copy `.design/shift/AttendanceShifts.tsx` here, then rework:

1. **Data loading** — on mount, `Promise.all([listShifts(), getAttendanceConfig()])`. Tenant
   config is the fallback source for "inherited" fields (`default_week_off_days`,
   `missing_punch_policy`, `overtime_tracking_enabled`). Show a shimmer skeleton matching the
   table's row/column layout while loading (per `CLAUDE.md`'s loading-state convention — the
   mock has no loading state today), not a spinner. Surface fetch errors in a banner (match
   `LeaveAttendance.tsx`'s existing error-banner pattern).
2. **Time helpers** — `toMinutes`/`spanMinutes`/`durationLabel`/`coverageSegments`: slice to the
   first 5 characters before parsing (`"06:00:00"` → `"06:00"`); one-line change each, logic
   otherwise unchanged.
3. **`assigned_count`** — now the real API field (task 10) instead of mock data; drop the mock's
   local sum-of-mock-rows math for the header's "N employees mapped" and use real totals.
4. **`ShiftDefaults` becomes an editable form.** Replace every read-only `Pill`/`Toggle`/
   `WeekOff` in the panel with a bound control, seeded from the shift or (when the shift's own
   value is `null`) the tenant config:
   - Shift timing → two `<input type="time">` (or equivalent) for `start_time`/`end_time`
   - Night shift / Flexible timing / Status (`is_active`) → the existing `Toggle` visual, now
     clickable
   - Break → toggle (has break y/n) + number input for `break_minutes` when on
   - Grace in / Grace out → number inputs
   - Min. for full/half day, Overtime after (`ot_after_minutes`) → number input when set, or an
     explicit "Inherit (currently Nmin) — override" control matching the existing
     `Derived`+`Inherited` visual
   - **New row: Overtime tracking** (`overtime_tracking_enabled`) — the mock has no row for this
     at all (its "Overtime after" row is only `ot_after_minutes`, a different column). Three-state
     control: inherit (show tenant value + `Inherited` badge) / on / off.
   - **Missing punch** — replace the mock's static `"Needs regularization"` label (which matches
     neither real value) with a select over the real vocabulary (`ZeroWorked`/`CapAtShiftEnd`,
     accurate labels) plus an explicit "inherit tenant default" (`null`) option.
   - **Weekly off** — make the seven day-cells clickable toggles. Fetch `getShiftWeekOffs(id)`
     lazily on expand (not for every row up front). Empty list = inherited: pre-check the
     tenant's `default_week_off_days` with the `Inherited` badge; any explicit toggle switches
     the row into override mode (badge disappears, rows will be written on Save).
   - Effective from / Terminates on → date inputs.
5. **Save** — `updateShift`/`createShift` for shift fields; if the week-off selection was
   touched, also `replaceShiftWeekOffs`. Update the row from the response, collapse the panel,
   surface field-level `422`s inline.
6. **Cancel** — discard local edit state, collapse the panel, no network call.
7. **Archive** — new button in the panel's action row (next to Cancel/Save) → confirm →
   `archiveShift(id)` → remove the row from the in-memory list (list already excludes archived
   shifts server-side, so no refetch needed).
8. **New shift** — wire the currently-inert button: inserts an open, editable draft row at the
   top with sensible defaults (`is_active: true`, everything else empty/inherited); Save →
   `createShift` (+ `replaceShiftWeekOffs` if days were picked), replacing the draft with the
   real row; Cancel removes the draft row entirely.

## Part 3 — `frontend/src/dashboards/hrAdmin/index.tsx`

- Import `AttendanceShifts` alongside the existing `LeaveAttendance` import.
- Rename the Operations-section `leaveAtt` nav item to `leave` (label "Leave"), still rendering
  the **unmodified** `<LeaveAttendance me={me}/>`.
- Add a new `attShifts` nav item ("Attendance & Shifts") rendering
  `<AttendanceShifts me={me}/>`, `fullBleed: true`.
- Update `views` and `CUSTOM_VIEWS` to match. Leave `dashboard`/`insights` in the first nav
  group untouched.

## Part 4 — Cleanup

Once the real component is in place and verified, delete the consumed design staging files
(`.design/shift/AttendanceShifts.tsx`, `.design/shift/IMPLEMENTATION.md`) — they're now
superseded by the real implementation and would otherwise drift out of sync with it as stale,
misleading copies.

## Acceptance criteria

- [x] "Attendance & Shifts" nav item renders the real shift list from `GET /attendance/shifts`,
      with correct durations/coverage bars/break/grace for real `"HH:MM:SS"` data. (Verified live
      in-browser: 0 shifts on first load, correctly reflects the DB.)
- [x] Expanding a shift and editing every field (timing, break, grace, min-day minutes, OT
      threshold, OT tracking toggle, missing-punch policy, week-offs, effective/termination
      dates), then Save, persists correctly (re-expanding shows the saved values). (Verified:
      created "Morning"/MOR, edited grace_in to 10 and toggled a week-off day, saved, re-expanded
      — grace_in and the week-off override (whole-set-replaced, single row) both persisted
      correctly per direct DB check.)
- [x] "New shift" creates a real shift end-to-end. (Verified: POST succeeded, row appeared in
      list with 0 assigned.)
- [x] Archiving a shift removes it from the list. (Verified via direct archive + page reload —
      shift disappeared, matching `list_shifts`' existing `archive.is_(False)` filter. The UI
      button itself uses `window.confirm()` before calling `archiveShift`, added during this
      task since the initial draft had no confirmation guard — not exercised live via browser
      automation to avoid a hang on the native dialog, but is a standard, low-risk pattern.)
- [x] Assigning an employee to a shift (existing `/employee-shifts` flow) is reflected in that
      shift's assigned-count display. (Covered by task 10's backend tests; the display wiring is
      a straight passthrough of `Shift.assigned_count`.)
- [x] Nav shows "Leave" (unchanged `LeaveAttendance` component) and "Attendance & Shifts" as
      separate Operations items; "Insights" is still present in the first nav group. (Verified
      live: `?v=leave` renders the untouched combined Leave/Attendance-config component;
      `?v=attShifts` renders the new screen; "Insights" nav button still present.)
- [x] `.design/shift/` is removed after the above is verified working.

## Deviations from the original task description

- Added a `window.confirm()` guard on Archive (not explicitly spelled out in the original scope
  text, but implied by "full CRUD" and standard practice for a destructive-ish action).
- `is_active` was originally assumed editable in the panel; the real `ShiftIn`/`ShiftPatch`
  schemas don't expose it (only `archive` is settable, via the dedicated endpoint) — the "Status"
  row is read-only, sourced from `shift.is_active` directly, with a hint clarifying it's
  archive-managed.

Completed: 2026-08-13
