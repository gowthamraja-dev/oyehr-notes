---
task: 178
title: Compute break_minutes from IN/OUT punch pairs (recompute + sweep)
status: done
depends_on: []
---

# 178 — Compute `break_minutes` from IN/OUT punch pairs

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Paths below are
relative to `backend/`. Decided with the user on 2026-10-05: **store only, don't deduct.**
`worked_minutes` stays the first-punch → last-punch span (tasks 131/134). Breaks are recorded
alongside it and are not subtracted.

## Why
`employee_attendance_details.break_minutes` (`app/models/employee_attendance_detail.py:60`, Integer,
`server_default 0`) exists, but it is always written as 0:
`app/services/attendance_recompute_service.py:592` → `break_minutes = 0  # tasks 131/134: no break deduction`.
The shift's `policy_config.break_minutes` is stored and editable too, but nothing reads it. So HR has
no record of how long employees were off the clock between sessions.

## Scope
### 1. The calculation
Add a pure helper next to `_settle_worked_minutes` in `attendance_recompute_service.py`:

```python
def _break_minutes(kept: list[tuple[AttendancePunchDetail, str]]) -> int:
```

It takes the debounced `kept` list from `_debounce_and_direction`, sorted by `punch_at`.
- **When every kept punch has a trusted explicit direction** (`punch.direction` is not NULL and
  `punch.punch_source` is not in `DIRECTION_UNTRUSTED_SOURCES`, i.e. Web / Mobile / Manual): walk
  the punches in order. Each **OUT followed directly by an IN** adds `(in.punch_at − out.punch_at)`.
  Repeated same-direction punches (IN, IN or OUT, OUT) add nothing; that gap is not a break.
- **Otherwise** (any Biometric punch, or any NULL direction): pair by position, the same parity rule
  `is_open_session` uses. Sessions are `(k0,k1), (k2,k3), …` and break = Σ `k[2i].punch_at − k[2i−1].punch_at`
  for i ≥ 1. Device-reported directions are unreliable (task 136), so they are not used.
- Only **closed** gaps count. A trailing OUT with no IN after it is the end of the day (or a break
  still in progress), not a break, and contributes 0 until an IN arrives.
- Floor each gap to whole minutes, sum them, and clamp the total to `[0, worked_minutes]`. The sum
  can't exceed the span in theory, but the clamp guards the `MAX_WORKED_MINUTES_PER_DAY` cap.
- 0 or 1 kept punches → 0.

### 2. Wire it in
- `recompute_attendance_day` (`:550-672`): replace the `break_minutes = 0` line with
  `break_minutes = _break_minutes(kept)`, and write it at `:640` as today.
  `worked_minutes`, status, `payable_day_fraction`, late/early and overtime **do not change**.
- `preview_attendance_day_with_extra_punches` (`:784`, the read-only twin) must compute it the same
  way, so the two never drift.
- Rows with `source='Import'`/`'Manual'`: don't recompute `break_minutes`; it is one of the preserved
  punch-derived fields. If task 169 has landed, add it to that preserve list. If not, note it in 169.
- Update the docstring on `_settle_worked_minutes` ("no break/gap accounting") to say that breaks are
  now measured separately in `_break_minutes` and still not deducted.

### 3. The cron job
The 23:59 `attendance_sweep` (`app/services/job_defs.py:51-56` → `run_attendance_sweep` in
`app/services/attendance_assembler_job.py:88`) already calls `recompute_attendance_day` for every
(employee, date) in the last 7 days. With step 2 in place it fills `break_minutes` for that window on
its next run, so no new job is needed for breaks.
- Update the comment on the `attendance_sweep` JobDef to mention that it now also settles `break_minutes`.
- History older than 7 days is backfilled by the operator with
  `uv run python scripts/recompute_attendance_history.py --cdp <id> --start-date … --end-date …`.
  Locked rows need `--force`. Document this in the runbook line in `assembler.md` §8 rather than
  running it automatically.

### 4. Expose it
`break_minutes` is not in any attendance output schema today (`app/modules/attendance/schemas.py`).
Add `break_minutes: int` to the day-row outputs: the HR register row, the employee's own day/history
row (`/attendance/me/...`) and the manager team row. Then mirror it in the TS types in
`frontend/src/lib/api.ts`. Rendering it in the UI is task 180.

### Out of scope
- Deducting breaks from `worked_minutes`, or comparing against the shift's allowed
  `policy_config.break_minutes` (an "excess break" flag). That would need its own task if wanted.
- Overtime (`overtime_minutes` stays 0).
- Grace-based absent marking (task 179).

## Files
- `app/services/attendance_recompute_service.py`: `_break_minutes`, the recompute and preview wiring,
  and docstrings.
- `app/services/job_defs.py`: the comment only.
- `app/modules/attendance/schemas.py` and the service/serializers that build those rows.
- `frontend/src/lib/api.ts`: the types.
- `docs/leave-and-attendance/attendance/assembler.md` §8 (Worked, break and overtime minutes) and §5.6:
  describe the new rule, the trusted vs. parity split, "not deducted", and the backfill command.
- `app/tests/modules/test_attendance_recompute.py`: the existing assertions that
  `row.break_minutes == 0` with `break_minutes: 60` configured (`:305`, `:321`, `:345`, `:492-511`) must
  become "`worked_minutes` unchanged, `break_minutes` = the measured gap". Keep the
  no-deduction intent explicit in each test name.

## Acceptance criteria
- [x] Web punches IN 09:00, OUT 13:00, IN 13:45, OUT 18:00 → `break_minutes=45`, `worked_minutes=540`
      (unchanged span), status Present after close.
- [x] Three sessions (two gaps of 30 and 15 min) → `break_minutes=45`.
- [x] IN 09:00, OUT 13:00 only (day open, no return yet) → `break_minutes=0`.
- [x] Trusted directions with IN 09:00, IN 09:30, OUT 18:00 → `break_minutes=0`.
- [x] Biometric punches with random directions, 4 punches 09:00 / 13:00 / 13:30 / 18:00 →
      `break_minutes=30` (parity pairing).
- [x] A double-tap within 60 s is debounced first and does not create a phantom break.
- [x] Clock-in and clock-out through `/attendance/me/clock-in|out` updates `break_minutes` synchronously
      (the recompute at `service.py:938` / `:1043`).
- [x] `run_attendance_sweep` over a seeded 7-day window fills `break_minutes` on rows that had 0.
- [x] `preview_attendance_day_with_extra_punches` returns the same `break_minutes` as a real recompute.
- [x] `break_minutes` appears in the register / me / team API responses. Tenant scoping is unchanged
      (existing org-scoping tests still pass).
- [x] `uv run pytest` is green.

## Build notes
- Built in parallel with 179 in agent worktrees, then merged into `workspace-2/hrms` uncommitted. Merged suite: 436 passed, 2 failed; both failures already failed on HEAD (`test_analytics_yesterday_never_punched_counts_absent` is date-dependent, `test_hardening_manager_scope_sweep` hits a login KeyError).
- 169's Import/Manual preserve-list bullet was deferred because 169 hasn't landed; the 169 file has been updated with it.
- Extras: `break_minutes` is also on `TodayOut` (`/me/today`) and in the clock-out log line; preview extra punches are tagged `Manual`. The `job_defs.py` comment was handled in 179.

Completed: 2026-10-05
