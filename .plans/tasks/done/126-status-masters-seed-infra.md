---
task: 126
title: Seed status_masters catalogs for ATTENDANCE / ATTENDANCE_REQUEST / LEAVE_REQUEST
status: done
depends_on: []
---

# 126 — Seed status_masters catalogs for ATTENDANCE / ATTENDANCE_REQUEST / LEAVE_REQUEST

## Scope

Foundation task for a 5-task set (126-130) that replaces the free-text status columns on
`employee_attendance_details`, `attendance_request_details`, and `leave_request_details` with a
real `status_master_id` foreign key into the shared `status_masters` catalog
(`backend/app/models/status_master.py`), following the **proven, already-in-production pattern**
used by payroll/banking/visitor-management — not the abandoned "denormalized pair, string stays
authority" design in `docs/leave-and-attendance/shared/status-masters-and-seeding.md` §2. This
task set **supersedes and reverses that doc's decision** for these three tables specifically (task
127/128/129 each update the relevant section of that doc and of
`docs/leave-and-attendance/attendance/vocabularies.md` — do not leave stale docs behind).

This task (126) only adds the catalog rows and the resolver-helper pattern each domain's cutover
task will use. It makes **zero behavior change** — nothing reads or writes `status_master_id` yet,
nothing is dropped yet. `attendance_status`/`status` string columns keep working exactly as today
until tasks 127/128/129 land. This task exists on its own because all three downstream tasks
depend on the catalog rows existing, and seeding is safe to ship and verify independently.

**Everything downstream (127, 128, 129, 130) depends on this task.**

## The one hard constraint every downstream task must honor

Unlike payroll's codes (`PAYROLL_INITIATED`, prefixed, because payroll never had pre-existing
consumers doing raw string equality against unprefixed values), **the `status_code` values seeded
here MUST be byte-for-byte identical to the string values these columns hold today** —
`"OnLeave"`, `"Present"`, `"HalfDay"`, `"OnDuty"`, `"WFH"`, `"Absent"`, `"Pending"`, `"Approved"`,
`"Rejected"`, `"Cancelled"`. There are dozens of existing consumers doing exact string equality
against these values that are explicitly **out of scope** for this task set (per the "just migrate
storage, not the vocabulary" scope decision) — the manager/admin dashboards
(`frontend/src/dashboards/hrManager/Attendance.tsx`, `.../AttendanceInsightsRegister.tsx`), the
employee self-service page (`frontend/src/dashboards/Employee/MyAttendance.tsx`), the mobile app's
`LeaveScreen`/`RecentRequestsCard`/`MyTeam` screens, and payroll's own raw-string checks
(`payroll_attendance_service.py`). Changing the wire values would silently break all of them. Task
130 fixes the one place the mobile app's matching was *already* wrong before this change
(`AttendanceList.js`'s `'Leave'`/`'Half Day'` vs the real `'OnLeave'`/`'HalfDay'`) — do not "fix"
any other consumer's casing as part of this seed task; that's scope creep this task set explicitly
declined (see the "vocabulary scope" decision recorded 2026-09-23: migrate storage only, no new
Live-State/OnBreak/workflow/exception vocabulary).

## Files

### New

- `backend/scripts/seed_attendance_status_masters.py` — modeled exactly on
  `backend/scripts/seed_payroll_status_masters.py` (idempotent get-or-create by
  `(source_activity, status_code)`, `--dry-run` flag, attributes `created_by_id`/`updated_by_id`
  to the lowest-id user, prints ids for confirmation only — nothing is ever hardcoded).
  `SOURCE_ACTIVITY = "ATTENDANCE"`. Rows (`status_code`, `status_name`):
  - `OnLeave` → "On Leave"
  - `Present` → "Present"
  - `HalfDay` → "Half Day"
  - `Holiday` → "Holiday"
  - `WeekOff` → "Week Off"
  - `OnDuty` → "On Duty"
  - `WFH` → "Work From Home"
  - `Absent` → "Absent"
- `backend/scripts/seed_attendance_request_status_masters.py` — same pattern.
  `SOURCE_ACTIVITY = "ATTENDANCE_REQUEST"`. Rows:
  - `Pending` → "Pending"
  - `Approved` → "Approved"
  - `Rejected` → "Rejected"
  - `Cancelled` → "Cancelled"
- `backend/scripts/seed_leave_request_status_masters.py` — same pattern.
  `SOURCE_ACTIVITY = "LEAVE_REQUEST"`. Rows:
  - `Pending` → "Pending"
  - `Approved` → "Approved"
  - `Rejected` → "Rejected"
  - `Cancelled` → "Cancelled"

None of these three scripts run on boot (matches the RBAC-seeding precedent already documented in
`hrms/CLAUDE.md` and the payroll/visitor seed scripts' own docstrings) — a deliberate step, run
once per environment:

```bash
uv run python scripts/seed_attendance_status_masters.py
uv run python scripts/seed_attendance_request_status_masters.py
uv run python scripts/seed_leave_request_status_masters.py
```

### Edited

- `docs/leave-and-attendance/shared/status-masters-and-seeding.md` — add a note at the top of §2
  (the "Decision" section) that this decision has been **superseded for `employee_attendance_details`,
  `attendance_request_details`, and `leave_request_details`** by tasks 126-130, with a one-line
  pointer to this file and to task 127/128/129 for the replacement design. Do not delete the
  original §2 text — it's still historically accurate for why the denormalized-pair approach was
  chosen originally, and still applies to any *other* table that might use this pattern later.

## Acceptance criteria

- [x] All three seed scripts exist, are idempotent (running twice does nothing the second time),
      and `--dry-run` prints the plan without writing.
- [x] Running all three against a fresh/empty `status_masters` table inserts the rows above (8 + 4
      + 4 = 16 total) with the exact `status_code` values listed (verified with a `SELECT
      source_activity, status_code, status_name FROM status_masters WHERE source_activity IN
      ('ATTENDANCE', 'ATTENDANCE_REQUEST', 'LEAVE_REQUEST') ORDER BY source_activity,
      status_code;`).
- [x] Running any script a second time reports "Nothing to do" and inserts no duplicate rows
      (verified — re-run printed "already existed, reused" at the same ids).
- [x] `status-masters-and-seeding.md` §2 has the superseded-by note.
- [x] No application code changed — `test_attendance_dashboard.py` (66/66) still passes unchanged
      after seeding; this task added no new test file, only catalog data + 3 new scripts.

**Correction (same session, before task 127 started)**: the first pass under-counted the real
vocabulary — it seeded `OnLeave/Present/HalfDay/OnDuty/WFH/Absent` (6) for `ATTENDANCE` and
`Pending/Approved/Rejected` (3) for `ATTENDANCE_REQUEST`, based on an initial research summary
that undercounted. A direct audit of the real dev DB
(`SELECT attendance_status, count(*) FROM employee_attendance_details GROUP BY 1` and the
equivalent for the other two tables) plus a direct grep for every `.status = "..."` assignment
site turned up two gaps before task 127 could rely on this catalog: `Holiday` (30 real rows) and
`WeekOff` (558 real rows) are values `_attendance_status()`
(`attendance_recompute_service.py:357-360`) genuinely writes and were missing from `ATTENDANCE`;
`Cancelled` (`attendance/service.py:1337`, an employee withdrawing their own pending
regularization request) was missing from `ATTENDANCE_REQUEST`. Both scripts were corrected and
re-run (idempotent — only the missing rows were inserted); final counts are 8 `ATTENDANCE` + 4
`ATTENDANCE_REQUEST` + 4 `LEAVE_REQUEST` = 16 rows, not the originally-reported 13. **Lesson for
127/128/129**: audit real DISTINCT values in the actual database and grep every assignment site
directly — don't trust a single prior research pass's vocabulary list without re-verifying it
against the live data before writing a migration that backfills from it.

Completed: 2026-09-23
