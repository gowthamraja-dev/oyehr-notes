---
task: 256
title: Hybrid recalculation runner — inline under a threshold, scheduled job above it
status: done
depends_on: [255]
---

# 256 — Hybrid runner

Plan: `.plans/shift-day-swap-plan.md` §2, §3 "Hybrid runner". Repo: `workspace-1/hrms/backend/`.

## Scope
Decide **inline vs queued** and run the queue. Hybrid was chosen on 26-Oct-26: small swaps finish in the request,
large ones never block it. Both paths call `shift_day_override_service.recalculate_override` (255) — no second implementation.

1. **Setting** `shift_day_override_sync_max_employee_days: int = 500` in `app/core/config.py` (`Settings`, env
   `SHIFT_DAY_OVERRIDE_SYNC_MAX_EMPLOYEE_DAYS`). Config only via `Settings`; nothing hardcoded.
2. `settle_overrides(db, cdp_id, overrides, *, actor_user_id) -> SettleOutcome` (in the 255 module or a sibling
   `shift_day_override_runner.py`): sum `count_impact(...).employee_days` over the rows being saved;
   - total ≤ threshold → mark each `Running`, call `recalculate_override`, return `mode="inline"`;
   - total > threshold → leave each `Pending`, return `mode="queued"`.
   The threshold is for the **whole request**, so seven Saturdays cannot each squeak under it.
3. **Job** `run_shift_day_override_recalc(db, cdp_id, as_of) -> dict[str, int]` registered in `JOB_DEFS` as
   `shift_day_override_recalc`, cron `*/5 * * * *`. Per CDP: `pg_try_advisory_xact_lock` under key
   `shift_day_override_recalc:<cdp>` (same pattern as `attendance_assembler_job._try_acquire_lock`; every Fargate replica
   fires at once); take up to N oldest rows with `recalc_status = 'Pending'` — **archived rows included** — mark `Running`,
   commit, process, commit. Stats: `picked, done, failed, skipped_locked`.
4. **Recovery:** a row stuck `Running` for > 30 min (crashed task) is treated as `Pending` again. `Failed` rows are retried
   automatically up to 3 times (count kept in `recalc_result.attempts`), then wait for HR's Retry button (257).
5. The runner must not depend on process memory: status lives in the row, so any replica can resume.

## Files
- `workspace-1/hrms/backend/app/core/config.py`
- `workspace-1/hrms/backend/app/services/shift_day_override_runner.py` (new: `settle_overrides`, `run_shift_day_override_recalc`)
- `workspace-1/hrms/backend/app/services/shift_day_override_service.py` (+ `scope_row_count`)
- `workspace-1/hrms/backend/app/tests/day_swap.py` (new shared test builders; the 255 test now imports them)
- `workspace-1/hrms/backend/app/services/job_defs.py`
- `workspace-1/hrms/backend/app/tests/modules/test_shift_day_override_job.py` (new)

## Acceptance criteria
- [x] Request totalling exactly the threshold runs inline, threshold + 1 queues (parametrised 3/2/1/0 over a 2-employee-day request)
- [x] Inline leaves rows `Done` (or `Failed` on an employee error) with `recalculated_at`; queued leaves `Pending`, clears `recalc_result`, touches no attendance row
- [x] The threshold is for the whole request: two overrides of 1 employee-day each queue together at threshold 1
- [x] The job picks a `Pending` row **and an archived one** (undo owed), recalculates both, sets `Done`; the second run picks 0
- [x] A second runner holding the CDP lock: tested with a real second connection holding `pg_advisory_lock` on the same key → `skipped_locked = 1`, nothing picked, the row still `Pending`. A claim whose lock is lost between claim and processing is handed back to `Pending` with its attempt un-counted
- [x] `Running` older than 30 min is reclaimed and processed; `Running` 5 min old is left alone; a stale `Running` with attempts used up becomes `Failed` instead of looping
- [x] `Failed` is retried exactly 3 times (never twice in one run), then `picked = 0` and `retries_exhausted = 1`; HR's Retry (clear `recalc_result`, status `Pending`) works and restarts the count
- [x] Another CDP's overrides are never picked up by this CDP's run (and run fine on their own run)
- [x] Job registered in `JOB_DEFS` as `shift_day_override_recalc`, cron `*/5 * * * *`, parsed by the scheduler's `_trigger`; `uv run pytest app/tests/modules/test_shift_day_override_job.py` → 20 passed
- [x] Mutation check, 6 deliberate bugs, each caught: `>` → `>=` on the threshold; no tenant filter on the queue; archived rows skipped; no retry cap; no `seen` set (an override picked twice in one run); no flush after the reclaim
- [x] Full backend suite before/after: no new failure; +35 passing (15 + 20 new). The 94 pre-existing failures are the same ones listed in task 254
- [x] Threshold re-checked, see below

## Threshold measurement (300 attendance rows, one org-wide swap, local Postgres in Docker)
**6.9 ms and 22 SQL statements per recalculated row** (2.08 s for 300). So 500 employee-days is about 3.5 s locally. Against RDS the per-statement round trip dominates: at ~1–2 ms that is roughly 30–50 ms per row, i.e. **about 15–25 s for 500** — inside the ALB's 60 s idle timeout, but not snappy. Kept the approved default of **500**; it is `SHIFT_DAY_OVERRIDE_SYNC_MAX_EMPLOYEE_DAYS`, so an environment can lower it with no code change. Re-measure on the real dev/prod DB before relying on it; if it is slow, lowering to ~200 only means more swaps wait up to 5 minutes (the Day swaps screen shows the status). The 22 statements/row are `recompute_attendance_day`'s own and are the bigger lever, not this threshold.

## Things 257 must know
- **Sessions are `autoflush=False`** (`core/db.py`). A modification is not visible to the next query until `db.flush()`. This bit the reclaim (caught by a test); 257 must flush after writing override rows and before `settle_overrides` / any count query.
- `settle_overrides(db, cdp_id, overrides, *, actor_user_id) -> SettleOutcome(mode, employee_days, threshold)`; flushes, never commits; the API commits after it. Expose `mode` and `employee_days` in the create response.
- The job audits as `updated_by_id`, else `created_by_id` (an archived override: `archived_by_id` first). 257 **must set `created_by_id`** (and `archived_by_id` / `updated_by_id` on archive / upsert); an override with none is marked `Failed` ("no acting user").
- HR's Retry: set `recalc_status = 'Pending'` and `recalc_result = None` (that clears `attempts`), then call `settle_overrides` (small → inline, big → stays queued). Retry on a `Done` row is a 409.
- Automatic attempts live in `recalc_result.attempts`; `recalculate_override` replaces `recalc_result` with a fresh dict, so the job re-adds `attempts` afterwards. The inline path has no `attempts` key.
- `Running` becomes visible to the UI only on the job path (committed claim); an inline run is `Running` only inside the request transaction.

## Decisions
- Two short transactions per override in the job (claim, then process), each taking the CDP advisory lock, because `pg_try_advisory_xact_lock` is released by every commit and `Running` must be committed before the work starts. Strict mutual exclusion holds during processing; between two overrides another replica may take the next one, which is fine (claims use `FOR UPDATE SKIP LOCKED` and status).
- At most 20 overrides per CDP per 5-minute tick (`_MAX_OVERRIDES_PER_RUN`); the rest wait for the next tick.
- `retries_exhausted` is reported every run (it is the visible "waiting for HR" count) and is computed after the run.
- A CDP with nothing queued costs one count query and no lock.

Completed: 2026-10-26
