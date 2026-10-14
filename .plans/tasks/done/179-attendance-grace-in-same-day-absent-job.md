---
task: 179
title: Mark no-punch employees Absent once shift start + grace-in has passed (recompute rule + frequent cron)
status: done
depends_on: []
---

# 179 — Same-day Absent after grace-in (recompute rule + frequent cron)

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Paths below are
relative to `backend/`. Decided with the user on 2026-10-05: the rule applies **only to shifts with
`grace_in_minutes > 0`**. Shifts with grace 0 or NULL (flexible) keep today's behaviour: Yet to
check in, then Absent after the auto-absent lag.

## Why
Today a Working-day employee with no punch stays `attendance_status = NULL` ("Yet to check in") for
the whole day. They only become `Absent` when the 23:59 sweep runs **after** the day close + 1 day
lag (`_auto_absent_elapsed`, `attendance_recompute_service.py:118`). The HR Manager screen therefore
never shows a same-day absent count: `compute_effective_status`
(`app/modules/attendance/dashboard_service.py:82-109`) treats today's NULL as `yet_to_check_in`.

The requirement: once the grace-in window is over, count the employee as Absent. When they punch in
later, they move to Present and the absent count drops.

## Scope
### 1. Recompute rule
In `app/services/attendance_recompute_service.py`:
- Add `_grace_absent_elapsed(shift, day_type, shift_start_at, approved_leave, now) -> bool`. It is
  True only when **all** of these hold:
  - `day_type == "Working"` and a shift was resolved (`shift is not None`, `shift_start_at is not None`)
  - `policy_config.is_flexible` is falsy
  - `int(policy_config.get("grace_in_minutes") or 0) > 0`
  - `now >= effective_start + grace_in`, where `effective_start` is computed exactly as in
    `_late_and_early` (`:278`). With a `FirstHalf` approved leave the reference moves to the shift
    midpoint. Extract that start-reference computation into one helper that both functions call, so
    grace has a single definition.
- Pass it into `_attendance_status` (`:375`) as a new keyword arg `grace_absent_elapsed: bool = False`,
  and change the last no-punch branch to:
  ```python
  if auto_absent_elapsed or grace_absent_elapsed:
      return "Absent", (None if auto_absent_elapsed else "No check-in within grace period")
  ```
  Leave the order unchanged so full-day leave, Holiday/WeekOff, half-day leave and any punch all win
  first. In particular `if not day_closed and first_in_at is not None: return "Present"` already
  makes a late punch turn the day back to Present.
- Compute it in `recompute_attendance_day` next to `day_closed` / `auto_absent_elapsed` (`~:595`), and
  do the same in `preview_attendance_day_with_extra_punches`.
- `payable_day_fraction` for that Absent is 0, the same as auto-absent. A later punch recomputes it
  from `worked_minutes` as usual.
- This is a deliberate exception to task 156 ("the same day shows only Present; Absent settles on
  close"). It covers **only the no-punch case**. Short-day Absent and HalfDay still wait for the
  close. Say so in the `_attendance_status` docstring.
- `Import` / `Manual` rows are not touched. That is task 169's overwrite matrix, and the job below
  also filters to `source='Auto'`.

### 2. The frequent cron job
The 23:59 `attendance_sweep` is the only scheduled recompute, so on its own nothing would flip
today's NULL rows during the day. Add a second per-CDP job:
- `app/services/job_defs.py` → `JOB_DEFS["attendance_grace_absent"] = JobDef(name="attendance_grace_absent", cron="*/5 * * * *", run_fn=run_grace_absent_sweep)`.
  Update the module comment ("the only scheduled recompute") accordingly.
- `app/services/attendance_assembler_job.py` → `run_grace_absent_sweep(db, cdp_id, as_of) -> dict[str, int]`:
  - Take the same `pg_try_advisory_xact_lock` pattern (`:44-53`) with its own key
    (`attendance_grace_absent:{cdp_id}`). This keeps it single-run across ECS replicas, since the
    APScheduler runs inside every API task.
  - **Candidates only, not every employee.** These are active, non-archived employees of the CDP
    (with the same joining/relieving-date filter as `run_attendance_sweep`) whose row for `as_of`
    meets one of these conditions:
    - (a) the row doesn't exist, or exists with `attendance_status IS NULL` and `source='Auto'`
    - (b) the row exists with `attendance_status='Absent'`, `source='Auto'` and `is_locked=false`.
      This picks up biometric punches that `rebuild_attendance_days` deferred past its 3 s budget,
      so a device punch still clears the Absent within 5 minutes.
  - Call `recompute_attendance_day` for each candidate inside a SAVEPOINT, as the sweep does. The
    recompute itself decides whether grace has elapsed, so there is no duplicated rule. Commit once
    per CDP.
  - Return counts such as `{"candidates", "marked_absent", "cleared", "unchanged", "failed"}`, which
    `run_job_for_all_cdps` logs.
  - `as_of` is the scheduler-tz date. A night shift starting at 22:00 on D has `attendance_date` D, so
    the 22:05+ ticks on D catch it.
- Logging per CLAUDE.md: INFO with the counts per CDP, and `logger.exception` inside the
  per-employee `except`.

### 3. Clock-in path (verify, probably no change)
`service.clock_in` (`app/modules/attendance/service.py:866-969`) refuses only on an open session
(409), a locked row (423) or no shift (400). It does **not** refuse on a stored `Absent`, and it
recomputes synchronously at `:938`, which flips the row to Present with `late_by_minutes` set. Add a
test for this. Webhook punches (`webhooks/service.py:310`) and regularization approval
(`service.py:1802`) recompute too.

### Known trade-off (document it)
Biometric devices that push only once a day will show their employees as Absent between grace and
the push. That lag is exactly why `AUTO_ABSENT_DAYS` exists. Only shifts with grace > 0 opt in, so
note in the docs that tenants on batch-push devices should keep grace at 0 or NULL on those shifts.

### Out of scope
- The HR Manager screen count and live refresh (task 180).
- Notifications or alerts to the employee or manager when they are marked Absent.
- A tenant-level default grace (only per-shift `policy_config.grace_in_minutes` exists).

## Files
- `app/services/attendance_recompute_service.py`: `_grace_absent_elapsed`, the shared
  effective-start helper, and the `_attendance_status` arg/branch plus docstring.
- `app/services/attendance_assembler_job.py`: `run_grace_absent_sweep`.
- `app/services/job_defs.py`: the new JobDef and comment.
- `docs/leave-and-attendance/attendance/assembler.md`: a new §11.1 "Same-day absent after grace-in",
  plus a row in the §6 table. Also update `config-knobs.md` (`grace_in_minutes` now affects status, not
  only late) and `vocabularies.md` §1 ("Yet to check in" now ends at grace).
- Tests: `app/tests/modules/test_attendance_recompute.py` and `test_attendance_assembler_job.py`
  (freeze `_now()` the way the existing tests do), plus one in `test_scheduler.py` asserting the job
  is registered with `*/5 * * * *`.

## Acceptance criteria
- [x] Shift 09:00–18:00, grace 10, no punch, `now=09:09` → recompute leaves status NULL. At `now=09:11`
      it becomes `Absent` with remark "No check-in within grace period" and payable 0.
- [x] The same employee clocks in at 09:40 through `/attendance/me/clock-in` → 200, the row is `Present`,
      `late_by_minutes=30`, and the remark is cleared.
- [x] Shift with grace 0 or NULL, or `is_flexible`, no punch at 12:00 → status stays NULL (unchanged).
- [x] WeekOff, Holiday, an approved full-day leave or a half-day leave → never grace-Absent.
- [x] `FirstHalf` leave approved, shift 09:00–18:00, grace 10 → not Absent at 11:00. Absent after
      midpoint 13:30 + 10 min with no punch.
- [x] No shift resolved → never grace-Absent.
- [x] `run_grace_absent_sweep` touches only candidates: an employee already Present today is not
      recomputed, and `Manual`/`Import`/locked rows are skipped.
- [x] A biometric punch inserted without recompute (simulating a deferred device ingest) on a
      grace-Absent row → the next `run_grace_absent_sweep` tick flips it to Present.
- [x] A second concurrent run for the same CDP returns the "lock not acquired" stats and does nothing.
- [x] Cross-tenant: the job for CDP A never creates or touches CDP B rows.
- [x] The 23:59 `attendance_sweep` behaviour for past days is unchanged (existing assembler-job tests pass).
- [x] `uv run pytest` is green.

## Build notes
- Built in parallel with 178 (same merged suite: 436 passed, 2 already failing on HEAD).
- **FirstHalf criterion, as built:** the status order is unchanged, so a no-punch day with an approved FirstHalf leave reads `OnLeave` (rows 8-9), never grace-Absent; this matches the "half-day leave → never grace-Absent" criterion. `_grace_absent_elapsed` itself does move the reference to the midpoint (unit-tested directly). The two criteria conflicted; the order-preserving one won. Documented in assembler.md §11.1.
- `_grace_absent_elapsed` takes `shift_end_at` too, which the midpoint needs. The shared start reference is `_effective_shift_bounds`.
- Also added a row to `docs/leave-and-attendance/shared/jobs-and-scheduling.md`.

Completed: 2026-10-05
