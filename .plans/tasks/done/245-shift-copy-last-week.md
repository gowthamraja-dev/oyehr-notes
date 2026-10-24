---
task: 245
title: Copy last week's roster to this week
status: done
depends_on: [241, 243]
---

# 245 — Copy last week's roster to this week

## Scope
Most common rota workflow after bulk apply: "repeat last week". Action on the Shift Scheduling
page for the currently filtered employees: reads the previous week's resolved roster (shift +
location per weekday) and writes it to the viewed week via the range endpoint (task 241), one
run per contiguous same-shift/location stretch. Confirm with `useConfirm()` (never native
`confirm()`), show the summary of applied/skipped. Weekly offs and locked/past days skipped.
Backend helper `POST /employee-shifts/copy-week` only if doing it client-side proves too chatty.

## Files
`ShiftScheduling.tsx`, `api.ts`, optionally `shifts/{router,service,schemas}.py` + tests.

## Acceptance criteria
- [x] Copy week N-1 → N reproduces shifts and locations for filtered employees
- [x] Past/locked days untouched and reported; confirm dialog uses `useConfirm`
- [x] Idempotent (second run → all "unchanged")

## Implementation notes (2026-10-24)
- Done as a backend helper, not client-side: copying a mixed week by calling `/range` would need one request per distinct
  (shift, location, calendar, weekday-set) and would not be atomic (a failure mid-way leaves a half-copied week). `POST /employee-shifts/copy`
  `{employee_master_ids, source_from_date, target_from_date, days}` is one transaction; the week UI always sends a 7-day offset.
- Refactor behind it: the per-employee core of `set_employee_shift_for_range` is now `_plan_and_apply_employee_days` (skip rules + bounded-row
  runs + activity log), shared by range and copy, with `_range_out` / `_new_range_totals`. Behaviour unchanged (all 145 pre-existing shift tests
  still pass).
- Copy semantics: sources read from a pre-write snapshot (overlapping windows copy what was there); a source day with no usable shift (none, or
  the shift was archived) leaves the target day alone and is reported as `no_standing_shift`; an identical day is "unchanged", so a standing-row
  week writes nothing and a re-run changes nothing; HR copy overwrites hand-set single days; weekly offs of the shift being written are skipped.
- UI: "Copy last week" in the week view's roster header (hidden in month view). Targets everyone currently shown (the filtered roster) — ticked
  rows are not consulted. In the current week the target starts today (no copying onto elapsed days). `useConfirm` dialog, then a toast;
  the summary dialog (`RangeResultModal`, extracted with `RangeResultBody` into `shared/ShiftRangeResult.tsx` and reused by the assign modal)
  only opens when a locked / outside-employment day was skipped — "no shift last week" is routine in a sparse roster and only counted in the toast.
- Not done: copying a month, or copying from an arbitrary earlier week (the API supports any offset; the UI offers last week only).

## Browser smoke (2026-10-24)
Headless Chrome vs the local stack, 17/17: confirm dialog (clamped 17–18 Oct → 24–25 Oct in the current week; Cancel sends nothing); copy
2–8 Nov → 9–15 Nov for 7 employees = one `POST copy`; Priya's Mon–Wed GEN@Head Office (her conflicting Tue replaced) and Thu–Fri LAT@Work From Home,
Sat/Sun untouched; Nisha's standing shift written nothing; Rohan GEN to his relieving date and 13–15 Nov reported "Outside employment dates"; Kabir's
existing day left alone; second run identical ("0 copied, 16 already the same"); button hidden in month view. DB: bounded rows only.
