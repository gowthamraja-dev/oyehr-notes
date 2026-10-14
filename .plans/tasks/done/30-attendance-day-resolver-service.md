---
task: 30
title: Shared day resolver + per-employee-date attendance recompute service
status: done
depends_on: []
---

# 30 — Shared day resolver + per-employee-date attendance recompute service

## Discussion

The authoritative spec for "punches → a settled attendance row" is
`docs/leave-and-attendance/attendance/assembler.md` — a **batch job** that sweeps every employee
over a date window on a schedule. This repo has no job-running mechanism at all
(`docs/leave-and-attendance/shared/jobs-and-scheduling.md` — no cron, Celery, APScheduler,
anything), and building one is a separate, cross-cutting initiative shared with leave
accrual/rollover — out of scope for "Clock In/Out & Request Regularization"
(`.design/prompts/Attendance_Clock_In_Out_Regularization_Plan.md` §29's phase boundary).

**This task builds an event-driven substitute**: a pure function that (re)computes exactly one
`employee_attendance_details` row for one `(employee, date)`, called synchronously by task 31
(clock-in/out), task 32 (regularization submit, for validation lookups) and task 33
(regularization approve, after materializing punches). It implements the same rules as
`assembler.md`, reduced to what a single on-demand call needs — most of the reduction is simply
"no calendar sweep, no cross-employee batching, no watermark"; the per-row algorithm itself
(business-date attribution, punch pairing, status derivation, late/early, worked minutes,
payable fraction) is followed faithfully because it's what keeps this task set's numbers
consistent with `assembler.md` if/when the real batch job is ever built on top of the same
tables. **Deliberately reduced, not reinvented:**

- **No leave integration** (`assembler.md §6` rows 1, 8, 9 — `OnLeave`/half-day-leave). The
  `leave` module doesn't exist in this codebase yet (`.plans/tasks/ongoing/21-28`). Those rows
  are simply never reached — `attendance_status` never becomes `OnLeave` in this task set. This
  is a consequence of the leave module's absence, not a special case to code around.
  `leave_request_detail_id` stays NULL always.
- **No `OnDuty`/`WFH` rows** (`assembler.md §6` rows 6, 7) — those request types are out of scope
  per task 29's discussion; only `Regularization` exists in this task set's data.
  `payable_day_fraction`'s `leave_fraction` term is therefore always 0 and the "approved
  OnDuty/WFH covers the full day" branch never fires — the formula in §3 below is `assembler.md
  §9` with those terms omitted, not a different formula.
- **No overtime** (`assembler.md §8.1`) — `overtime_minutes` is always `0`.
- **No auto-absent** (`assembler.md §11`) — that requires a scheduled sweep for employees who
  never punch at all; there is nothing to trigger it synchronously. A `Working` day with zero
  punches simply has no row (nothing calls the recompute function for a date nobody touched) or
  stays `attendance_status = NULL` if a row exists from a previous partial computation. Tracked as
  a known gap for whoever eventually builds the job runner — not silently patched over here.
- **No night-shift lookback beyond yesterday/today/tomorrow.** `assembler.md §2.3`'s general
  attribution rule considers arbitrary adjacent shifts; this function only ever needs to place a
  punch happening *now*, so it resolves the shift for `today-1`, `today` and `today+1` and picks
  whichever window contains `now()` — sufic for a live clock action, not for a bulk historical
  import (out of scope; `punch_source='Import'` is never written by this task set).

## Files

### New

- `backend/app/services/calendar_resolver_service.py` — the shared shift/day-type resolver
  (`docs/leave-and-attendance/README.md §3.4` calls one shared implementation a hard architectural
  requirement so a future leave-module day-row builder doesn't compute `day_type` differently and
  silently disagree with this module). Pure functions, no FastAPI imports, callable from tests:

  ```python
  def resolve_effective_shift(
      db: Session, tenant_id: int, employee_id: int, target_date: date,
  ) -> ResolvedShift | None:
      """assembler.md §3: per-date `employee_shift_assignments` row (status='ASSIGNED') wins;
      else the standing `employee_shift_details` row effective on target_date; else None.
      Reuses the exact precedence already implemented as
      `app.modules.shifts.service._resolve_employee_shift` — that function is made
      non-private (renamed, exported) and this service becomes its second caller, rather
      than duplicating the query. Returns (shift: ShiftMaster, work_location_master_id,
      holiday_calendar_master_id, source: "assignment"|"standing") or None (no assignment
      at all — assembler.md §3.3: treat as day_type=Working via CDP fallback, thresholds
      from hardcoded defaults below, since no tenant_params.py exists to override them).
      """

  def resolve_day_type(
      db: Session, tenant_id: int, employee_id: int, target_date: date,
      resolved_shift: ResolvedShift | None,
  ) -> DayTypeResolution:
      """assembler.md §4: Holiday > WeekOff > Working precedence.
      - Holiday: `shifts.service`'s existing holiday-calendar fallback chain (assignment's
        calendar -> location's calendar -> all-locations calendar), `holiday_type='Public'`
        only (Restricted/Optional stay Working — assembler.md §4.2). Reuse/adapt
        `attendance.service.get_resolved_holidays`'s calendar-selection logic rather than
        re-deriving it — do not fork a second calendar picker.
      - WeekOff: query `shift_week_off_details` for the resolved shift, match
        `day_of_week = iso_dow(D)` and `(week_of_month IS NULL OR week_of_month =
        nth_occurrence(D))` per assembler.md §4.1's Nth-occurrence-in-month rule
        (`floor((day_of_month(D)-1)/7)+1`), `is_half_day=false` -> WeekOff,
        `is_half_day=true` -> stays Working with halved thresholds.
      - No shift resolved at all: CDP fallback `default_week_off_days` isn't backed by any
        config surface (config-knobs.md §1.2 — "not exposed through a live endpoint");
        hardcode Sat/Sun (ISO 6,7) as the fallback, matching the documented default value.
      Returns day_type plus the halved-threshold flag and the resolved holiday_detail_id.
      """

  def resolve_timezone(resolved_shift: ResolvedShift | None) -> str:
      """work_location_masters.time_zone of the resolved location, else 'Asia/Kolkata'
      (config-knobs.md §1.2 default_time_zone — hardcoded, no tenant override surface)."""
  ```

  `ResolvedShift` / `DayTypeResolution` are small `@dataclass`es in the same file, not Pydantic
  (this is a service-layer, not wire-layer, shape).

- `backend/app/services/attendance_recompute_service.py` — the per-row "mini-assembler":

  ```python
  def recompute_attendance_day(
      db: Session, tenant_id: int, employee_id: int, target_date: date,
  ) -> EmployeeAttendanceDetail:
      """Idempotent upsert-by-(cdp, employee, date) into employee_attendance_details.
      Skips entirely (returns the existing row untouched) if `is_locked = true`
      (assembler.md §10, defensive only — nothing sets is_locked in this task set).

      1. resolve_effective_shift + resolve_day_type + resolve_timezone (above).
      2. shift_start_at / shift_end_at as UTC instants (assembler.md §2.2) — the night-shift
         end-date-rollover rule (`+1 day if is_night_shift or end_time <= start_time`).
      3. Candidate punches: all `attendance_punch_details` rows with
         `employee_attendance_detail_id` pointing at this row OR (for a fresh/rebuild call)
         attributed to this business date by the 3-day-window rule in this task's Discussion,
         `is_active AND NOT archive`, ordered `punch_at ASC, id ASC`.
      4. Debounce (assembler.md §5.2, punch_debounce_seconds=60 hardcoded — config-knobs.md
         confirms this isn't exposed anywhere) + direction assignment (§5.3 — this task set
         always writes explicit `direction`, so the "all NULL" odd/even fallback is dead code
         but keep it, matching the general rule verbatim) + pairing scan (§5.4) + derived
         fields (§5.5: punch_count, first_in_at, last_out_at, worked interval sum capped at
         max_worked_minutes_per_day=1440 hardcoded).
      5. break_minutes / worked_minutes per assembler.md §8's table (1 closed interval ->
         shift.break_minutes nominal; >=2 -> measured gaps; 0 -> 0).
      6. late_by_minutes / early_exit_minutes per assembler.md §7 (ceil-rounded, forced to 0
         when shift.is_flexible, day_type != Working, or the shift didn't resolve). No
         half-day-leave midpoint adjustment (§7.1) — no leave module.
      7. attendance_status per assembler.md §6, restricted to rows 2-5 (Holiday/WeekOff with
         or without a punch), 10-13 (Working: Present/HalfDay/short-day/missing-OUT-Present),
         14-15 collapsed to "no punch -> stays NULL" (no auto-absent, see Discussion).
         short_day_status (row 12) hardcoded 'Absent' (config-knobs.md §1.1 default,
         unexposed) and missing_punch_policy (row 13) hardcoded 'ZeroWorked' (same).
      8. payable_day_fraction per assembler.md §9 with the leave_fraction term omitted
         (always 0 — no leave module): Holiday/WeekOff -> 1.00; else worked_fraction from
         min_full_day_minutes/min_half_day_minutes (shift column, falling back to
         config-knobs.md §1.2 hardcoded defaults 510/270 when the shift has neither set),
         halved on an is_half_day week-off per resolve_day_type's flag.
      9. overtime_minutes = 0 always (Discussion).
      10. source: 'Regularized' if an approved Regularization from `attendance_request_details`
          covers this date (predicate join, assembler.md §12.2 — no
          attendance_request_detail_id FK on this table, by design), else 'Auto'.
          is_regularized mirrors the same predicate — recomputed every call so a cancelled
          regularization's next recompute reverts both to Auto/false.
      11. Upsert `ON CONFLICT (cdp, employee_master_id, attendance_date) DO UPDATE` (the SQLAlchemy
          equivalent — `session.merge`-style or explicit
          select-then-update-else-insert is fine; this table has no ORM relationship cycles
          to worry about). Set assembled_at = now(). Back-link every attributed punch's
          `employee_attendance_detail_id` (assembler.md §10.2); punches that lose attribution
          on a re-run get it reset to NULL in the same call.
      """
  ```

  This module has **no** FastAPI imports and takes a plain `Session` — callable directly from
  `app/tests/` the same way `assembler.md §10.3`'s mandatory idempotency test expects (task 37
  wires that test).

### Edited

- `backend/app/modules/shifts/service.py` — rename `_resolve_employee_shift` to
  `resolve_employee_shift` (drop the leading underscore) and keep every existing call site
  (`get_my_shift`, `list_my_shifts`) working unchanged; this is the only edit to this file. Do not
  change its resolution behaviour — `calendar_resolver_service.py` above becomes its second
  caller, exactly as `docs/leave-and-attendance/attendance/employee-self-service.md` already notes
  this is "the same unresolved two-tables gap" (`../shifts/gaps.md#44`) between self-service shift
  display and the attendance assembler's own resolution — this task deliberately **unifies** them
  onto one function rather than letting `calendar_resolver_service.py` fork a second copy, closing
  that gap for good instead of reproducing it under a new name.

## Acceptance criteria

- [x] `resolve_employee_shift` is a public, importable function in `app.modules.shifts.service`
      with identical behavior to the old private one (existing `test_shifts.py` suite still
      passes unmodified — 63/63). Docstring updated to note it's now the shared canonical
      resolver, not a self-service-only helper.
- [x] `calendar_resolver_service.resolve_effective_shift` returns the same shift
      `resolve_employee_shift` reports for a given employee/date (assignment-over-standing
      precedence) — confirmed by `test_resolve_effective_shift_matches_shift_service_precedence`,
      which calls both directly and compares shift id + source for both the "assignment" and
      "standing" cases (comparing against the renamed function directly rather than through the
      full `get_my_shift`/principal path, which needs a logged-in user this unit test doesn't set
      up — same underlying guarantee).
- [x] `resolve_day_type` correctly resolves Holiday (Public only) > WeekOff (including the Nth-
      Saturday-of-month rule and the half-day-week-off threshold-halving case) > Working — one
      test per branch, all passing.
- [x] `recompute_attendance_day` run twice over an unchanged punch set produces byte-identical
      rows except `assembled_at`/`updated_at`, and `punch_count` does not double —
      `test_recompute_is_idempotent`.
- [x] A 22:00→06:00 night-shift fixture (clock in 22:0x, clock out next-day 06:0x) attributes both
      punches to the **start** date's row, `worked_minutes=478` (7h58m) —
      `test_recompute_night_shift_attributes_to_start_date`.
- [x] A day with no shift resolved still produces a row with `day_type='Working'` (Sat/Sun
      fallback applied only when the weekday matches), `late_by_minutes=early_exit_minutes=0`,
      thresholds from the hardcoded 510/270 defaults — `test_recompute_no_shift_uses_hardcoded_
      defaults`.
- [x] No `app/jobs/` directory, no scheduled-task code, and no leave-module import introduced —
      confirmed via `git diff` touching only `app/services/calendar_resolver_service.py`,
      `app/services/attendance_recompute_service.py`, `app/modules/shifts/service.py` (rename +
      docstring only), and the new test file.
- [x] Bonus (not in the original list, added because it's a real code path): `is_locked` rows are
      skipped entirely and returned untouched — `test_recompute_skips_locked_row`.
- [x] Full backend suite: 295 passed, 2 failed — the same 2 pre-existing, unrelated
      `test_engagement_email.py` failures noted in task 29's completion record.

Completed: 2026-08-17
