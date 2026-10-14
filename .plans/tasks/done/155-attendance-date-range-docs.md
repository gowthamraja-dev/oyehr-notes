---
task: 155
title: Attendance date-range filter — docs update
status: done
depends_on: [150, 151, 153, 154]
---

# 155 — Document the date-range contract

> Part of requirement "4. Attendance Date Range Filters". Work in **`workspace-2/hrms/`**;
> paths are relative to it.

## Scope

Update the existing attendance docs to match what shipped. No new doc: this extends a
documented endpoint set.

`docs/leave-and-attendance/attendance/api-and-pages.md`:
- §3.1 / §3.2 endpoint tables (`/register`, `/analytics`, `/exceptions`, `/register/export`
  rows): add `from=&to=` as the alternative to `date=`; state the 31-day cap and the 422 rules.
- §4.4 (`/register`), §4.5 (`/analytics`), §4.8 (`/exceptions`) and the export section: a range
  example request/response showing `attendance_date`/`day_label` on rows, `period: "range"` +
  `from`/`to` on analytics, employee-day semantics of the counts, the CSV `Date`/`Day` columns,
  and the range filename.
- The page table row for `attendance` (manager): "date/period" →
  "date range (presets, max 31 days)/period". The admin Insights → Attendance row now points
  out that it renders the same `hrManager/Attendance.tsx` component (task 154: no separate
  Overview/Register views, no drawer "Review" link for admin).
- If task 150 added `resolve_effective_shifts_for_range`, note it in
  `docs/leave-and-attendance/attendance/assembler.md` next to `resolve_effective_shift`.

## Files
- `docs/leave-and-attendance/attendance/api-and-pages.md`
- `docs/leave-and-attendance/attendance/assembler.md` (only if the batched resolver exists)

## Acceptance criteria
- [x] Every param, field and 422 rule in the docs matches the code (spot-check against
      `router.py` / `schemas.py`).
- [x] Examples use real field names and dd-MMM-yy only where the UI/CSV shows dates (API
      payloads stay ISO).

## Progress (29-Sep-26)
Docs only, in `workspace-2/hrms/` (branch `feature/gowtham_AttendanceDateRange`, uncommitted).

`docs/leave-and-attendance/attendance/api-and-pages.md`:
- §2.1: new `insights` ▸ *Attendance* row. It mounts `hrManager/Attendance.tsx` `embedded`, has no
  separate Overview/Register views and no drawer "Review" link (no `navigate`), and admin scope =
  whole CDP.
- §2.3 `attendance` row: date range (the 7 presets from `lib/dateRange.ts`, max 31 days,
  `components/ui/DateRangeField.tsx`), the range label replacing the Day/Week/Month band, and
  employee-day rows with a Date column, newest first.
- §3.1 / §3.2: the `/register`, `/analytics`, `/exceptions` and `/register/export` rows (admin +
  manager) show `?date=` **or** `?from=&to=`, max 31 days, and task numbers.
- §4.4: `sort` gains `date`; the sample row adds `is_half_day`, `attendance_date` and `day_label`.
  New "Date window" subsection (shared by all four routes): the `date` | `from`+`to` table, the
  three exact 422 `detail`s from `router._date_range`, no future-date rejection, employee-day
  semantics (synthesized rows, per-day `shift_id`, per-day `has_pending_regularization`,
  `total` = employee-days), `sort=date` behaviour, and a range example.
- §4.5: the sample adds `from`/`to` (band window = the `period` window for a single date). Range
  section: `period: "range"`, employee-day counts, `yet_to_checkin` only when the window includes
  today, the % denominator, headcount = distinct employees, and a worked example.
- §4.8: the sample adds `from`/`to`. Range: employee-day counts (`stale_open_session` per later
  day), `items` newest day first.
- §4.10: the CSV header gains `Date` (dd-MMM-yy) / `Day` on every export. Range: one line per
  employee-day, newest day → status → name, filename `attendance-{from}_to_{to}.csv`, audit
  `new_value` `from`/`to` (+ `date`). The single-date sample's clock-in is now local time
  (09:32:00), matching the text and the code.

`docs/leave-and-attendance/attendance/assembler.md`: new §3.4 "Batched resolution" covers
`resolve_effective_shifts_for_range` and `resolve_day_types_for_pairs` (signatures, queries, the
rule-for-rule parity test `test_calendar_resolver_batch.py`, and task 150's measured timings).

Differences between this task's text and the code (the docs follow the code):
- The batched resolver's signature is `(db, tenant_id, employee_ids, dates)` (a list of dates),
  not `(…, employee_ids, from_, to)`. It also has a companion `resolve_day_types_for_pairs`.
- `assembler.md` §3's SQL filters `is_active AND NOT archive` and tie-breaks on `id`. The shipped
  single-date query (`shifts.service._resolve_effective_row`) does neither, and neither does the
  batched one's `is_active`/`archive` handling. Noted in §3.4; §3 itself is left unchanged
  (out of scope).

Completed: 2026-09-29
