---
task: 205
title: Configure shift timing by dragging a 24h timing bar
status: done
depends_on: []
---

# 205 — Configure shift timing by dragging a 24h timing bar

**Clone / branch:** `workspace-2/hrms/`, branch `feature/gowtham_ShiftTimingSlider` (cut from `origin/main`).

## Scope

HR Admin → Attendance & Shifts. Today start/end are set only through two native
`<input type="time">` boxes in the editor's "Shift timing" header, while the table's
**Coverage · 24h** column draws each shift as a read-only `CoverageBar`. Make that same
Coverage bar **draggable for the row being edited** (existing shift or "New shift" row) so
HR sets the timing by sliding it — no second bar inside the editor (decided 09-Oct-26):

- **Track:** the open row's Coverage cell swaps `CoverageBar` for `TimingSlider` — same
  size/colour (`accentFor(s.color, s.code).bar`, fallback accent for a new shift), faint
  3-hour gridlines, no labels (the cell is ~175px).
- **Start handle** — drag to change `start_time`.
- **End handle** — drag to change `end_time`.
- **Body drag** — grab the filled segment and slide the whole shift; duration is kept.
- **Snap** to 15-minute steps (`SNAP_MINUTES = 15`).
- **Night shifts / midnight wrap:** when end ≤ start the segment wraps (draw two segments,
  exactly like `coverageSegments`). Dragging a handle past the other one is allowed and
  simply produces a wrapping (night) shift; dragging the body past 24:00 wraps modulo
  1440. A zero-length shift (start == end) is not allowed — clamp so the span is ≥ 15 min.
- **Live readout:** the open row's **Timing** and **Duration** cells follow the edit live
  (plus a HH:MM tooltip on the handle being dragged/focused). The save already computes
  `is_night_shift` from start/end — no change there.
- **Two-way sync** with the editor's `TimeField` inputs: start/end are lifted out of the
  `ShiftDefaults` draft into the table (`index.tsx` `openTiming`, type `Timing`), passed
  down as `timing`/`onTimingChange`. Typing moves the bar; dragging updates the inputs.
  Dirty-tracking (draft + timing vs baseline), the "Unsaved changes" guard and the PATCH
  diff / "Apply from today?" timing-change preview work unchanged. Typed times are NOT snapped
  (only drags snap) so an existing 09:10 shift isn't silently rewritten on open.
- **Accessibility:** each handle is `role="slider"` with `aria-valuemin=0`,
  `aria-valuemax=1439`, `aria-valuenow`, `aria-valuetext="09:30"`, focusable; ←/→ move
  15 min, Shift+←/→ move 60 min, Home/End jump to 00:00 / 23:45.
- **Pointer handling:** Pointer Events + `setPointerCapture` (mouse, touch, pen); no new
  dependency. `touch-action: none` on the track so touch-drag doesn't scroll the page.

**Explicitly NOT in scope**
- No backend/API/schema change — `start_time`/`end_time`/`is_night_shift` already exist on
  `PATCH/POST /shifts`; this is a pure frontend input.
- Rows that are not being edited keep the read-only `CoverageBar`.
- Break placement / grace windows drawn on the bar (break has no position in the data
  model — it's just `break_minutes`). Possible follow-up task.
- Manager Portal `ShiftScheduling.tsx` — untouched.

## Files

- `workspace-2/hrms/frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/coverage/TimingSlider.tsx` — **new**: the draggable twin of `CoverageBar` (controlled: `start`, `end`, `color`, `onChange(start, end)`).
- `.../AttendanceShifts_components/utils/shift.ts` — pure helpers: `fromMinutes`, `snapMinutes`, `wrapMinutes`, `isHHMM`, and the drag math (`moveStart`, `moveEnd`, `moveBody`).
- `.../AttendanceShifts_components/utils/types.ts` — `Draft` drops `start_time`/`end_time`; new `Timing` + `timingFromShift`.
- `.../AttendanceShifts_components/index.tsx` — owns `openTiming`; `timingCells()` renders Coverage/Timing/Duration (draggable + live for the open row and the New-shift row).
- `.../AttendanceShifts_components/components/ShiftDefaults.tsx` — takes `timing`/`onTimingChange` instead of draft start/end.
- `Skeleton.tsx` — no change (list-only skeleton).

## Acceptance criteria

- [ ] Opening an existing shift turns its row's Coverage bar draggable (handles appear); a night shift (e.g. 22:00–06:00) renders as two wrapped segments. Other rows stay read-only.
- [ ] Dragging the start handle, end handle, or the body updates the bar, the row's Timing/Duration cells and both editor time inputs live, in 15-min steps.
- [ ] Typing in a time input moves the bar (no snapping of typed values).
- [ ] Dragging a handle across the other produces a wrapping night shift; span never reaches 0.
- [ ] Body drag keeps the duration and wraps across midnight.
- [ ] Keyboard: ←/→ (15 min), Shift+←/→ (60 min), Home/End work on a focused handle; slider ARIA attributes present.
- [ ] Works with touch (no page scroll while dragging) — checked in devtools device mode.
- [ ] The "New shift" row shows a draggable 09:00–18:00 bar plus live Timing/Duration.
- [ ] Save after a drag sends only `start_time`/`end_time`/`is_night_shift` in the PATCH and triggers the existing "Apply from today?" timing prompt; cancel with unsaved drag shows the discard guard.
- [ ] New-shift flow: bar starts at 09:00–18:00 and saving creates the shift with the dragged times.
- [ ] Tailwind only (inline `style` only for the computed left/width % and the DB-driven shift colour); no new `.module.css`; no new npm dependency.
- [ ] `npx tsc --noEmit` and `npm run lint` clean for the touched files; manual smoke-check in the browser.

Completed: 2026-10-13
