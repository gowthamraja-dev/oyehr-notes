---
task: 68
title: Attendance dashboard — read-time effective-status & worked-hours classifier
status: done
depends_on: []
---

# 68 — Attendance dashboard — read-time effective-status & worked-hours classifier

## Scope

A pure, reusable service-layer function that every manager-dashboard endpoint (69-72) calls to
turn one `EmployeeAttendanceDetail` row into the display state the Manager Portal Attendance
Dashboard prompt (`.design/prompts/Manager Portal — Attendance Dashboard Full-Stack Development
Prompt.md`) needs: `effective_status`, `is_late`, `late_by_minutes`, and a worked-hours display
value that is `"Incomplete"` rather than a real duration when clock-out is missing.

**This does NOT touch the stored `attendance_status` column, and does NOT build the auto-absent
batch job.** Both are explicitly out of scope — see the decision below.

### Why this needs its own task

`docs/leave-and-attendance/attendance/vocabularies.md` §1 states, unqualified: **"`NULL` must
never render as `Absent`"** — because the auto-absent transition (`assembler.md` §11) needs a
calendar-sweep job that doesn't exist (`docs/leave-and-attendance/attendance/gaps.md`, Addendum
A) and never got built (tasks 29-33 only built the synchronous per-`(employee,date)` recompute in
`app/services/attendance_recompute_service.py`, triggered by clock-in/out and regularization
approval — nothing sweeps a date whose employee never punched).

The design prompt nonetheless requires a real, non-zero **Absent** KPI and status for the
register (§4, §5, §6). Reconciling these without silently contradicting the documented rule:

**Decision** (record this in the docs-update task, 81, as a new vocabularies.md addendum):
introduce a *new*, separately-named field — `effective_status` — computed **at read time, only
by the manager-dashboard endpoints** (69-72), never written back to
`employee_attendance_details.attendance_status`, never used by `/me/*` or the existing
`/employees/{id}/today`/`/daily` (task 54) responses, which keep rendering stored `NULL` as
"Yet to check in" exactly as vocabularies.md §1.2 specifies today. `effective_status` is allowed
to resolve `NULL` to `Absent` — but **only for `attendance_date < today`**, where the day has
fully elapsed and there is no more ambiguity about whether the employee might still check in.
For `attendance_date == today`, `NULL` still means "yet to check in", exactly as today, never
`Absent` — do not invent a "shift end has passed" heuristic; that is precisely the auto-absent
job's job and stays deferred.

### `effective_status` precedence (design prompt §5)

Given one `EmployeeAttendanceDetail` row (nullable `shift_master_id`/shift resolved via
`resolve_effective_shift` from `app/services/calendar_resolver_service.py`, same as the recompute
service already uses) plus whether `attendance_date < today` (caller passes today's date once,
computed from the org/location timezone the same way the recompute service does — do not use the
server's naive local date):

1. `attendance_status == "OnLeave"` → `EffectiveStatus.ON_LEAVE`
2. `day_type in ("WeekOff", "Holiday")` → `EffectiveStatus.WEEK_OFF` / `EffectiveStatus.HOLIDAY`
   (keep them distinct — the design prompt's KPI/table only ever call this bucket "neutral", but
   the exceptions section and CSV export need the real value)
3. `attendance_status in ("Present", "HalfDay", "OnDuty", "WFH")` → `EffectiveStatus.PRESENT`
   (worked-hours display still applies — see below; a `Present` row can still be `Late`)
4. `attendance_status == "Absent"` → `EffectiveStatus.ABSENT` (an already-materialized Absent —
   the "short day" case `attendance_recompute_service.SHORT_DAY_STATUS` can produce)
5. `attendance_status is None and day_type == "Working"`:
   - `attendance_date < today` → `EffectiveStatus.ABSENT` (the read-time-only resolution above)
   - `attendance_date == today` → `EffectiveStatus.YET_TO_CHECK_IN`
6. Anything else (defensive default) → `EffectiveStatus.YET_TO_CHECK_IN`

`is_late` / `late_by_minutes`: unchanged from vocabularies.md §1.1 — `day_type == "Working" and
late_by_minutes > 0`, read straight off the stored column. It is a badge alongside
`EffectiveStatus.PRESENT`, never its own bucket (`Late` is a filter predicate, not a status —
tasks 69-71 must implement the `status=late` filter as `WHERE late_by_minutes > 0 AND
day_type='Working'`, not an equality).

### Worked-hours display (design prompt §17)

Separate concern from the status precedence above — a row can be `EffectiveStatus.PRESENT` and
still need `"Incomplete"` instead of a duration:

- `first_in_at is not None and last_out_at is None` → display value `"Incomplete"` (do not render
  `worked_minutes`, which the recompute service may have left at a stale/zero value for this
  case — `attendance_recompute_service.py`'s missing-OUT branch already writes `attendance_status
  = "Present"` with a remark, precisely so this dashboard layer can catch it via the null
  `last_out_at`, not by parsing the remark string)
- `first_in_at is not None and last_out_at is not None` → format `worked_minutes` as today
  (`Nh MMm`)
- both `None` → `"—"`

## Files

- `backend/app/modules/attendance/service.py` (or a new `backend/app/modules/attendance/
  dashboard_service.py` if `service.py`'s 1486 lines make a new file cleaner — pick whichever
  keeps `service.py` from growing past what the module's existing single-file convention can
  bear; either way this is **new code**, not a change to `attendance_recompute_service.py`)
- `backend/app/modules/attendance/schemas.py` — an `EffectiveStatus` literal/enum type shared by
  tasks 69-72's response schemas

## Acceptance criteria

- [x] A pure function, e.g. `compute_effective_status(row: EmployeeAttendanceDetail, today: date)
      -> EffectiveStatus`, with no DB writes and no dependency on request/response objects — easy
      to unit-test directly against constructed `EmployeeAttendanceDetail` instances (in-memory,
      not committed to the session).
- [x] A sibling `format_worked_hours(row) -> str` implementing the Incomplete/duration/— rule
      above.
- [x] Unit tests (new, in `app/tests/modules/test_attendance.py` or a new
      `test_attendance_dashboard.py`) covering every precedence branch above, including: a
      `NULL`-status Working row for **yesterday** → `Absent`; the identical row for **today** →
      `YetToCheckIn`; a `WeekOff` day with `worked_minutes > 0` (holiday/weekoff worked case,
      already `Present` per the recompute service — confirm this classifier doesn't re-derive it
      wrong); a `Present` row with `last_out_at IS NULL` → worked-hours display `"Incomplete"`.
- [x] No existing `/me/*` or `/employees/{id}/today`/`/daily` test's expected output changes —
      this task adds a new code path, it does not touch the existing one.
