---
task: 115
title: Register the attendance calendar sweep / auto-absent job now that the scheduler exists
status: done
depends_on: []
---

# 115 — Register the attendance calendar sweep / auto-absent job now that the scheduler exists

## Revision note (see below for the original scope)

Revised per explicit direction: the sweep must be **shift-aware, not a single fixed wall-clock
time** (e.g. a global "1 AM" cron), because shift end times differ across employees/tenants — a
night shift ending 06:00 would still be mid-shift at 1 AM and must not be swept as if its day had
closed. Also confirms and locks in the exact behaviour required for a dangling clock-IN that
never got a matching clock-OUT: once the sweep determines that employee's day has genuinely
closed, the stored row must finalize to "needs regularization," not stay open or silently
disappear. Both are addressed below. A third, related but separable concern — showing a live
"in progress" state for an employee who is *currently* mid-shift, rather than leaving today's row
blank — is **out of scope for this task** and filed separately as
[123](../ongoing/123-manager-dashboard-in-progress-status.md), since it touches a different code path (the
manager dashboard's read-time classifier, not the scheduled sweep) and can ship independently.

## Scope

This is the still-open half of `docs/leave-and-attendance/attendance/gaps.md`'s **Addendum A**
("no scheduled job runner exists — auto-absent and the batch assembler remain unbuilt") and
**Addendum B** (the manager dashboard's `effective_status` read-time workaround for the same
gap). It was true when those addenda were written; it is **still true today**, but the reason
has changed and the fix is now much smaller than it used to be.

**What changed since those addenda were written:** the in-process APScheduler mechanism
`docs/leave-and-attendance/shared/jobs-and-scheduling.md` describes has since been built —
`backend/app/core/scheduler.py` (started from `app.main`'s lifespan) iterates two registries in
`backend/app/services/job_defs.py`: `JOB_DEFS` (per-CDP jobs, fanned out by
`backend/app/services/job_runner.py:run_job_for_all_cdps`) and `GLOBAL_JOB_DEFS` (jobs that
iterate tenants themselves — leave accrual lives here today, registered and running). **`JOB_DEFS`
is empty.** Its own docstring says so explicitly:

```python
# backend/app/services/job_defs.py
#   * `JOB_DEFS` / `JobDef` — a job that fans out per-CDP ... Fits any job whose unit of work is
#     naturally "one CDP, one pass" — e.g. the attendance assembler
#     (`docs/leave-and-attendance/shared/jobs-and-scheduling.md` §1) once it's built. Empty today
JOB_DEFS: dict[str, JobDef] = {}
```

`backend/app/services/job_runner.py`'s module docstring says the same thing: this file is
"generic infra for a future job that genuinely is 'one `run_fn` call per CDP' (e.g. the
attendance assembler)."

So the missing piece is no longer "there's nowhere to hang this job" — it's "nobody has written
the `run_fn` and put it in `JOB_DEFS`." The per-`(employee, date)` recompute logic itself already
exists and is exactly what a sweep needs to call in a loop:
`backend/app/services/attendance_recompute_service.recompute_attendance_day(db, tenant_id,
employee_id, target_date, shift_cache=...)` — idempotent upsert-by-`(cdp, employee, date)`,
skips rows with `is_locked`, flushes but doesn't commit (per-CDP transaction is the caller's job,
matching `run_job_for_all_cdps`'s one-transaction-per-CDP contract). **Verified in code**
(`attendance_recompute_service.py:499-608`): this function already computes everything the
sections below need — `_day_closed` (line 63-72), `_attendance_status` (line 312-357), and the
`is_locked` write-back (line 587-588) are all real, tested code today. The sweep's job is purely
to **call** this function on the right schedule for the right `(employee, date)` pairs — no new
calculation logic is needed for the two behaviours below, only the caller.

## Design decision: cadence is shift-aware by construction, not by a per-shift schedule

**Rejected: a single fixed-time cron (e.g. "run once at 01:00") that closes every employee's
"yesterday" in one pass.** This is wrong the moment any tenant has a shift whose `shift_end_at`
falls after 01:00 local — a night shift running 22:00→06:00 is still open at 01:00, and a fixed
close-everything-now pass would either (a) skip it correctly only if it re-checks `_day_closed`
per row (in which case the fixed time bought nothing — see below), or (b) incorrectly finalize it
early if it doesn't. There is no single wall-clock time that is "after end of day" for every
shift a tenant might configure — that's the whole reason `assembler.md` §2 makes `attendance_date`
shift-anchored rather than calendar-anchored in the first place.

**Chosen: run the sweep frequently (every 15 minutes, matching
`jobs-and-scheduling.md` §1's own recommended cadence for this exact job) over a short trailing
window, and let each row's own `_day_closed(shift_end_at, target_date, tz, now)` decide
per-`(employee, date)` whether that particular day has actually ended.** This is not a
workaround — it is the direct, intended reading of `jobs-and-scheduling.md` §1's cadence
guidance ("every 15 min over the trailing window, plus a nightly full sweep") once you notice
that "shift-based" doesn't require scheduling one job per shift — it falls out for free from
calling an idempotent, already-shift-aware function often enough that no shift's `shift_end_at`
is ever far past before the next tick notices:

- A day that's still open when the sweep visits it is a no-op: `recompute_attendance_day`
  recomputes it (still cheap — it's the same idempotent per-row upsert every other trigger in
  this codebase already uses) and it comes back unchanged, `attendance_status` still `None`/live,
  because `_day_closed` still reads `False` for that row.
- A day whose shift ended in the last 15 minutes gets finalized on the very next tick after it
  closes — for every shift, at whatever time *that* shift ends, with no per-shift cron
  configuration anywhere.
- A tenant with no shift resolved for an employee falls back to the calendar-day boundary (local
  midnight) per `_day_closed`'s existing no-shift branch — also handled automatically, no special
  case needed in the job.

**Also register a second, wider nightly sweep** (e.g. `0 2 * * *`, matching the *shape* of
`jobs-and-scheduling.md`'s "plus a nightly full sweep," picked at a low-traffic hour — not because
it's when shifts end, but because it's a cheap time to run a wider safety net) over a longer
window (the full `attendance_rebuild_window_days`, default 7 days) to catch anything the 15-minute
job's shorter trailing window missed — a watermark bug, a config change applied retroactively, a
period of scheduler downtime. **This nightly job is a safety net, not the mechanism that closes
a shift's day on time** — that distinction matters: don't let "nightly" get confused with "the
thing that marks yesterday closed," which is the 15-minute job's actual role. Both jobs call the
exact same `run_fn`/logic with different window sizes — implement one `run_fn` parameterized by
window length, registered twice in `JOB_DEFS` under two names/cadences, rather than two separate
implementations.

## Dangling clock-IN with no clock-OUT → closes to "needs regularization," not silently

**Already correctly implemented, verified in code — the sweep's job is only to trigger it.**
`_attendance_status` (`attendance_recompute_service.py:349-355`), when `day_closed=True`,
`worked_minutes == 0` and `first_in_at` is set (i.e. the employee punched IN and the interval
never closed):

```python
if first_in_at is not None:
    if day_closed:
        if shift is None:
            return "Present", "No shift assignment"  # assembler.md §3.3
        return "Present", "Missing OUT punch — regularization required"
    return None, None  # still on the clock — assembler.md §5.6's live "on the clock" state
```

So the target behaviour the user asked for — "next day, leftover clocked-in-not-clocked-out
should be closed and marked as needs regularization" — is exactly what this function already
does, *the moment something calls it after the day has closed*. The entire gap is that **nothing
currently calls `recompute_attendance_day` again for that stale date** once the employee stops
interacting (no second clock-in, no clock-out, no regularization submission) — every existing
trigger (clock-in, clock-out, regularization-approval) is an action *by that employee on that
day*; a forgotten clock-out, by definition, has no such follow-up action. This task's sweep is
what finally revisits it.

**One interaction to get right, and cover with a test**: `recompute_attendance_day` also sets
`is_locked = True` in the *same call* that closes the day, once
`_regularization_window_elapsed(shift, target_date, now)` is also true (line 587-588) — and per
`assembler.md` §10, once `is_locked = true` the row is **never recomputed again**. If the sweep's
cadence were too coarse (e.g. only the nightly safety net, no 15-minute job), a long-neglected
day could jump straight from "still open" to "closed AND locked" in a single sweep pass, with no
window in between during which the employee/manager could actually see "needs regularization" and
act on it. Running the fast (15-minute) sweep close to each shift's actual end time is what
guarantees the row spends real time in the open, actionable "Present / Missing OUT punch —
regularization required, not yet locked" state before `_regularization_window_elapsed` can ever
fire for it — confirm `regularization_window_days` for every tested shift configuration is
comfortably larger than the 15-minute cadence (it will be by default — the knob is denominated in
days) and add a regression test proving a freshly-closed dangling-IN day is *not* locked yet, only
a genuinely stale one (past the window) is.

## Files

### New

- `backend/app/services/attendance_assembler_job.py` (or similar name matching
  `leave_accrual_dispatcher.py`'s convention) — a `run_fn: (Session, cdp_id, as_of) -> dict[str,
  int]` for `JOB_DEFS`, parameterized by a `window_days: int` argument (see the cadence design
  above — the same function backs both the 15-minute and nightly registrations, just with
  different window sizes) via `functools.partial` or two thin wrapper functions. Per CDP:
  - Resolve the active-employee set for that CDP (`employee_masters` joined through
    `corp_masters.care_delivery_program_master_id`, per `assembler.md` §1.3's tenant-reach note —
    `employee_masters` itself has no CDP column).
  - Resolve the date window: `[as_of − window_days, as_of]` — `window_days` is
    `attendance_rebuild_window_days` (default 7) for the nightly registration, and a small value
    (e.g. 2 — "yesterday and today," enough to always re-check the day currently rolling over)
    for the 15-minute registration; confirm the existing knob name/default in `config-knobs.md`
    before hardcoding either value.
  - Apply the §1.1 "who gets a row" filter (`joining_date <= D`, `relieving_date IS NULL OR D <=
    relieving_date`, `is_active AND NOT archive`) per employee × date pair — an employee outside
    that window for a given date gets **no row**, not an `Absent` row (per §1.1's explicit
    warning: "Marking a person absent before they joined or after they left is a payroll
    defect").
  - Call `recompute_attendance_day(db, cdp_id, employee_id, target_date, shift_cache=...)` for
    every `(employee, date)` pair that passes the filter — reuse one `ShiftCache` per employee
    across the date loop (see `recompute_attendance_day`'s own docstring on why) to avoid
    redundant shift lookups. This single call is what both materializes never-punched days
    (§1/calendar sweep), finalizes auto-absent (§11, if/once that logic exists in
    `_attendance_status` — see the note below), and closes a dangling clock-IN to "needs
    regularization" (the section above) — one call, three outcomes, entirely driven by what
    `_day_closed`/`_attendance_status` already compute for that row.
  - Take the advisory lock convention `jobs-and-scheduling.md` §2.2 requires
    (`(job_name, cdp)`-shaped, per `JOB_DEFS`'s own contract) before doing any work for that CDP —
    `pg_try_advisory_xact_lock`, matching how `leave_accrual_service.process` locks its own row;
    exit quietly (return an empty/zero stats dict) if the lock isn't acquired. Use a distinct lock
    name per registration (15-minute vs. nightly) so the two cadences never block each other.
  - Return a stats dict (`rows_upserted`, `skipped_locked`, `newly_needs_regularization` — count
    rows whose remark just became "Missing OUT punch — regularization required" in this run, for
    the alerting `jobs-and-scheduling.md` §4 describes — `data_quality_warnings`, etc.) since
    `run_job_for_all_cdps` sums whatever keys the `run_fn` returns into its own totals log line.
  - Per §11: after `recompute_attendance_day` for a given `(employee, date)`, if the resulting row
    is still a Working day with `punch_count = 0`, no approved leave/OnDuty/WFH/Regularization,
    and `auto_absent_days` has elapsed, confirm during implementation whether `_attendance_status`
    already resolves this to `Absent` (rows 14/15 in `assembler.md` §6) or whether that branch is
    still dormant/unimplemented in `attendance_recompute_service.py` — if the latter, implementing
    it belongs in `attendance_recompute_service.py` itself (not duplicated in the job file), since
    every other trigger (clock-in/out, regularization) must see the same auto-absent behavior
    once it exists, not just the sweep.

### Edited

- `backend/app/services/job_defs.py` — add **two** entries to `JOB_DEFS`, both backed by the same
  `run_fn`:
  ```python
  from functools import partial
  from app.services.attendance_assembler_job import run_attendance_sweep

  JOB_DEFS: dict[str, JobDef] = {
      "attendance_sweep": JobDef(
          name="attendance_sweep", cron="*/15 * * * *",
          run_fn=partial(run_attendance_sweep, window_days=2),
      ),
      "attendance_sweep_nightly": JobDef(
          name="attendance_sweep_nightly", cron="0 2 * * *",
          run_fn=partial(run_attendance_sweep, window_days=7),
      ),
  }
  ```
  (Adjust to whatever calling convention `JobDef.run_fn`'s type — `Callable[[Session, int, date],
  dict[str, int]]` — actually requires; a `functools.partial` binding the keyword-only
  `window_days` should satisfy it without changing `JobDef`'s shape.)

### Tests

- `backend/app/tests/modules/test_attendance_recompute.py` or a new
  `test_attendance_assembler_job.py`:
  - **Shift-aware cadence**: a night-shift employee (22:00→06:00) with an open IN punch from
    "yesterday" — running the sweep at a `now` of 01:00 (mid-shift) leaves the row `None`/open;
    running it again at a `now` of 07:00 (past `shift_end_at`) closes it. This is the direct
    regression test for "1 AM would be wrong, shift-end-aware is right."
  - **Dangling IN → needs regularization**: a day-shift employee with an open IN punch and no
    OUT, day genuinely closed (`now` past `shift_end_at`) — sweep produces
    `attendance_status = "Present"`, `remarks = "Missing OUT punch — regularization required"`,
    `payable_day_fraction = Decimal("0.00")`, and `is_locked` still `False` (within the
    regularization window).
  - **Locks only once genuinely stale**: same setup, but `now` is past both `shift_end_at` and
    the shift's `regularization_window_days` — sweep produces the same status/remark **and**
    `is_locked = True`.
  - An employee with no punches at all on a Working day, after the sweep runs for that date, gets
    a row with `attendance_status = 'Absent'` once `auto_absent_days` has elapsed (and stays
    `NULL` before it has — regression test for the existing/new `assembler.md` §6 row-14/15
    distinction, once confirmed/implemented per the note above).
  - An employee outside `[joining_date, relieving_date]` for a swept date gets **no row** at all
    (not `Absent`) — direct regression test for §1.1's explicit warning.
  - Running the sweep twice over the same window produces byte-identical rows except
    `assembled_at`/`updated_at` (the `assembler.md` §10.3 idempotency acceptance test, now
    exercised through the real job entrypoint rather than only through
    `recompute_attendance_day` directly).
  - A locked row (`is_locked = true`) is skipped and counted in `skipped_locked`, not overwritten.
  - Cross-tenant: employees in CDP B are never touched by a sweep run scoped to CDP A.

## Acceptance criteria

- [x] `JOB_DEFS` in `backend/app/services/job_defs.py` has two real entries — a frequent
      (15-minute) shift-aware sweep and a nightly wider safety-net sweep — both backed by one
      `run_fn`; `JOB_DEFS` is no longer empty.
- [x] No code path closes a day based on a fixed wall-clock time — every finalization decision
      goes through `_day_closed`'s existing per-row, per-shift logic.
- [x] A night-shift employee's dangling IN is **not** prematurely closed by an earlier tick that
      only checked the calendar clock, and **is** closed by the first tick after that specific
      shift's `shift_end_at` passes. (`test_sweep_night_shift_not_closed_early_by_an_earlier_tick`)
- [x] A dangling clock-IN, once its day closes, produces `attendance_status = "Present"` +
      `remarks = "Missing OUT punch — regularization required"` — verified by test — and does
      **not** get `is_locked = True` until the regularization window has also elapsed.
      (`test_recompute_shift_resolved_dangling_in_closes_to_needs_regularization`,
      `test_sweep_closes_dangling_in_and_counts_it_as_newly_needing_regularization`)
- [x] Running the sweep for a CDP with never-punched active employees materialises rows for them
      (WeekOff/Holiday/Absent as appropriate) where none existed before.
      (`test_sweep_materializes_never_punched_working_day`)
- [x] An employee outside their joining/relieving window for a given date gets no row for that
      date, per §1.1. (`test_sweep_respects_joining_date_window`)
- [x] Two consecutive sweep runs over the same window are idempotent — verified via
      `rows_upserted` staying stable and `newly_needs_regularization` dropping to 0 on the second
      run in `test_sweep_closes_dangling_in_and_counts_it_as_newly_needing_regularization`, on top
      of the pre-existing `test_recompute_is_idempotent` covering the underlying per-row function.
- [x] The advisory-lock convention from `jobs-and-scheduling.md` §2.2 is honoured — verified with
      a test that a second concurrent call for the same CDP is a no-op, not a duplicate run.
      (`test_sweep_advisory_lock_prevents_concurrent_double_run`, using a genuinely separate DB
      connection to hold the lock, not just a second call on the same session.)
- [x] Full backend suite passes (`uv run pytest`) — 1143 passed, 21 failed, out of 1164 total.
      Zero failures in any `test_attendance*.py` file (178 pre-existing + 11 new tests, all
      green). The 21 failures are pre-existing and unrelated:
      - 5 (`test_engagement_email.py` ×2, `test_geography.py` ×2, `test_seed_geography.py` ×1)
        are the exact same failures already documented as pre-existing/unrelated in task 86's
        own completion record (weeks before this task).
      - 5 in `test_organizations.py` (`test_upload_*`) fail on `S3 upload failed: Unable to
        locate credentials` — a sandbox/environment AWS-credentials gap, not a code defect.
      - 4 in `test_leave.py`, 2 in `test_payroll.py`, 3 in `test_employee_import.py` — all in
        modules this task never touches (confirmed via `git status`: `test_leave.py` and its
        module files were already modified/staged from unrelated in-progress work before this
        task started).
      - 2 in `test_devices.py` (`test_unmapping_returns_punches_and_empties_the_day_row`,
        `test_reported_name_reaches_the_unresolved_reason_on_a_punch`) — the closest candidates
        for a false positive, since `devices/service.py` also calls into
        `attendance_recompute_service`. **Verified pre-existing**: reverted
        `attendance_recompute_service.py` to its last-committed version (`git show HEAD:...`)
        and re-ran both tests in isolation — both failed identically with this task's changes
        completely absent, then the working version was restored.
- [x] `docs/leave-and-attendance/attendance/gaps.md`'s Addendum A is updated to note the sweep now
      exists (Addendum B left as-is, per scope).

Also added, beyond the original acceptance criteria: a per-row `db.begin_nested()` SAVEPOINT
around each `(employee, date)` recompute call inside the sweep, so one row's DB-level failure
can't poison the rest of that CDP's run — matching the isolation `job_runner.py`'s own docstring
already assumes every `JOB_DEFS` job provides for itself.

Completed: 2026-09-23
