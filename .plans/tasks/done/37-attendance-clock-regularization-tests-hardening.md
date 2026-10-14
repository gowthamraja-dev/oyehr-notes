---
task: 37
title: Cross-cutting test hardening — idempotency, night shift, concurrent approve, isolation
status: done
depends_on: [31, 32, 33]
---

# 37 — Cross-cutting test hardening

## Discussion

Tasks 29-33 each already require their own tests as part of their own acceptance criteria (per
CLAUDE.md: "add tests in the same change as the feature — not later"). This task is not "write
the tests nobody wrote" — it's the module-specific must-haves that `docs/leave-and-attendance/
attendance/api-and-pages.md §7` and `shared/api-conventions.md §7` call out as needing dedicated,
deliberately-designed fixtures rather than falling naturally out of a single endpoint's happy-path
test. Run the full suite and fill exactly the gaps below; do not re-write tests that already exist
from tasks 29-33 as part of this task.

## Files

### Edited

- `backend/app/tests/modules/test_attendance.py`:
  - **Recompute idempotency** (mirrors `assembler.md §10.3`'s mandatory acceptance test, at
    single-row granularity since there's no batch job in this task set): call
    `recompute_attendance_day` twice over a fixed fixture (a clock-in + clock-out pair) and assert
    every column except `assembled_at`/`updated_at` is byte-identical, and `punch_count` did not
    double.
  - **Night shift attribution**: a shift with `start_time=22:00`, `end_time=06:00`
    (`is_night_shift` or `end_time <= start_time` triggers the rollover per task 30). Clock in at
    22:05 on day D, clock out at 06:03 on day D+1. Assert both punches land on day D's
    `employee_attendance_details` row, `worked_minutes ≈ 478`.
  - **Concurrent double-approve**: two approve calls issued against the same Pending request (in
    quick succession, simulating a manager double-click / two browser tabs). Assert only one
    materializes punches and flips status; the second gets `409`, not a duplicate punch pair —
    exercises the dedupe index from task 29 together with task 33's Pending-status guard.
  - **Cross-CDP isolation**: a second `CareDeliveryProgramMaster` + corp + employee (matching
    `test_employees.py`'s existing pattern) whose punches, attendance rows and requests never
    appear in the first tenant's `/me/*` or manager `/requests` responses, and whose employee
    cannot be targeted by the first tenant's manager/admin.
  - **Encrypted round-trip**: one test per `EncryptedRoute` endpoint added across tasks 31-33
    (`/me/clock-in`, `/me/clock-out`, `/me/today`, `/me/daily`, `/requests` POST, `/requests/{id}/
    approve`, `/requests/{id}/reject`) confirming the `{iv, ct}` wire shape round-trips — following
    `test_encryption.py`'s existing pattern. If tasks 31-33 already added one of these individually,
    skip re-adding it here; this task's job is to confirm the **full set** is covered, not to
    duplicate.
  - Run `uv run pytest` (or the `docker compose exec api python -m pytest` equivalent per
    CLAUDE.md) for the **whole** backend suite, not just this module, and confirm no regression in
    `test_shifts.py` from task 30's `_resolve_employee_shift` -> `resolve_employee_shift` rename.

## Acceptance criteria

- [ ] Idempotency test passes: two recompute calls over an unchanged punch set produce identical
      rows except the two timestamp columns, and `punch_count` is stable.
- [ ] Night-shift test passes: both punches attribute to the shift's start date.
- [ ] Concurrent double-approve test passes: exactly one set of Manual punches is created, the
      second call is rejected.
- [ ] Cross-CDP isolation test passes for every new endpoint (self, manager, admin surfaces).
- [ ] Encrypted round-trip coverage confirmed complete across all `EncryptedRoute` endpoints added
      in tasks 31-33.
- [ ] Full `uv run pytest` suite passes with no new failures beyond the two pre-existing,
      unrelated `test_engagement_email.py` failures already noted in task 13's completion record.

Completed: 2026-08-18
