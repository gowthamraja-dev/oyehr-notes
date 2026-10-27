---
task: 255
title: Day-override recalculation service — recompute attendance, audit, payroll guard, impact counters
status: done
depends_on: [253, 254]
---

# 255 — Recalculation service

Plan: `.plans/shift-day-swap-plan.md` §3 "Recalc service". Repo: `workspace-1/hrms/backend/`.

## Scope
One service module, no HTTP and no scheduling (256 wires the hybrid runner, 257 the API).
New file `app/services/shift_day_override_service.py` (stdlib `logging.getLogger(__name__)`, `%s` placeholders).

1. `recalculate_override(db, cdp_id, override, *, actor_user_id) -> dict` — the single function both the inline and the
   queued path call.
   - Rows to touch: `employee_attendance_details` for `care_delivery_program_master_id = cdp_id` and
     `attendance_date = override.override_date`; when `override.shift_master_id` is set, also `shift_master_id = that`.
     Employees with no row are skipped (gap days resolve live). Chunk by employee so memory stays flat.
   - For each row: remember `(day_type, attendance_status, worked_minutes, overtime_minutes, is_locked)`, then
     `recompute_attendance_day(db, cdp_id, employee_id, date, shift_cache, force=row.is_locked)` inside
     `db.begin_nested()` (a SAVEPOINT per row, as `attendance_assembler_job` does). A forced row stays locked.
   - If `day_type` or `attendance_status` changed, add `AttendanceAuditLog(action="DayTypeOverridden",
     old_value={...before..., "shift_day_override_id": id}, new_value={...after...}, performed_by_id=actor_user_id,
     performed_by_role="admin", reason=override.reason)`. Unchanged rows write no audit row (idempotent re-run).
   - Result dict (stored in `recalc_result`): `{employees, days_recomputed, days_changed, days_force_locked,
     ot_rows_created, failed: [{employee_master_id, error}]}`; cap `failed` at 50 entries.
   - Sets `recalc_status` Done (no failures) or Failed (any failure), `recalculated_at = now`. Flushes; the caller commits.
   - An archived override is recalculated the same way: the resolver already ignores it, so rows return to the rule.
2. `count_impact(db, cdp_id, override_like) -> ImpactCounts` — read-only, for the preview and the hybrid threshold:
   `employee_days` (rows that would be recomputed), `locked_rows`, `rows_with_punches` (`punch_count > 0`),
   `ot_rows_expected` (Working→WeekOff rows with punches), `absent_expected` (WeekOff→Working, no punch, day closed),
   `leave_overlaps` (approved leave day rows on the date whose stored fraction disagrees with the new day type — see the
   deviation note below; the original wording, "no day-detail row", was wrong).
3. `payroll_period_blocking(db, cdp_id, d) -> PayrollPeriod | None` — a `payroll_periods` row covering `d` that is closed.
   First read how `app/modules/payroll/service.py` decides a period is closed/paid and reuse that predicate; if none exists use
   `processed_at / approved_at / locked_at IS NOT NULL`. Record the choice in the task's completion note.
4. `resolve_rule_day_type(db, cdp_id, shift_id, d)` — what the weekly rule + holiday say with overrides ignored (the preview's
   "today it is" column). Reuse `week_off_from_rows(rows, d)` with `override=None`; never re-derive the matcher.

## Files
- `workspace-1/hrms/backend/app/services/shift_day_override_service.py` (new)
- `workspace-1/hrms/backend/app/tests/modules/test_shift_day_override_service.py` (new)
- extend `test_attendance_recompute.py`, `test_overtime.py` only if a case does not fit the new file

## Acceptance criteria
- [x] Working→WeekOff on a date with an existing `Absent` row and no punches → `WeekOff`/`WeekOff`, `payable_day_fraction` equal to a natural week-off's, one audit row (old Working/Absent, new WeekOff/WeekOff, `shift_day_override_id`, actor, role `admin`, reason)
- [x] WeekOff→Working, no punches, day closed → `Absent`; with punches (09:00–18:00) → `Present`
- [x] Working→WeekOff with punches → stays `Present`, `overtime_minutes` = 540 (the whole day), one Pending `employee_overtime_details` row (9.00 h); a Processed OT row is untouched (still 1.00 h, still Processed). WeekOff→Working deletes the unpaid OT the week-off had earned
- [x] A locked row is recomputed (forced), **stays locked**; `days_force_locked` counts it
- [x] Second run: `days_recomputed = 1`, `days_changed = 0`, still exactly one audit row
- [x] One bad employee (forced exception): that SAVEPOINT rolls back (row untouched, no audit row), the other employee still recomputes, status `Failed`, `failed[]` names the employee
- [x] Shift-specific override recalculates only that shift's rows (`employees == 1`, the other shift's `assembled_at` unchanged); organisation-wide recalculates every row of its own tenant and **none of another tenant's** (`assembled_at` unchanged, no audit rows there)
- [x] Archive then recalculate: day goes back to `Working`/`Absent`, a second (reverse) audit row, reason `Swap removed: <reason>`, status `Done`
- [x] `count_impact` equals what `recalculate_override` then reports on one fixture: `employee_days == days_recomputed (4)`, `rows_changing == days_changed (4)`, `locked_rows == days_force_locked (1)`, `ot_rows_expected == ot_rows_created (1)`; `rows_with_punches == 2`; and nothing is written by `count_impact`
- [x] Closed payroll period → `payroll_period_blocking` returns it; an open month, another tenant's locked month and a date with no period → None
- [x] `uv run pytest app/tests/modules/test_shift_day_override_service.py` → 15 passed. Mutation check: forcing `force=False` → 2 tests fail; dropping the tenant filter → 1; auditing unchanged rows → 1; ignoring `locked_at` → 1. Restored and green
- [x] Regression: attendance recompute, overtime, assembler job, shifts, resolver suites — only `test_attendance.py::test_employee_daily_pagination_matches_my_daily_shape` fails, and it fails before this change too (same baseline list as task 254)

## What was built
`app/services/shift_day_override_service.py`: `recalculate_override`, `count_impact` (+ `OverrideSpec`, `ImpactCounts`), `payroll_period_blocking`, `resolve_rule_day_type`, `AUDIT_ACTION = "DayTypeOverridden"`. stdlib logging; flushes, never commits. Chunks of 200 attendance rows; one SAVEPOINT per row.

## Decisions and deviations (read before 256/257)
- **Payroll "closed" = `payroll_periods.locked_at IS NOT NULL`.** That is payroll's own rule: an Admin's month lock, or set automatically when the last employee of the month is approved (`approved_at` and `locked_at` together); only an Admin's unlock clears it, and `run_payroll_initiation` refuses a locked month with "ask an Admin to unlock it". `processed_at` is deliberately not used: it stays set after an unlock, which would block a swap on a month payroll itself considers reopened. 257's 409 should say "unlock the payroll month first".
- **`leave_overlaps` meaning changed from the task text.** Leave stores a day row for *every* date in a request, with fraction 0.00 on an excluded week-off (`build_leave_day_rows`), so "no day-detail row" never happens. It counts approved leave day rows on the date whose fraction disagrees with the new day type: fraction > 0 on a date becoming WeekOff, or fraction 0 (not a holiday) on a date becoming Working. Only employees who have an attendance row for the date are looked at.
- **`count_impact` counters.** `employee_days` and `locked_rows` cover every row the swap recomputes (what the 256 threshold needs); `rows_with_punches`, `ot_rows_expected`, `absent_expected`, `leave_overlaps` cover only rows whose day type actually changes (new field `rows_changing`). It accepts an unsaved `OverrideSpec` and models saving it (replaces the live row for that shift + date). `absent_expected` uses the recompute service's own `_auto_absent_elapsed` with the default time zone.
- **`resolve_rule_day_type` only looks at the tenant's all-locations holiday calendar.** There is no employee to read a location/assignment calendar from. The recalculation itself resolves per employee, so a holiday on one employee's own calendar still wins for that employee. 257's preview should say "holiday (default calendar)".
- `recalculate_override` leaves `recalc_status` at `Done` / `Failed`; marking `Running` before the call is 256's job.
- Imports the private `_resolve_holiday` (resolver) and `_now` / `_auto_absent_elapsed` (recompute) — same pattern as `attendance/dashboard_service.py`. Tests pin the clock by patching `recompute_mod._now`.
- Employees with no attendance row for the date are not recomputed and not counted: they resolve live under the new rule.

Completed: 2026-10-26
