---
task: 39
title: OFF status for per-date shift assignments (manual marking)
status: done
depends_on: []
---

# 39 — OFF status for per-date shift assignments

## Discussion

Closes the concrete complaint: in the Manager Portal's per-date roster
(`employee_shift_assignments` / `app/modules/shifts/service.py`), there is no first-class way to
mark a date as a day off. Today `status` is only `ASSIGNED | CANCELLED`
(`app/models/employee_shift_assignment.py`), and `shift_master_id` is `NOT NULL`, so the only
existing workaround is assigning a shift row that happens to have `is_day_off=true` — which
requires a tenant to have created such a shift and doesn't read as "this date is off" in the data
model itself.

**Found while reading the code, not asked for, but must be fixed as part of this task:**
`service.list_shift_assignments` filters `EmployeeShiftAssignment.status == "ASSIGNED"` when
building the roster grid's `assignments` list (around line 562). If we ship an `OFF` status
without touching this, every OFF row becomes silently invisible in `GET /shifts/assignments` —
the exact "empty result hides a real state" failure `README.md §3.3` warns about elsewhere in
this module, just for data instead of permissions. Fix: `.status.in_(["ASSIGNED", "OFF"])`.

**Deliberately out of scope — record as a new gap, don't silently leave it undiscoverable.**
`resolve_employee_shift` (also in `shifts/service.py`, shared with
`app/services/calendar_resolver_service.py` per `README.md §3.4`) only treats a per-date row with
`status == "ASSIGNED"` as an override; it is left untouched here. That means a manager marking a
date `OFF` on the roster does **not** flow into the employee's own `GET /shifts/me` "Today's
Shift" card or into attendance day-type resolution once the assembler is built — those keep
resolving from the employee's *standing* shift and its `ShiftWeekOffDetail` rules. This is the
same shape of problem as `docs/leave-and-attendance/shifts/gaps.md` #43/#44 (two/three consumers
of "what is this employee doing on this date" that can disagree), not a new kind of bug. Add a new
entry to that file (next number after #44 — check
`docs/leave-and-attendance/shared/gaps-cross-cutting.md` for the current global max before
numbering it) stating this explicitly, mirroring how #43/#44 themselves were recorded rather than
solved. Do not attempt to fix the ripple in this task — `resolve_employee_shift`'s return contract
change would cascade into `MyShiftOut`, `calendar_resolver_service.ResolvedShift`, and
`resolve_day_type`, which is a separate, larger unit of work if it's ever picked up.

## Files

### Edited

- `backend/app/models/employee_shift_assignment.py`
  - `shift_master_id: Mapped[int | None]` (was non-null) — `NULL` exactly when `status == "OFF"`.
  - `status` comment becomes `# ASSIGNED | OFF | CANCELLED`.
  - New column: `is_auto_assigned: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))`
    — distinguishes a manager's manual row from one written by the auto-assignment engine (task
    40), so that engine can re-run without ever clobbering a manual override. Not used by this
    task's own endpoints beyond always writing `False` on manual create/update.

- `backend/alembic/versions/<new>.py` — autogenerate, then hand-review:
  `ALTER COLUMN shift_master_id DROP NOT NULL`, `ADD COLUMN is_auto_assigned boolean NOT NULL
  DEFAULT false`. Pure DDL, no data migration needed (existing rows are all real assignments with
  a real shift, so backfilling `is_auto_assigned=false` via the server default is correct as-is).

- `backend/app/modules/shifts/schemas.py`
  ```python
  from typing import Literal
  from pydantic import model_validator

  class ShiftAssignmentIn(BaseModel):
      employee_master_id: int
      assignment_date: date
      status: Literal["ASSIGNED", "OFF"] = "ASSIGNED"
      shift_master_id: int | None = None  # required iff status == "ASSIGNED"
      note: str | None = Field(default=None, max_length=500)

      @model_validator(mode="after")
      def _shift_required_iff_assigned(self):
          if self.status == "ASSIGNED" and self.shift_master_id is None:
              raise ValueError("shift_master_id is required when status is ASSIGNED")
          if self.status == "OFF" and self.shift_master_id is not None:
              raise ValueError("shift_master_id must not be set when status is OFF")
          return self

  class ShiftAssignmentPatch(BaseModel):
      status: Literal["ASSIGNED", "OFF"] | None = None
      shift_master_id: int | None = None
      note: str | None = None
      # No cross-field validator here — PATCH is exclude_unset, partial by design (e.g. a
      # note-only patch sends neither status nor shift_master_id). The ASSIGNED<->OFF
      # cross-field rule is enforced in the service, where it can see the row's *current*
      # state, not just the patch body.

  class ShiftAssignmentOut(BaseModel):
      id: int
      employee_master_id: int
      assignment_date: date
      shift_master_id: int | None = None
      status: str
      is_auto_assigned: bool
      note: str | None = None
  ```
  `BulkShiftAssignmentIn` needs no change — it already wraps `list[ShiftAssignmentIn]`, so bulk
  gets OFF support for free once the service's per-item loop handles it (below).

- `backend/app/modules/shifts/service.py`
  - `create_shift_assignment`: branch on `payload.status`.
    ```python
    shift = None if payload.status == "OFF" else _require_active_shift(db, principal, payload.shift_master_id)
    ```
    then use `shift.id if shift else None` everywhere `payload.shift_master_id` was used for the
    new/reactivated row, and set `row.status = payload.status` instead of hardcoding
    `"ASSIGNED"`. The existing "already assigned" 409 guard
    (`if existing is not None and existing.status == "ASSIGNED"`) must widen to
    `existing.status in ("ASSIGNED", "OFF")` — creating on top of an already-`OFF` cell should
    409 too, forcing the caller through `update_shift_assignment` to make the change explicit
    (matches today's behavior for `ASSIGNED`-over-`ASSIGNED`).
  - `update_shift_assignment`: handle `status` explicitly instead of the current blanket
    `for field, value in data.items(): setattr(row, field, value)`:
    - `status` in `data` and `== "OFF"`: force `row.shift_master_id = None`; 422 if the same patch
      also included a non-null `shift_master_id` ("shift_master_id must not be set when status is
      OFF").
    - `status` in `data` and `== "ASSIGNED"` while `row.status` is currently `"OFF"`: require
      `shift_master_id` in the same patch (422 "shift_master_id is required to reassign from
      OFF"), validate it via `_require_active_shift`.
    - `shift_master_id` in `data` with no `status` key and `row.status == "OFF"`: same 422 as
      above — a bare shift_master_id patch can't silently resurrect an OFF row as ASSIGNED
      without the caller saying so.
    - Every manual write here — create, update, and the bulk loop below — sets
      `row.is_auto_assigned = False`, overwriting any prior auto-assigned flag (a manual edit
      always wins going forward; task 40's engine skips rows where this is `False`).
    - Audit action naming: reuse `_write_assignment_audit`'s existing action vocabulary, adding
      `"OFF"` as a fourth `action` value (column is an unconstrained `String`, so no migration
      needed) — `action = "OFF"` when the new status is `OFF`, `"ASSIGNED"` when transitioning
      OFF→ASSIGNED or reactivating from CANCELLED, `"CHANGED"` for an ASSIGNED→ASSIGNED shift swap
      (unchanged from today).
  - `bulk_assign_shifts`: mirror the same `status`-branching in its per-item validate loop and its
    write loop — do not duplicate the create/update logic verbatim; factor the "resolve `shift`
    from `payload.status`+`shift_master_id`, validate if not OFF" step into one small helper both
    `create_shift_assignment` and `bulk_assign_shifts` call (`update_shift_assignment` has
    different enough transition rules — OFF→ASSIGNED requiring an explicit shift — that it can
    stay separate, but pull the ASSIGNED/OFF conflict-check widening into a second shared helper
    if it turns out identical in both places).
  - `list_shift_assignments`: change the assignment-rows filter from
    `EmployeeShiftAssignment.status == "ASSIGNED"` to
    `EmployeeShiftAssignment.status.in_(["ASSIGNED", "OFF"])` (the bug fix noted above).

- `backend/app/modules/shifts/router.py` — no new routes; the existing `POST /shifts/assignments`,
  `PUT /shifts/assignments/{id}`, `POST /shifts/assignments/bulk` gain OFF support transparently
  through the schema change.

- `docs/leave-and-attendance/shifts/gaps.md` — add a new numbered entry (see Discussion) recording
  that per-date `OFF` overrides don't propagate into `resolve_employee_shift`/self-service/the
  attendance assembler.

- `backend/app/tests/modules/test_shifts.py` — extend with:
  - `POST /shifts/assignments` with `status: "OFF"` and no `shift_master_id` succeeds; the stored
    row has `shift_master_id IS NULL`.
  - `status: "OFF"` with a `shift_master_id` present → 422; `status: "ASSIGNED"` (or default) with
    no `shift_master_id` → 422.
  - `PUT /shifts/assignments/{id}` flips an `ASSIGNED` row to `OFF`, clearing `shift_master_id`,
    and writes an audit row with `action="OFF"`.
  - `PUT` flipping an `OFF` row back to `ASSIGNED` without a `shift_master_id` → 422; with one →
    succeeds, `is_auto_assigned` resets to `false`.
  - `POST /shifts/assignments` on a date that already has an `OFF` row → 409 (mirrors the existing
    ASSIGNED-over-ASSIGNED 409).
  - `GET /shifts/assignments` (the roster range query) includes `OFF` rows in its response —
    regression test for the visibility bug fix.
  - Manager can mark a direct report's date OFF; marking a non-report's date OFF is 403.
  - Encrypted round-trip test covering an OFF-status create.

## Implementation notes (decided/found during execution)

- **Shared helper instead of duplicating the OFF/ASSIGNED branch:** added
  `_resolve_assignment_shift(db, principal, status, shift_master_id) -> ShiftMaster | None` and
  used it from both `create_shift_assignment` and `bulk_assign_shifts`'s validate loop, per the
  task's own note not to duplicate that branch verbatim.
- **`update_shift_assignment` rewrite:** replaced the old blanket
  `for field, value in data.items(): setattr(row, field, value)` with explicit handling: `status`
  is popped out of `data` first (`target_status = data.pop("status", "ASSIGNED" if was_cancelled
  else old_status)`), the OFF/ASSIGNED cross-field rule is enforced against `target_status` before
  any field is set, and only then does the generic per-field loop run over what's left in `data`
  (just `shift_master_id`/`note` at that point). `is_auto_assigned` is unconditionally reset to
  `False` on every manual update, per the task's design (a manual edit always wins over a future
  auto-assigned flag).
- **Audit action naming ended up simpler than "OFF→ASSIGNED or reactivating from CANCELLED, CHANGED
  for a swap"**: settled on three buckets — `"OFF"` whenever the target status is `OFF`,
  `"ASSIGNED"` when reactivating from `CANCELLED` or from `OFF`, `"CHANGED"` otherwise (covers both
  a shift swap and a note-only edit on an already-`ASSIGNED` row, matching the pre-existing
  behavior where a note-only patch also got `"CHANGED"`).
- Migration generated with `uv run python scripts/migrate.py revision --autogenerate` (per
  CLAUDE.md — a bare `alembic revision` can't see the nhforms branch and errors on multiple
  heads), reviewed, and applied with `scripts/migrate.py upgrade heads`. Pure DDL as expected: one
  `ALTER COLUMN shift_master_id DROP NOT NULL`, one `ADD COLUMN is_auto_assigned`.
- Gap `#45` added to `docs/leave-and-attendance/shifts/gaps.md` (next number after the existing
  #43/#44), plus that file's own `#2, #3, #20, #43, #44` index line updated to include it.

## Acceptance criteria

- [x] `employee_shift_assignments.shift_master_id` is nullable; `is_auto_assigned` column exists;
      migration applies cleanly on a fresh dev DB (`uv run alembic upgrade head`).
- [x] Manager or admin can mark a specific employee/date as `OFF` through the existing
      create/update/bulk endpoints, with no `shift_master_id` stored.
- [x] Marking a date back to `ASSIGNED` from `OFF` requires an explicit `shift_master_id`; the API
      never leaves a row in an inconsistent `status`/`shift_master_id` combination.
- [x] `GET /shifts/assignments` returns `OFF` rows (fixes the silent-filter bug) — covered by
      `test_list_shift_assignments_includes_off_rows`.
- [x] Every manual write sets `is_auto_assigned=false`; the audit trail records an `"OFF"` action
      distinct from `"CHANGED"`/`"CANCELLED"`/`"ASSIGNED"` —
      `test_update_assigned_to_off_clears_shift_and_writes_audit`.
- [x] New gap entry (#45) added to `docs/leave-and-attendance/shifts/gaps.md` documenting the
      self-service/assembler non-propagation.
- [x] `test_shifts.py`: 73 passed. Full backend suite: 350 passed, 3 failed — the same
      pre-existing, unrelated failures already on record from task 33's completion notes
      (`test_engagement_email.py::test_send_email_ok`,
      `test_engagement_email.py::test_send_email_resolves_template_variables`,
      `test_leave.py::test_audit_written_on_success_and_not_on_rejection`); confirmed via `git
      status` that none of those modules' files were touched by this task.

Completed: 2026-08-18
