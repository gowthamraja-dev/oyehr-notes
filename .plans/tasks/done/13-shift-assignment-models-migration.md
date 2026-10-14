---
task: 13
title: Per-date shift assignment models + migration (employee_shift_assignments, shift_assignment_audits, shift_masters.is_day_off)
status: done
depends_on: []
---

# 13 — Per-date shift assignment models + migration

## Discussion

`.design/prompts/hrms_shift_assignment_apis_ui_walkthrough.md` proposes a normalized,
per-calendar-date shift assignment model (`employee_shift_assignments`, unique per
employee+date) for the Manager Portal's weekly roster. The Manager Portal
(`ShiftScheduling.tsx`) currently runs on a *different*, already-shipped model:
`employee_shift_details` (effective-dated ranges — "this shift from `effctv_dt` onward
until superseded", no per-day override, see task 11). Decided with the user (2026-08-17):
**migrate the Manager Portal to the per-date model.** This task lays the new schema. Tasks
14–17 build the service/API/frontend on top of it.

### What does NOT change

- **`employee_shift_details` stays exactly as-is.** `backend/app/modules/attendance/service.py`
  (`get_resolved_holidays`) still resolves an employee's effective holiday-calendar/work-location
  through it, and the HR Admin "Attendance & Shifts" screen's `assigned_count` (tasks 09–11) still
  reads from it. This task does not touch that table, its model file, or its existing
  `/api/v1/shifts/employee-shifts*` / `/api/v1/shifts/team/employee-shifts` endpoints — they keep
  working for whatever still calls them. Only the Manager Portal *frontend* stops calling them,
  in task 16.
- **No new `shift_definitions` table.** The design doc's §4.1 (`GET /shifts` returning
  id/code/name/start_time/end_time) is already exactly `shift_masters` /
  `GET /api/v1/shifts`. Reuse it — do not duplicate a second shift-catalog table.
- **Known, deliberately unresolved gap — not blocking this task:** the new
  `employee_shift_assignments` table and the existing `employee_shift_details` table are two
  independent datasets after this change. A manager's per-date assignment does **not** feed the
  attendance assembler or the admin "N employees mapped" count. Reconciling them (dual-write?
  replace the assembler's source? leave them separate forever?) is a real open decision, tracked
  as a new gap in task 17's docs update — resolving it is out of scope for this task set, which is
  scoped to the Manager Portal roster screen only.

### Reconciliation decisions (deviations from the design doc, deliberate)

1. **FK column is `shift_master_id`**, not `shift_definition_id` — matches this repo's existing
   naming (`EmployeeShiftDetail.shift_master_id`, `ShiftWeekOffDetail.shift_master_id`).
2. **Table names are plural** (`employee_shift_assignments`, `shift_assignment_audits`) per
   `CLAUDE.md`'s model convention — the design doc's SQL used singular `shift_assignment_audit`.
3. **Tenant column added to both new tables** (`care_delivery_program_master_id`, indexed FK to
   `care_delivery_program_masters`) — the design doc's generic SQL has no tenant column at all;
   every tenant-scoped table in this repo carries it directly (see `shift_masters`,
   `employee_shift_details`).
4. **No DB `CHECK` constraints on `status`/`action` string vocabularies** — this repo validates
   enum-like string columns at the Pydantic/service layer (see `ShiftIn.regularization_approver`'s
   `field_validator`), not via Postgres `CHECK`. Task 14 adds the equivalent validation in code.
5. **`employee_shift_assignments` unique key is `(employee_master_id, assignment_date)` forever,
   including cancelled rows** — cancelling flips `status` to `CANCELLED` rather than deleting the
   row (matches the design doc's own "soft cancellation" and "do not physically delete" guidance
   in its §8). A later re-assignment for the same employee+date **updates that same row** back to
   `ASSIGNED` (task 14's service layer) rather than inserting a second row, so the unique
   constraint is never violated by the normal assign→cancel→reassign cycle.
6. **`is_day_off` added to `shift_masters`, not a forced `code='OFF'` row.** The design doc's
   `chk_shift_day_off` constraint requires a literal `code = 'OFF'` shift; `shift_masters.code` in
   this repo is free tenant text (task 09), not a fixed vocabulary. Any shift a tenant creates can
   be flagged `is_day_off=true` instead. **No admin-UI toggle for this field is built in this task
   set** (that's `hrAdmin/AttendanceShifts.tsx`, out of scope for "manager portal" tasks) — until a
   future admin-UI task adds a toggle, a tenant can only set it via a direct `PATCH
   /api/v1/shifts/{id}` call. The Manager Portal (task 16) renders whichever shift(s) happen to
   have `is_day_off=true` as a "Rest day" option if/when one exists; it does not require one to
   exist to function.

## Files

### New
- `backend/app/models/employee_shift_assignment.py` — new file, one table:

  ```python
  from datetime import date, datetime

  from sqlalchemy import BigInteger, Date, DateTime, ForeignKey, Index, String, UniqueConstraint, func, text
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class EmployeeShiftAssignment(Base):
      """One row = one employee's shift for one calendar date. Unlike EmployeeShiftDetail
      (effective-dated ranges), this is the Manager Portal's per-day roster: each
      (employee, date) pair has exactly one row for its whole lifetime — cancelling flips
      `status` to CANCELLED rather than deleting, so a later re-assignment for the same
      employee+date updates this same row instead of violating the unique constraint.
      """

      __tablename__ = "employee_shift_assignments"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_master_id: Mapped[int] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      assignment_date: Mapped[date] = mapped_column(Date)
      shift_master_id: Mapped[int] = mapped_column(ForeignKey("shift_masters.id"))
      status: Mapped[str] = mapped_column(String(20), server_default=text("'ASSIGNED'"))  # ASSIGNED | CANCELLED
      note: Mapped[str | None] = mapped_column(String(500))
      created_by_id: Mapped[int | None] = mapped_column(BigInteger)
      updated_by_id: Mapped[int | None] = mapped_column(BigInteger)
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
      updated_at: Mapped[datetime] = mapped_column(
          DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

      __table_args__ = (
          UniqueConstraint("employee_master_id", "assignment_date", name="uq_employee_shift_assignment_date"),
          Index("ix_employee_shift_assignments_date", "assignment_date"),
      )
  ```

- `backend/app/models/shift_assignment_audit.py` — new file, one table:

  ```python
  from datetime import date, datetime

  from sqlalchemy import BigInteger, Date, DateTime, ForeignKey, String, func
  from sqlalchemy.orm import Mapped, mapped_column

  from app.core.db import Base


  class ShiftAssignmentAudit(Base):
      """Append-only: who changed which employee's shift assignment, from what, to what,
      when, and why. No updated_at — rows are never edited after insert.
      """

      __tablename__ = "shift_assignment_audits"

      id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
      care_delivery_program_master_id: Mapped[int] = mapped_column(
          ForeignKey("care_delivery_program_masters.id"), index=True)  # tenant
      employee_shift_assignment_id: Mapped[int] = mapped_column(
          ForeignKey("employee_shift_assignments.id"), index=True)
      employee_master_id: Mapped[int] = mapped_column(ForeignKey("employee_masters.id"), index=True)
      assignment_date: Mapped[date] = mapped_column(Date)
      old_shift_master_id: Mapped[int | None] = mapped_column(ForeignKey("shift_masters.id"))
      new_shift_master_id: Mapped[int | None] = mapped_column(ForeignKey("shift_masters.id"))
      action: Mapped[str] = mapped_column(String(30))  # ASSIGNED | CHANGED | CANCELLED
      performed_by_id: Mapped[int] = mapped_column(BigInteger)
      reason: Mapped[str | None] = mapped_column(String(500))
      created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
  ```

### Edited
- `backend/app/models/__init__.py` — add, next to the existing shift imports (~line 32):
  ```python
  from app.models.employee_shift_assignment import EmployeeShiftAssignment  # noqa: F401
  from app.models.shift_assignment_audit import ShiftAssignmentAudit  # noqa: F401
  ```
- `backend/app/models/shift_master.py` — add one nullable-with-default column, placed after
  `end_time` (an identity/definitional column, like start/end time) and before the
  `policy_config` JSONB comment block:
  ```python
  is_day_off: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
  ```
- `backend/app/modules/shifts/schemas.py` — add `is_day_off: bool = False` to `ShiftIn` (no
  validator needed, plain bool), `is_day_off: bool | None = None` to `ShiftPatch`, and
  `is_day_off: bool` to `ShiftOut`.
- `backend/app/modules/shifts/service.py` — `create_shift`: pass `is_day_off=payload.is_day_off`
  into the `ShiftMaster(...)` constructor. `update_shift`: `is_day_off` is a plain top-level column
  (not in `_POLICY_FIELDS`), so the existing `for field, value in data.items(): ... else:
  setattr(shift, field, value)` branch already handles it once it's a real column — no code change
  needed there beyond the column existing. `_shift_out`: add `is_day_off=shift.is_day_off` to the
  returned `ShiftOut(...)`.
- `backend/app/tests/modules/test_shifts.py` — add one small test: creating a shift with
  `is_day_off: true` round-trips `true` on the list response; a shift created without it defaults
  to `false`.

## Migration

Run from the repo root, per `CLAUDE.md`'s nhforms migration workflow (never bare
`alembic`/`uv run` — the private-package two-head rule):

```bash
docker compose exec api python scripts/migrate.py revision --autogenerate -m "add employee_shift_assignments, shift_assignment_audits, shift_masters.is_day_off"
# review the generated file:
#   - two new tables with their FKs/unique constraint/indexes exactly as modeled above
#   - one new nullable-with-server-default column on shift_masters
#   - no accidental DROP of unrelated tables (nhforms' metadata is merged in alembic/env.py)
docker compose exec api python scripts/migrate.py upgrade heads
```

## Acceptance criteria

- [x] `employee_shift_assignments` and `shift_assignment_audits` tables exist with the exact
      columns/FKs/constraints above; `shift_masters.is_day_off` exists, nullable-with-default
      `false`. (Migration `c8e1f3d91586` reviewed before applying — matched the spec exactly, no
      unrelated DROPs.)
- [x] Migration applies cleanly via `docker compose exec api python scripts/migrate.py upgrade heads`.
      Note: generating the migration first failed with `Can't locate revision '0b8b15797b78'` —
      this branch was 4 commits behind `origin/main` and missing a migration file the shared
      remote dev DB (`45.198.59.197`) had already applied. Resolved (with user confirmation) by
      stashing in-progress changes, fast-forward merging `origin/main` (clean, no conflicts beyond
      an auto-mergeable `app/models/__init__.py`), and popping the stash back — unrelated to this
      task's schema itself.
- [x] `docker compose up --force-recreate -d api` starts with no import errors (both new models
      registered in `app/models/__init__.py`).
- [x] `ShiftIn`/`ShiftPatch`/`ShiftOut` expose `is_day_off`; creating a shift with
      `is_day_off: true` round-trips correctly; omitting it defaults to `false`.
- [x] Full `test_shifts.py` suite passes (33/33), including the new `is_day_off` test.
- [x] `employee_shift_details`, its model file, and its existing `/api/v1/shifts/employee-shifts*`
      / `/api/v1/shifts/team/employee-shifts` endpoints are untouched — confirmed via `git diff`
      touching only the files listed above.
- [x] No frontend files touched — this is a backend-only schema/API change.
- [x] Full backend suite (`uv run pytest` equivalent, via `docker compose exec api python -m
      pytest`): 198 passed, 2 failed — the 2 failures
      (`test_engagement_email.py::test_send_email_ok`,
      `::test_send_email_resolves_template_variables`) are the same pre-existing, unrelated
      failures already noted in task 12's completion record (a `ChatRoom`/`ChatMessage` lookup
      issue in the engagement module), confirmed untouched by this task's `git diff`.

Completed: 2026-08-17
