---
task: 29
title: Attendance punch/day/request models + migration (attendance_punch_details, employee_attendance_details, attendance_request_details, attendance_audit_log)
status: done
depends_on: []
---

# 29 — Attendance punch/day/request models + migration

## Discussion

This task, and the nine that follow it (30–38), implement
`.design/prompts/Attendance_Clock_In_Out_Regularization_Plan.md` — employee clock in/out and
request regularization. That prompt is a **generic** design (its own `attendance_records` /
`attendance_regularizations` / `attendance_audit_log` sketch). This codebase already has a far
more detailed, reconciled domain model for exactly this feature, written against the real
`.design/sql/Attendance & Leave/HRMS.sql` schema — `docs/leave-and-attendance/attendance/*.md`
and `docs/leave-and-attendance/shared/*.md`. **That corpus is authoritative; the prompt is the
trigger for this task set, not the schema to build.** Every task 29–38 reconciles the prompt's
acceptance criteria against it. Read `docs/leave-and-attendance/README.md` first for the index.

### What this task set builds, and what it deliberately does not

The full domain model spans devices/biometric ingestion (Phase 7), a scheduled batch assembler +
job runner (`app/jobs/`, which doesn't exist anywhere in this repo — see
`docs/leave-and-attendance/shared/jobs-and-scheduling.md`), the full attendance register/analytics
KPI dashboards (Phase 6), and leave-status integration (the `leave` module doesn't exist yet either
— see `.plans/tasks/ongoing/21-28`). None of that is required by the prompt's own phase boundary
(§29: "do not include yet: geofencing, GPS validation, biometric-device integration... complex
payroll overtime calculations") or its scope section (§2, which only lists clock in/out, shift-
based attendance, history, and **regularization** — not OnDuty/WFH/ShortLeave, and not a manager
analytics dashboard). Task 30 states the exact reduced algorithm this task set implements instead
of the full batch assembler. Concretely, this task set (29–38) does **not** build:

- `attendance_device_masters` / `employee_device_mappings` / `ingest_router.py` — no biometric
  device integration (prompt §29 explicitly excludes it).
- `app/jobs/assembler.py` or any scheduled job — no job-running mechanism exists in this repo at
  all (`docs/leave-and-attendance/shared/jobs-and-scheduling.md`); building one is a separate,
  cross-cutting initiative that also serves leave accrual/rollover. This task set computes
  attendance state **synchronously, per (employee, date), on clock-in/out/regularization-approval**
  instead of an offline batch — see task 30.
- Auto-absent marking (`assembler.md §11`) — it requires a scheduled sweep for employees who never
  punch at all; with no job runner, there is nothing to trigger it. A `Working` day with no punch
  stays `attendance_status = NULL` ("yet to check in / not settled") indefinitely rather than
  flipping to `Absent`. Tracked as a gap, not silently faked.
- `request_type` values other than `Regularization` — `OnDuty`, `WFH`, `ShortLeave` share this
  table's schema (so a later task adds them with **no migration**) but are out of scope for "Clock
  In/Out & Request Regularization" per the prompt's own §2 scope list.
- The attendance register / analytics KPI band (`GET /attendance/register`, `/analytics`,
  `/employees/{id}/analytics`) — `manager-approvals.md §1` scope, a separate Phase 6 initiative.
  The manager regularization inbox (task 33/36) embeds just the one employee/one day comparison
  it needs (`manager-approvals.md §3`) directly in the request detail response, not a general
  register endpoint.
- `overtime_minutes` computation (`assembler.md §8.1`) — stays `0` always; the column exists for
  schema fidelity but the OT-tracking-enabled/`ot_after_minutes` calculation is exactly the
  "complex payroll overtime" the prompt excludes.
- `status_masters` seeding/lookup — `status_master_id` on the two new tables below stays `NULL`
  forever in this task set (nullable, "derived lookup, never source of truth" per
  `shared/status-masters-and-seeding.md`). Seeding that global, cross-module catalogue is shared
  work with the leave module; out of scope here.
- Geofence enforcement UI, `is_locked`/payroll-cutoff admin action — the `is_locked` column exists
  and clock-in/out still checks it (defensive, matches the documented `423 Locked` contract) but
  nothing in this task set ever sets it `true`.

### The new audit table — closing gap 17 for this task set's own actions only

`docs/leave-and-attendance/attendance/gaps.md#17` records that attendance has **no audit trail** —
an open, unresolved gap in the authoritative docs. The generic prompt this task set is built from
explicitly requires one (§20, §21, acceptance §"Audit history is created"). Building the general
case (HR manual edits via a not-yet-built `PATCH /daily/{id}`, etc.) is out of scope, but the
actions *this* task set introduces — clock in, clock out, regularization submitted / approved /
rejected / cancelled — are cheap to make auditable now, closing gap 17 for exactly that slice.
`attendance_audit_log` below is modeled directly on the existing
`backend/app/models/shift_assignment_audit.py` (append-only, no `updated_at`) — not part of
`HRMS.sql`, a new table this task set adds.

### Column-for-column source

The three `HRMS.sql`-derived tables below are copied field-for-field from
`.design/sql/Attendance & Leave/HRMS.sql` lines 211–300 (the `attendance_punch_details`,
`employee_attendance_details`, `attendance_request_details` `CREATE TABLE` blocks) — cross-check
against it if in doubt, per CLAUDE.md's "the real model is authoritative for existing tables;
`HRMS.sql` is authoritative for the new ones" rule (`docs/leave-and-attendance/README.md §2.1`).
Deviations from that SQL are the ones already decided and flagged in
`docs/leave-and-attendance/attendance/gaps.md#18` (the punch dedupe index) — reproduced below —
plus the CLAUDE.md-mandated ones every model in this repo already follows (`server_default` on
every non-null defaulted column, `*_master_id` → plain `BigInteger` when that master table doesn't
exist yet, tenant column named `care_delivery_program_master_id`).

## Files

### New

- `backend/app/models/attendance_punch_detail.py`:

  ```python
  from datetime import datetime
  from typing import Any

  from sqlalchemy import (
      BigInteger, Boolean, DateTime, ForeignKey, Index, Numeric, String, func, text,
  )
  from sqlalchemy.dialects.postgresql import JSONB
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class AttendancePunchDetail(Base):
      """APPEND-ONLY. The canonical attendance event — every clock-in/out lands here and is
      never edited in place; void one with `archive = true` (assembler.md §5.1, gaps.md #26).

      `attendance_device_master_id` stays a plain nullable BigInteger, not a real FK —
      `attendance_device_masters` (biometric devices) is out of scope for this task set
      (CLAUDE.md's "*_master_id fields whose master table doesn't exist yet" rule). This task
      set only ever writes `punch_source IN ('Web', 'Manual')` with
      `attendance_device_master_id = NULL` — the Manual rows come from an approved
      regularization (task 33), never from a device.
      """

      __tablename__ = "attendance_punch_details"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_master_id: Mapped[int | None] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      attendance_device_master_id: Mapped[int | None] = mapped_column(BigInteger)  # no device module yet
      device_serial: Mapped[str | None] = mapped_column(String(120))
      enrollment_no: Mapped[str | None] = mapped_column(String(64))
      punch_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))  # UTC
      punch_source: Mapped[str] = mapped_column(String(30), server_default=text("'Biometric'"))
      direction: Mapped[str | None] = mapped_column(String(10))  # IN | OUT
      work_location_master_id: Mapped[int | None] = mapped_column(ForeignKey("work_location_masters.id"))
      lttd: Mapped[float | None] = mapped_column(Numeric(10, 7))
      lgtd: Mapped[float | None] = mapped_column(Numeric(10, 7))
      is_within_geofence: Mapped[bool | None] = mapped_column(Boolean)
      raw: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
      employee_attendance_detail_id: Mapped[int | None] = mapped_column(
          ForeignKey("employee_attendance_details.id"))  # set by the recompute step, task 30
      processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      unresolved_reason: Mapped[str | None] = mapped_column(String(120))
      is_active: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
      archive: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
      created_by_id: Mapped[int | None] = mapped_column(BigInteger)  # nullable — device ingest has no user
      updated_by_id: Mapped[int | None] = mapped_column(BigInteger)
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      updated_at: Mapped[datetime] = mapped_column(
          DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

      __table_args__ = (
          # gaps.md #18 (RESOLVED): the supplied SQL's 4-column unique index never deduped app/
          # manual punches (device id NULL). employee_master_id is added, NULLS NOT DISTINCT.
          Index(
              "uq_attendance_punch_details_dedupe",
              "care_delivery_program_master_id", "employee_master_id",
              "attendance_device_master_id", "enrollment_no", "punch_at",
              unique=True, postgresql_nulls_not_distinct=True,
          ),
          Index("ix_attendance_punch_details_employee_punch_at", "employee_master_id", "punch_at"),
          Index("ix_attendance_punch_details_unresolved", "care_delivery_program_master_id", "punch_at"),
      )
  ```

- `backend/app/models/employee_attendance_detail.py`:

  ```python
  from datetime import date, datetime
  from decimal import Decimal

  from sqlalchemy import (
      BigInteger, Boolean, Date, DateTime, ForeignKey, Index, Integer, Numeric, String, Text,
      UniqueConstraint, func, text,
  )
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class EmployeeAttendanceDetail(Base):
      """One row per employee per date — every report and this feature's history/register
      table reads this and nothing else. The unique constraint is the idempotency key for
      re-computation (task 30): every write is upsert-by-`(cdp, employee, date)`.

      Deliberately has NO `attendance_request_detail_id` — the FK points the other way
      (`attendance_request_details` has no FK here either) to avoid a circular dependency;
      an approved request is joined by predicate instead (task 33).

      `leave_request_detail_id` stays a plain nullable BigInteger (no FK) — the `leave` module
      doesn't exist in this codebase yet. `status_master_id` stays NULL forever in this task
      set (see task 29's discussion) — nullable, never the source of truth; the varchar
      `attendance_status` column is what every read/write in tasks 30-33 uses
      (`../shared/status-masters-and-seeding.md`).
      """

      __tablename__ = "employee_attendance_details"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_master_id: Mapped[int] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      attendance_date: Mapped[date] = mapped_column(Date)
      shift_master_id: Mapped[int | None] = mapped_column(ForeignKey("shift_masters.id"))
      work_location_master_id: Mapped[int | None] = mapped_column(ForeignKey("work_location_masters.id"))
      day_type: Mapped[str] = mapped_column(String(20), server_default=text("'Working'"))  # Working|WeekOff|Holiday
      status_master_id: Mapped[int | None] = mapped_column(BigInteger)  # derived lookup only, never written to in v1
      attendance_status: Mapped[str | None] = mapped_column(String(30))  # nullable — NULL = not settled yet
      shift_start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      shift_end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      first_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      last_out_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      punch_count: Mapped[int] = mapped_column(Integer, server_default=text("0"))
      worked_minutes: Mapped[int] = mapped_column(Integer, server_default=text("0"))
      break_minutes: Mapped[int] = mapped_column(Integer, server_default=text("0"))
      overtime_minutes: Mapped[int] = mapped_column(Integer, server_default=text("0"))  # always 0 in this task set
      late_by_minutes: Mapped[int] = mapped_column(Integer, server_default=text("0"))
      early_exit_minutes: Mapped[int] = mapped_column(Integer, server_default=text("0"))
      payable_day_fraction: Mapped[Decimal] = mapped_column(Numeric(4, 2), server_default=text("0"))
      leave_request_detail_id: Mapped[int | None] = mapped_column(BigInteger)  # leave module doesn't exist yet
      holiday_detail_id: Mapped[int | None] = mapped_column(ForeignKey("holiday_details.id"))
      is_regularized: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
      source: Mapped[str] = mapped_column(String(20), server_default=text("'Auto'"))  # Auto|Manual|Regularized|Import
      assembled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      is_locked: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))  # never set true in this task set
      remarks: Mapped[str | None] = mapped_column(Text)
      is_active: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
      archive: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
      archived_by_id: Mapped[int | None] = mapped_column(BigInteger)
      archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      created_by_id: Mapped[int | None] = mapped_column(BigInteger)  # nullable — job-written
      updated_by_id: Mapped[int | None] = mapped_column(BigInteger)
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      updated_at: Mapped[datetime] = mapped_column(
          DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

      __table_args__ = (
          UniqueConstraint(
              "care_delivery_program_master_id", "employee_master_id", "attendance_date",
              name="uq_employee_attendance_details_employee_date",
          ),
          Index("ix_employee_attendance_details_cdp_date", "care_delivery_program_master_id", "attendance_date"),
      )
  ```

- `backend/app/models/attendance_request_detail.py`:

  ```python
  from datetime import date, datetime

  from sqlalchemy import BigInteger, Boolean, Date, DateTime, ForeignKey, Index, String, Text, func, text
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class AttendanceRequestDetail(Base):
      """One table for all correction flows, discriminated by `request_type`. This task set
      only ever writes `request_type = 'Regularization'` — `OnDuty`/`WFH`/`ShortLeave` share
      this exact schema (vocabularies.md §4) and are added by a later task with NO migration.

      `from_date`/`to_date` are a range in the schema but this task set's service layer
      (task 32) rejects anything where they are not equal — the table has exactly one
      `requested_in_at`/`requested_out_at` pair, so a multi-day Regularization is incoherent
      (a known schema defect, tracked, not fixed here — see the leave-side gap it's split with).

      Attachments live in the existing polymorphic `image_details`
      (`imageable_type='AttendanceRequestDetail'`, `imageable_id=self.id`) — no column here.
      """

      __tablename__ = "attendance_request_details"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_master_id: Mapped[int] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      request_type: Mapped[str] = mapped_column(String(30))  # Regularization|OnDuty|WFH|ShortLeave
      from_date: Mapped[date] = mapped_column(Date)
      to_date: Mapped[date] = mapped_column(Date)
      requested_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      requested_out_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      reason: Mapped[str | None] = mapped_column(Text)
      status_master_id: Mapped[int | None] = mapped_column(BigInteger)  # derived lookup only, never written in v1
      status: Mapped[str] = mapped_column(String(30), server_default=text("'Pending'"))
      applied_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      approver_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
      approver_employee_master_id: Mapped[int | None] = mapped_column(ForeignKey("employee_masters.id"))
      actioned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      approver_remarks: Mapped[str | None] = mapped_column(Text)
      is_active: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
      archive: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
      archived_by_id: Mapped[int | None] = mapped_column(BigInteger)
      archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
      created_by_id: Mapped[int | None] = mapped_column(BigInteger)
      updated_by_id: Mapped[int | None] = mapped_column(BigInteger)
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      updated_at: Mapped[datetime] = mapped_column(
          DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

      __table_args__ = (
          Index("ix_attendance_request_details_employee_from_date", "employee_master_id", "from_date"),
      )
  ```

- `backend/app/models/attendance_audit_log.py` — new, not part of `HRMS.sql`, modeled on the
  existing `backend/app/models/shift_assignment_audit.py`:

  ```python
  from datetime import datetime
  from typing import Any

  from sqlalchemy import BigInteger, DateTime, ForeignKey, String, func
  from sqlalchemy.dialects.postgresql import JSONB
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class AttendanceAuditLog(Base):
      """Append-only: who changed what about an employee's attendance, from what, to what,
      when and why. Closes gaps.md #17 for exactly the actions tasks 31-33 introduce (clock
      in/out, regularization submit/approve/reject/cancel) — not a general edit-history
      mechanism for the not-yet-built HR manual-edit/lock actions. No `updated_at` — rows are
      never edited after insert, same shape as `ShiftAssignmentAudit`.
      """

      __tablename__ = "attendance_audit_logs"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_master_id: Mapped[int] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      attendance_punch_detail_id: Mapped[int | None] = mapped_column(ForeignKey("attendance_punch_details.id"))
      attendance_request_detail_id: Mapped[int | None] = mapped_column(ForeignKey("attendance_request_details.id"))
      # ClockedIn | ClockedOut | RegularizationSubmitted | RegularizationApproved |
      # RegularizationRejected | RegularizationCancelled
      action: Mapped[str] = mapped_column(String(40))
      old_value: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
      new_value: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
      performed_by_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
      performed_by_role: Mapped[str] = mapped_column(String(20))  # self | manager | admin
      reason: Mapped[str | None] = mapped_column(String(500))
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
  ```

### Edited

- `backend/app/models/__init__.py` — add, grouped near the other attendance-domain imports:
  ```python
  from app.models.attendance_punch_detail import AttendancePunchDetail  # noqa: F401
  from app.models.employee_attendance_detail import EmployeeAttendanceDetail  # noqa: F401
  from app.models.attendance_request_detail import AttendanceRequestDetail  # noqa: F401
  from app.models.attendance_audit_log import AttendanceAuditLog  # noqa: F401
  ```

## Migration

Per CLAUDE.md's nhforms two-head rule, run from `backend/` (never bare `alembic`):

```bash
uv run python scripts/migrate.py revision --autogenerate -m "add attendance punch, day, request and audit tables"
```

Review the generated file before applying:

- Four new tables, exactly the columns/FKs above.
- `uq_attendance_punch_details_dedupe` carries `NULLS NOT DISTINCT` — autogenerate may not emit
  the clause even with `postgresql_nulls_not_distinct=True` set on the `Index`; if it's missing
  from the generated DDL, hand-edit the migration to add it (do not apply without it — this is the
  fix for the resolved dedupe defect in `gaps.md#18`).
- No accidental DROP of unrelated tables (nhforms' metadata is merged in `alembic/env.py`).

```bash
uv run python scripts/migrate.py upgrade heads
```

## Acceptance criteria

- [x] `attendance_punch_details`, `employee_attendance_details`, `attendance_request_details`,
      `attendance_audit_logs` exist with exactly the columns/FKs/constraints above. Confirmed via
      `to_regclass` on all four table names against the live (remote) dev DB.
- [x] `uq_attendance_punch_details_dedupe` is confirmed (via `\d attendance_punch_details` or
      equivalent) to carry `NULLS NOT DISTINCT` — this is the resolved-gap-18 behavior, not
      optional. Confirmed directly: `pg_indexes.indexdef` shows `... NULLS NOT DISTINCT` for this
      index. Autogenerate emitted the clause correctly on its own (`op.create_index(...,
      postgresql_nulls_not_distinct=True)`) — no hand-edit was needed, unlike the task's
      contingency note anticipated.
- [x] Migration applies cleanly via `scripts/migrate.py upgrade heads` — revision `c2e6b0b88453`,
      chained on the app's own head `099852abca49` (confirmed via `scripts/migrate.py heads` that
      this did not collide with or branch off the separate `nhforms` head).
- [x] `docker compose up --force-recreate -d api` starts with no import errors — all four models
      registered in `app/models/__init__.py`; confirmed via container logs ("Application startup
      complete") and a `GET /docs` 200.
- [x] No unrelated tables dropped or altered — reviewed the generated migration file before
      applying: only the four new tables/their indexes in both `upgrade()` and `downgrade()`.
- [x] No `attendance_device_master*`/`employee_device_mapping*` table, model, or reference
      introduced anywhere — out of scope, per this task's discussion.
- [x] Full backend suite (`docker compose exec api python -m pytest`): 246 passed, 2 failed — the
      2 failures (`test_engagement_email.py::test_send_email_ok`,
      `::test_send_email_resolves_template_variables`) are the same pre-existing, unrelated
      failures already noted in task 13's and task 21's completion records, untouched by this
      task's changes.

Completed: 2026-08-17
