---
task: 86
title: Attendance — no-shift employees get marked Present the instant they clock in
status: done
depends_on: []
---

# 86 — Attendance — no-shift employees get marked Present the instant they clock in

## Scope

Bug found in `backend/app/services/attendance_recompute_service.py`. Both places that compute
whether the attendance day is "closed" use:

```python
day_closed = shift_end_at is None or now >= shift_end_at
```

(`recompute_attendance_day` line 401, `preview_attendance_day_with_extra_punches` line 562 —
identical logic duplicated in both).

`shift_end_at` is `None` whenever `resolve_effective_shift` returns `None` — i.e. the employee
has **no shift assigned at all** (no per-date `employee_shift_assignments` row and no standing
`employee_shift_details` row). In that case `day_closed` evaluates to `True` unconditionally,
even one second after the employee's very first clock-in.

`_attendance_status` (same file, ~line 261) then hits the "day closed, worked_minutes == 0,
first_in_at is set" branch and returns:

```python
return "Present", "Missing OUT punch — regularization required"
```

So a no-shift employee who clocks in gets an attendance row written as `attendance_status =
"Present"` immediately — before they've worked a single minute, before they've clocked out, and
regardless of the actual time of day. This is exactly the reported symptom: "without any shift
assigned to the employee they are clocking in and it get stored as a present."

The doc spec (`docs/leave-and-attendance/attendance/assembler.md §3.3 "No shift assignment at
all"`) already describes the no-shift case explicitly and says the day should carry `remarks =
'No shift assignment'` as a **data-quality signal for HR**, not be silently routed through the
missing-OUT-punch branch. The spec's own "day closed" reference point for a no-shift day, used
elsewhere for the (currently unimplemented, per task 30) auto-absent job, is the **calendar-day
boundary**: `now() >= (D + 1 day at 00:00 local)` (assembler.md line ~472) — not "immediately, the
moment there's no shift to compare against."

**Root cause**: `shift_end_at is None` is being used as a proxy for "the day already ended," but
it actually means "there is no shift-based end-of-day reference at all." Those are not the same
thing, and conflating them makes every no-shift clock-in look like a missed punch.

**Not in scope**: building the real auto-absent batch job (task 30 already scoped that out —
no job runner exists in this codebase). This task only fixes the false "Present"/day-closed
determination for the synchronous clock-in/clock-out/regularization path.

## Files

### Edited

- `backend/app/services/attendance_recompute_service.py`
  - Add a small shared helper, e.g.:
    ```python
    def _day_closed(shift_end_at: datetime | None, target_date: date, tz: str, now: datetime) -> bool:
        """assembler.md §5.6 / §3.3: with a resolved shift, closed once now() is past
        shift_end_at. With no shift resolved, there is no shift-based reference — fall back
        to the calendar-day boundary (assembler.md's own no-shift auto-absent reference
        point), so a lone IN punch stays in the live "on the clock" state for the rest of
        that calendar day instead of being closed on arrival.
        """
        if shift_end_at is not None:
            return now >= shift_end_at
        next_midnight = datetime.combine(
            target_date + timedelta(days=1), time(0, 0), tzinfo=ZoneInfo(tz),
        ).astimezone(timezone.utc)
        return now >= next_midnight
    ```
  - Replace both duplicated `day_closed = shift_end_at is None or now >= shift_end_at` lines
    (`recompute_attendance_day`, `preview_attendance_day_with_extra_punches`) with calls to this
    helper, passing the already-resolved `tz` (from `resolve_timezone`) and `target_date`.
  - In `_attendance_status`, when the day closes with `worked_minutes == 0` and `first_in_at` set
    **and no shift was resolved**, set `remarks = "No shift assignment"` instead of `"Missing OUT
    punch — regularization required"`, matching assembler.md §3.3 verbatim. This needs the
    "was a shift resolved" fact threaded into `_attendance_status` (it already receives `shift:
    ShiftMaster | None`, so branch on `shift is None` there — no new parameter needed).

### Tests

- `backend/app/tests/modules/test_attendance_recompute.py`
  - New test: a no-shift employee (no `employee_shift_details`, no assignment) clocks in with a
    single IN punch on a Working day, same-day recompute → `attendance_status` is `None` (still
    "on the clock"), not `Present`. This is the regression test for the bug — the existing
    `test_recompute_no_shift_uses_hardcoded_defaults` only exercises a *closed* IN+OUT pair and
    never reaches the buggy branch, so it didn't catch this.
  - New test: same no-shift employee, single IN punch, recompute called with `target_date` set to
    a day before "today" (i.e. the calendar day has actually elapsed) → `attendance_status ==
    "Present"`, `remarks == "No shift assignment"`, `payable_day_fraction == Decimal("0.00")`.
  - Keep `test_recompute_no_shift_uses_hardcoded_defaults` passing unmodified (it doesn't touch
    the changed branch).

## Acceptance criteria

- [x] `_day_closed` (or equivalent) helper added and both call sites in
      `attendance_recompute_service.py` use it — no duplicated inline logic remains.
- [x] A no-shift employee with only an open IN punch does **not** get `attendance_status =
      "Present"` on the same calendar day — status stays `None` ("on the clock").
- [x] Once that calendar day has elapsed, the same open-IN-punch row resolves to
      `attendance_status = "Present"`, `remarks = "No shift assignment"`,
      `payable_day_fraction = Decimal("0.00")` (per assembler.md §3.3 — not the
      "Missing OUT punch" remark, since there was never a shift to miss punching out against).
- [x] An employee **with** a resolved shift is unaffected — behavior for the existing
      `shift_end_at is not None` path is unchanged (existing tests covering that, e.g.
      `test_recompute_...missing_out...` variants if present, still pass).
- [x] Full backend suite passes (`uv run pytest`), no new failures beyond any pre-existing
      unrelated ones already noted in prior task completion records.
      677 passed, 7 failed — all 7 failures (`test_attendance_dashboard.py::
      test_analytics_yesterday_never_punched_counts_absent`, `::
      test_export_writes_audit_log_with_actor_and_row_count`, `test_engagement_email.py::
      test_send_email_ok`, `::test_send_email_resolves_template_variables`,
      `test_geography.py::test_country_locale_returns_currency_and_timezones`, `::
      test_country_locale_defaults_when_unset`, `test_seed_geography.py::
      test_rails_import_inserts_full_hierarchy`) reproduce identically with this task's changes
      stashed out, confirming they are pre-existing and unrelated (the engagement_email pair was
      already noted in tasks 12/13/21/29's completion records; the dashboard/geography ones are
      newly-observed pre-existing failures, confirmed via a stash-and-rerun of just those 7 tests).

Completed: 2026-08-24
