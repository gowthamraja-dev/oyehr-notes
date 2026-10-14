---
task: 74
title: Manager attendance dashboard — backend tests hardening
status: done
depends_on: [69, 70, 71, 72, 73]
---

# 74 — Manager attendance dashboard — backend tests hardening

## Scope

Cross-cutting test coverage that spans tasks 68-73 rather than belonging to any one of them —
matches this project's own established pattern (see e.g. `37-attendance-clock-regularization-
tests-hardening.md`, `48-leave-request-tests-hardening.md`, `56-employee-directory-backend-tests-
hardening.md`: each feature cluster gets its own consolidated hardening pass after the individual
endpoint tasks land their own inline tests).

Each of 68-73 already specifies its own inline test list — this task is specifically for the
scenarios that only show up when the endpoints are exercised **together** against one realistic
fixture set, plus the two hardest domain rules the design prompt calls out by name (§15
night-shift boundary, §5/§17 leave/incomplete-punch correctness) end to end through the new
endpoints rather than unit-tested in isolation.

## What to add

1. **One shared fixture builder** — a manager with N direct reports across ≥2 departments and
   ≥2 shifts (including one night shift, e.g. 21:00→06:00), a date range covering at least one
   full week, with a deliberate mix of: on-time present, late present, on-leave (approved),
   week-off, holiday, missing clock-out, a pending regularization, and (for a past date) a
   never-punched Working day. Reuse this fixture across the new tests in this task rather than
   each test hand-rolling its own — this is what makes the "together" scenarios below tractable.
2. **Night-shift attendance date boundary** (design prompt §15): an employee on the 21:00→06:00
   shift punches in at 21:10 on day N and out at 06:05 on day N+1. Assert the summary (69),
   register (70), and export (73) all attribute this as **one** session on day N's row — not
   split across two dates, and not miscounted as absent on day N+1. This is exercising
   `attendance_recompute_service.py`'s existing shift-boundary handling *through* the new
   dashboard endpoints, not re-deriving it — if this fails, the bug is almost certainly in how a
   new endpoint queries by calendar date instead of `attendance_date`.
3. **Leave/week-off/holiday never shows Absent** (design prompt §5, §14): for every date in the
   fixture range where an employee has approved leave, a week-off, or a holiday, assert
   `effective_status` is never `Absent` in the summary counts, register rows, or exceptions list
   — and that the `attendance_percentage` denominator in task 69/72 excludes those days.
4. **Cross-tenant leak sweep**: one query against each of the five endpoints (69-73) with a
   second CDP's data present in the same test DB, asserting zero cross-tenant rows/counts appear
   anywhere, including in the CSV export body.
5. **Manager-scope sweep**: two managers, each with their own direct reports, both attendance
   data in the same date range; assert each manager's summary/register/exceptions/export never
   surfaces the other's reports.
6. **Consistency between endpoints on the same fixture/date**: the register's per-row
   `effective_status`/`is_late` values, summed by hand, must equal the summary endpoint's counts
   for the same `date`/filters — a regression here means task 69 and task 70 have silently
   diverged in their classification logic (both must call task 68's single `compute_
   effective_status`, not reimplement it).

## Files

- `backend/app/tests/modules/test_attendance.py` or a new `backend/app/tests/modules/
  test_attendance_dashboard.py` (prefer the new file — this cluster is large enough to warrant
  its own module, matching how `test_attendance_recompute.py` was split out from
  `test_attendance.py` originally)

## Acceptance criteria

- [x] All six scenarios above pass against the shared fixture.
- [x] Full backend test suite (`uv run pytest`) green, no regressions in the pre-existing 75+
      attendance tests from tasks 29-54.
- [x] `docs/leave-and-attendance/attendance/gaps.md`'s Addendum A / `README.md` §1.2's "auto-
      absent marking" exclusion is still accurate after this task — if a test in this task
      accidentally starts depending on auto-absent behavior existing, that's a sign task 68's
      date-boundary rule was implemented wrong, not a sign to add the batch job.
