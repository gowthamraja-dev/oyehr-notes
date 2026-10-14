---
task: 152
title: Attendance date-range filter — shared DateRangeField + API client/types (frontend)
status: done
depends_on: [150, 151]
---

# 152 — `DateRangeField` component and range-aware API client

> Part of requirement "4. Attendance Date Range Filters". Work in **`workspace-2/hrms/`**;
> paths are relative to it. Run `npm install` in `frontend/` first (no `node_modules` yet).

## Scope

Build the control and the client plumbing the HR Manager Attendance page (153) uses. Admin
Insights reuses that same page (154), so there is exactly one consumer. No page wiring here.

### `frontend/src/components/ui/DateRangeField.tsx` (new)
- Built from **two `DateField`s** (`frontend/src/components/ui/DateField.tsx`), never a bare
  `<input type="date">`; dates display dd-MMM-yy (`hrms-date-format` skill).
- Props: `value: { from: string; to: string }` (ISO `YYYY-MM-DD`), `onChange`, `max?` (the pages
  pass today), `maxDays?` (default `31`, matching backend `MAX_REGISTER_RANGE_DAYS`).
- Presets dropdown: Today · Yesterday · This week (Mon–Sun, capped at `max`) · Last 7 days ·
  This month (capped at `max`) · Last month · Custom. Selecting a preset sets both ends; editing
  either field switches the label to Custom (or to the matching preset).
- Invariants enforced in the control (the backend rejects both with 422 anyway): moving `from`
  past `to` pulls `to` along, and vice versa; a span over `maxDays` is clamped on the edited
  end with a short inline hint ("Max 31 days").
- Tailwind only; matches the existing header controls (`h-9`, `rounded-[9px]`,
  `border-border`, `bg-white`, `text-ink-600`).

### `frontend/src/lib/dateRange.ts` (new)
Move `toISODate` / `todayIso` / `addDaysIso` out of `hrManager/Attendance.tsx` into this file.
The Insights copy in `AttendanceInsights.tsx` is deleted in task 154, so leave it alone here.
Then add: `type DateRange`, `rangeDays(r)`, `shiftRange(r, direction)` (moves the
whole window by its own length; a one-day range moves by one day, as the arrows do today),
`isSingleDay(r)`, `formatRangeLabel(r)` (dd-MMM-yy – dd-MMM-yy, or one date when single-day).

### `frontend/src/lib/api.ts`
- `getManagerAttendanceSummary`, `getManagerAttendanceRegister`,
  `getManagerAttendanceExceptions`, `exportAttendanceRegister`: replace the `date: string` param
  with `from: string; to: string`. Send `?date=` when `from === to` (keeps the single-day
  request identical to today's), else `?from=&to=`.
- `AttendanceRegisterSort` gains `"date"`.
- `AttendanceRegisterRow` gains `attendance_date: string; day_label: string`.
- `AttendanceAnalytics.period` gains `"range"`, plus `from: string; to: string`.
- `AttendanceExceptions` gains `from: string; to: string`.
- Leave the `secureFetch` / plain-`fetch` split exactly as it is (export stays plain `fetch`).

## Files
- `frontend/src/components/ui/DateRangeField.tsx` (new)
- `frontend/src/lib/dateRange.ts` (new)
- `frontend/src/lib/api.ts`

## Acceptance criteria
- [x] `DateRangeField` renders dd-MMM-yy for both ends, opens the native picker on click, and
      respects `max`. It's built on `DateField`, so these come from there; the in-browser check is
      carried into task 153, where the control is first mounted.
- [x] Every preset yields the expected `{from, to}` (spot-check around a month boundary and a
      Sunday).
- [x] from/to crossing and the 31-day cap are enforced in the control.
- [x] Single-day calls still send `?date=`; multi-day calls send `?from=&to=` (`setDateRangeParams`).
      The network-tab check is carried into task 153.
- [x] `npm run lint` and `npx tsc --noEmit` clean. Callers of the changed API functions
      (`hrManager/Attendance.tsx`, and the soon-deleted `AttendanceInsights*.tsx`) may only be
      left broken if 152 and 153 land in the same change. Otherwise keep a compiling shim.

## What shipped
- `src/components/ui/DateField.tsx`: `formatDDMMMYY` exported as the shared display formatter
  (the hrms-date-format skill says to consolidate there, not copy it).
- `src/lib/dateRange.ts`: `DateRange`, `MAX_RANGE_DAYS = 31`, `toISODate` / `todayIso` /
  `addDaysIso` (moved out of `hrManager/Attendance.tsx`), `rangeDays` (UTC day math, DST-safe),
  `isSingleDay`, `singleDay`, `shiftRange`, `formatRangeLabel`, `RANGE_PRESETS`, `presetRange`,
  `matchPreset`, `editRange` (the other end follows the edited one when they'd cross; the span
  clamp pulls the other end in and reports `clamped`).
- `src/components/ui/DateRangeField.tsx`: presets `<select>` + two `DateField`s + "Max 31 days"
  hint. "Custom" sticks while the user edits, but only for the range it was picked at, so an
  outside change (the Today button, arrows) re-matches the preset label.
- `src/lib/api.ts`: `getManagerAttendanceSummary` / `…Register` / `…Exceptions` /
  `exportAttendanceRegister` take `from` + `to` via `setDateRangeParams` (one day → `?date=`).
  Types gain `attendance_date` / `day_label`, `from` / `to`, `period: "range"`, and sort `"date"`.
- Compiling shim: the three callers (`hrManager/Attendance.tsx`, and `AttendanceInsights.tsx` /
  `AttendanceInsightsRegister.tsx`, due for deletion in 154) pass `from = to = selectedDate`.
- Verified: `npx tsc --noEmit` clean. eslint shows no new problems (the 6 `set-state-in-effect`
  errors in the pages and 1 unused-`useState` warning in `DateField.tsx` were already there).
  `dateRange.ts` was transpiled with the project's `typescript` and 26 assertions run under
  TZ=Asia/Kolkata and America/New_York (Sunday week, a Wednesday capped at today, Feb/Mar and
  Dec/Jan boundaries, preset round-trip, crossing, both clamp directions, exactly 31 days).

Completed: 2026-09-29
