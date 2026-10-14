---
task: 09
title: Shift-level overrides for missing-punch policy and overtime tracking
status: done
depends_on: []
---

# 09 — Shift-level overrides for missing-punch policy and overtime tracking

## Discussion

A Shift Configuration screen mockup (list of shifts + an "Attendance defaults · Morning" edit
panel) showed timing/break/grace fields already on `ShiftMaster`, plus three fields tagged
"inherited" that today are **tenant-wide only**, with no per-shift override:

- `week_off_days` (S M T W T F S toggle)
- `missing_punch_policy`
- `overtime_tracking_enabled`

Decided during the mockup walkthrough (2026-08-12):

1. **`missing_punch_policy` and `overtime_tracking_enabled` become per-shift override columns**
   on `shift_masters`, nullable, `NULL` = "inherit the tenant default from
   `GET /api/v1/attendance/config`". This task adds those two columns.
2. **Week-off inheritance needs no backend change.** `shift_week_off_details` already returns
   an empty list for a shift with no rows (`list_week_offs` in `service.py`) — "no rows" already
   *is* "inherited". The simple flat S–S toggle in the mockup just writes plain
   `day_of_week` rows (`week_of_month = NULL`) into the existing table; it does not replace or
   duplicate it. Showing the tenant's `default_week_off_days` with an "inherited" badge when a
   shift has zero rows is a **frontend** concern (it already has both values available: the
   shift's own `week_off_count`/rows and the tenant config) — not addressed by this task, and
   should not require a backend change when the frontend CRUD screen is built.
3. **Resolution (`override ?? tenant_default`) happens client-side, not server-side.** The API
   returns the raw nullable override only. This mirrors how this codebase already resolves other
   "NULL = inherit/all" columns (e.g. `holiday_calendar_masters.work_location_master_id NULL` =
   all locations) at the call site rather than baking a resolution join into every read. Keeps
   `ShiftOut` simple and avoids coupling the shifts endpoint to the config endpoint.

**Open question, not blocking this task:** the mockup's display label for `missing_punch_policy`
was "Needs regularization", which matches **neither** of the two values this knob currently
supports (`ZeroWorked | CapAtShiftEnd`, per
[05 §5.6](../../docs/leave-and-attendance/05-attendance-assembler.md)). Either the mockup's copy
is provisional/mislabeled, or product wants a third value. This task keeps the existing
two-value vocabulary (`extra`/unknown values still rejected) — resolve the label question before
building the frontend dropdown for this field, not before shipping this schema change.

## Scope

Backend only — model, migration, schema, service, tests. No frontend work (tracked separately
whenever the Shift Configuration CRUD screen itself is built).

### 1. Model — `backend/app/models/shift_master.py`

Add two nullable columns, no `server_default` (per `CLAUDE.md`'s convention: nullable columns
don't get one — `NULL` here is a meaningful third state, not "unset defaults to X"):

```python
missing_punch_policy: Mapped[str | None] = mapped_column(String(30))  # NULL = inherit tenant default
overtime_tracking_enabled: Mapped[bool | None] = mapped_column(Boolean)  # NULL = inherit tenant default
```

Place them after `is_flexible` (the other config-behavior column) and before the audit/lifecycle
columns, matching the file's existing column ordering.

### 2. Migration

```bash
docker compose exec api python scripts/migrate.py revision --autogenerate -m "shift-level overrides for missing punch policy and overtime tracking"
# review the generated file — two nullable columns on shift_masters, no server_default, no data migration needed
docker compose exec api python scripts/migrate.py upgrade heads
```
Never bare `alembic upgrade head` (two-head rule, per `CLAUDE.md`'s nhforms section) and never
bare `uv run` on the host (CodeArtifact token isn't available there) — always through
`docker compose exec api`.

### 3. Schemas — `backend/app/modules/attendance/schemas.py`

Add to `ShiftIn`, `ShiftPatch`, and `ShiftOut`:

```python
missing_punch_policy: str | None = None
overtime_tracking_enabled: bool | None = None
```

Add a `field_validator` on `missing_punch_policy` for `ShiftIn`/`ShiftPatch`, mirroring the
existing `HolidayIn`/`HolidayPatch` `_valid_type` pattern already in this file: `None` is always
valid (means "inherit"); a non-`None` value must be in `{"ZeroWorked", "CapAtShiftEnd"}` or raise
`ValueError` (→ 422). Do not validate `overtime_tracking_enabled` beyond the `bool | None` type —
it has only two meaningful states plus "inherit".

### 4. Service — `backend/app/modules/attendance/service.py`

`create_shift`, `update_shift`, and `_shift_out` (~line 272) pass the two new fields straight
through like every other `ShiftIn`/`ShiftPatch` field already does — no inheritance/resolution
logic here (see Discussion §3). `ShiftPatch`'s `exclude_unset=True` semantics mean a `PATCH` that
doesn't mention a field leaves it untouched; explicitly patching a field to `null` clears an
override back to "inherited" — confirm this round-trips correctly (Pydantic distinguishes
"key absent" from "key present with value null" via `exclude_unset`).

### 5. Tests — `backend/app/tests/modules/test_attendance.py`

Add:
- Creating a shift without `missing_punch_policy`/`overtime_tracking_enabled` returns `None` for
  both on the response (inherited, no override).
- Creating/patching a shift with both fields set persists and round-trips them on a subsequent
  `GET`-equivalent (list/patch response).
- Patching `missing_punch_policy` to an invalid value (e.g. `"Foo"`) returns `422`; valid values
  `ZeroWorked` and `CapAtShiftEnd` both succeed.
- Patching an already-overridden shift's `missing_punch_policy` back to `null` clears the
  override (round-trips to `None` on the next read).

## Files

- `backend/app/models/shift_master.py`
- `backend/alembic/versions/<new>.py` (new migration)
- `backend/app/modules/attendance/schemas.py`
- `backend/app/modules/attendance/service.py`
- `backend/app/tests/modules/test_attendance.py`

## Acceptance criteria

- [x] `shift_masters` has nullable `missing_punch_policy` (varchar(30)) and
      `overtime_tracking_enabled` (boolean) columns; migration applies cleanly via
      `docker compose exec api python scripts/migrate.py upgrade heads`.
- [x] `ShiftIn`/`ShiftPatch`/`ShiftOut` expose both fields; an invalid `missing_punch_policy`
      value returns `422` on create and patch.
- [x] A shift created without either field returns `None` for both (inherited); setting and
      later clearing (`null`) an override round-trips correctly.
- [x] Full `test_attendance.py` suite passes, including the new cases above. (37 passed; the
      3 pre-existing `test_config_*` failures are task 07's known in-flight gap —
      `attendance_leave_config_details`' migration is applied but `service.py`'s config
      endpoints aren't rewired onto it yet — unrelated to and untouched by this task.)
- [x] `docker compose up --force-recreate -d api` starts without import errors.
- [x] No frontend files touched — this is a backend-only schema/API change.

Completed: 2026-08-12
