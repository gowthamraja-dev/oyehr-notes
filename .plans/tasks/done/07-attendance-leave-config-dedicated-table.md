---
task: 07
title: Attendance/leave config — dedicated typed table replacing the EAV parameter rows
status: abandoned
depends_on: [1]
---

# 07 — Attendance/leave config — dedicated typed table replacing the EAV parameter rows

## Abandoned (2026-08-18)

Never executed — no code in this file was built. Filed here (not left in `ongoing/`) so it stops
showing up as pickable work, but it is **not** a completed/verified unit per this tracker's own
`done/` convention; every acceptance box below is still unchecked. Originally deferred on
2026-08-17 as unrelated to the Shift Assignment Manager/Employee UI work that session was scoped
to. Its own "Discussion" section below already flags that this task's original premise doesn't
match the live codebase (no EAV-backed `/attendance/config` route or `tenant_params.py` module
ever existed as described; 8 of its ~17 knobs shipped a different way, as per-shift override
columns on `shift_masters`) and needs a full re-scope before anyone executes it. If this work is
picked up later, treat it as a new task file re-derived from the Discussion below, not a resume
of this one.

## Discussion

> **Flag — verify before executing.** This section's premise was checked against the live
> codebase during the `docs/leave-and-attendance/` restructuring (2026-08-14) and does not match
> reality: `backend/app/services/tenant_params.py` does not exist (only a stale `.pyc` is present),
> there is no `GET/PUT /api/v1/attendance/config` route in `attendance/router.py`, and there is no
> `AttendanceConfigOut`/`UpdateAttendanceConfigRequest` in `attendance/schemas.py`. This EAV-backed
> `/config` endpoint was never built. Instead, 8 of the ~17 knobs this task describes moving
> (`missing_punch_policy`, `overtime_tracking_enabled`, `regularization_window_days`,
> `max_regularization_requests_per_month`, `regularization_approver`, `late_marks_per_half_day`,
> `late_mark_reset_cycle`, `notify_on_late_mark`) already shipped a different way — as **per-shift
> override columns directly on `shift_masters`** (see `docs/leave-and-attendance/shifts/admin-configuration.md`
> and `docs/leave-and-attendance/shared/tenant-config-storage.md`). Re-scope this task against that
> reality before executing — decide whether the dedicated table below still makes sense for the
> remaining ~9 knobs that never got a per-shift equivalent, whether it should also subsume/replace
> the per-shift columns, or something else — rather than running it as "replace the EAV table",
> since there is no EAV table live for these knobs today.

The attendance admin-config screen (`GET/PUT /api/v1/attendance/config`) currently stores its
~17 tenant knobs (`regularization_window_days`, `auto_absent_days`, `default_week_off_days`, …)
as rows in the generic EAV table `care_delivery_program_parameter_details`, keyed by hardcoded
`parameter_masters.id` values 300-349 (`app/services/tenant_params.py`'s `PARAM_IDS`). This task
replaces that with a dedicated typed table.

**Why**: the current database model has no dedicated config table for attendance at all. Every
knob is a generic `int_val`/`str_val` row identified only by a hardcoded numeric id that every
reader has to already know out-of-band — no schema to read, no `NOT NULL`/type constraint, no way
to `\d` the table and see what a tenant can configure.

`leave_policy_details` (already in `.design/sql/Attendance & Leave/HRMS.sql`, not yet built in the
backend) looks like a natural template, but it's different in kind, not just in table-vs-EAV: it's
**keyed per leave type** (`leave_type_master_id`/`corp_master_id`/`employee_type_master_id`)
because accrual genuinely varies by leave type ("Split from leave_type_masters because accrual
varies by employee type / corp within one leave type" — its own table comment). Pulling up "the
leave configuration" there means pulling up the row(s) for a given leave type, not one flat
tenant-wide row.

The knobs this task moves (attendance policy, defaults, assembler tuning, tenant-wide leave
settings like `leave_year_start_month`, operations, comp-off — doc `09`'s §1.1-§1.6) are **not**
per-leave-type — they're exactly one scalar per tenant. So the right analog isn't "add columns to
`leave_policy_details`" (wrong cardinality: that table is 1+ rows per leave type, this data is 1
row per tenant); it's "give tenant-wide config the same treatment `leave_policy_details` gives
per-leave-type config: a real table with typed columns, instead of a numbered EAV row."

This is a deliberate deviation from what's currently documented — `docs/leave-and-attendance/09-`,
`12-`, and `14-*.md` all explicitly state these knobs belong in
`care_delivery_program_parameter_details`, split only by *router ownership*, never by table
("Two routers share this one accessor but serve disjoint key sets... they all live in the same
table" — `14-config-knob-reference.md`). There is no dedicated attendance-config table anywhere in
`.design/sql/...HRMS.sql` — this is net-new design, not a documented-but-unbuilt one. Scope here
covers the full ~35-knob catalogue from doc `09` §1.1-§1.6 in one table, not just the 16 knobs with
a live endpoint today, so the table doesn't need a second migration when leave/assembler-tuning/ops
modules eventually claim their columns.

## Scope

Everything below is one unit: new model + migration, the `/attendance/config` rewrite onto it, and
the doc updates that follow from the storage change. Not in scope: exposing any of the
non-attendance columns (leave policy, assembler tuning beyond `missing_punch_policy`, ops beyond
`attendance_cutoff_day`, comp-off) through any endpoint — no `leave` module exists yet
(`backend/app/modules/leave/` does not exist), so those columns just sit ready with defaults until
a future task wires a router to them.

### 1. New model + migration

`backend/app/models/attendance_leave_config_detail.py` → class `AttendanceLeaveConfigDetail` →
table `attendance_leave_config_details`. **One row per tenant**: `care_delivery_program_master_id`
FK to `care_delivery_program_masters.id`, with a `UniqueConstraint` on it — a singleton-per-CDP
config row, explicitly not shaped like `leave_policy_details` (see Discussion above).

Columns (typed per `CLAUDE.md`'s conventions — non-null with a default uses `server_default`,
nullable uses `Mapped[T | None]`), grouped by doc `09`'s §1 sections (id-block noted per group for
traceability only — these ids stop existing as DB values once this migration lands):

- **§1.1 Attendance policy** (was ids 300-309): `regularization_window_days` (Integer, NOT NULL,
  default 7 — **DB column stays a plain `Integer`, no CHECK constraint**, but see the schemas.py
  note below: the API layer constrains it to `3`/`7`/`15`), `max_regularization_requests_per_month`
  (Integer, NOT NULL, default 3), `regularization_approver` (String(30), NOT NULL, default
  `'ReportingManager'` — again plain at the DB layer, constrained at the API layer),
  `auto_absent_days` (Integer, NOT NULL, default 1), `late_marks_per_half_day` (Integer, NOT NULL,
  default 3), `late_mark_reset_cycle` (String(20), NOT NULL, default `'Monthly'`),
  `notify_on_late_mark` (Boolean, NOT NULL, default true), `overtime_tracking_enabled` (Boolean,
  NOT NULL, default true), `ot_on_non_working_days` (Boolean, NOT NULL, default true),
  `short_day_status` (String(30), NOT NULL, default `'Absent'`).
- **§1.2 Defaults** (was ids 310-316): `default_shift_master_id` (nullable BigInteger, FK
  `shift_masters.id`), `default_week_off_days` (**`ARRAY(Integer)` via
  `sqlalchemy.dialects.postgresql.ARRAY`, `Mapped[list[int]]`, NOT NULL, default `[6, 7]`** —
  replaces the CSV-string-in-a-text-column hack `tenant_params.py`/`_parse_week_off_days` needed
  only because EAV forced everything through `str_val`; a real column can just be a native array),
  `default_full_day_minutes` (Integer, NOT NULL, default 510), `default_half_day_minutes`
  (Integer, NOT NULL, default 270), `default_grace_in_minutes` (Integer, NOT NULL, default 10),
  `default_work_location_master_id` (nullable BigInteger, FK `work_location_masters.id`),
  `default_time_zone` (String(64), NOT NULL, default `'Asia/Kolkata'`).
- **§1.3 Assembler tuning** (was ids 320-325): `missing_punch_policy` (String(30), NOT NULL,
  default `'ZeroWorked'`), `attendance_rebuild_window_days` (Integer, NOT NULL, default 7),
  `punch_attribution_window_before_minutes` (Integer, NOT NULL, default 240),
  `punch_attribution_window_after_minutes` (Integer, NOT NULL, default 240),
  `punch_debounce_seconds` (Integer, NOT NULL, default 60), `max_worked_minutes_per_day` (Integer,
  NOT NULL, default 1440).
- **§1.4 Leave policy** (was ids 330-335) — tenant-wide leave defaults, distinct from
  `leave_policy_details`'s per-leave-type accrual columns: `leave_year_start_month` (Integer, NOT
  NULL, default 4), `accrual_rounding` (String(20), NOT NULL, default `'NearestHalf'`),
  `accrue_during_probation` (Boolean, NOT NULL, default true), `allow_retro_leave_cancellation`
  (Boolean, NOT NULL, default false), `max_backdated_leave_days` (Integer, NOT NULL, default 0),
  `fallback_approver_user_id` (nullable BigInteger, FK `users.id`).
- **§1.5 Operations** (was ids 340-343): `attendance_cutoff_day` (Integer, NOT NULL, default 25),
  `attendance_log_retention_months` (Integer, NOT NULL, default 24),
  `device_heartbeat_alert_minutes` (Integer, NOT NULL, default 60), `geofence_enforcement`
  (String(10), NOT NULL, default `'Warn'` — valid values `Off|Warn|Block`, no DB `CHECK`
  constraint, matches this codebase's existing convention of leaving enum-like strings
  unconstrained at the DB layer).
- **§1.6 Comp-off** (was ids 345-346): `comp_off_expiry_days` (Integer, NOT NULL, default 60),
  `comp_off_min_worked_minutes` (**nullable Integer, no server default** — doc `09` defines it as
  "= `min_half_day_minutes`", a dynamic fallback to another column that a static `server_default`
  can't express; resolve it at read time in the service layer as
  `row.comp_off_min_worked_minutes or row.default_half_day_minutes`, not in the model/migration).
- Audit columns (standard across this codebase's detail tables): `created_by_id`/`updated_by_id`
  (nullable BigInteger, FK `users.id`), `created_at`/`updated_at` (`DateTime(timezone=True)`,
  `server_default=func.now()`, `updated_at` also gets `onupdate=func.now()`).

Register in `app/models/__init__.py` per the existing import-ordering convention (append after the
attendance-admin block from task 01).

Migration:
```bash
cd backend
uv run python scripts/migrate.py revision --autogenerate -m "attendance leave config dedicated table"
# review the generated file — the UniqueConstraint on care_delivery_program_master_id and the
# ARRAY(Integer) column should be present; hand-add the cleanup statement below, autogenerate
# won't produce it
uv run python scripts/migrate.py upgrade heads   # never bare `alembic`
```
In `upgrade()`, after `op.create_table(...)`, hand-add:
```python
op.execute("DELETE FROM parameter_masters WHERE id BETWEEN 300 AND 349")
op.execute(
    "DELETE FROM care_delivery_program_parameter_details WHERE parameter_master_id BETWEEN 300 AND 349"
)
```
This is safe because nothing else in the codebase uses ids 300-349 — confirmed during exploration:
`organizations/service.py`, `public/service.py`, `forms/branding.py` use theme ids 51/52/57;
`engagement/service.py`/`webhooks/service.py` use WhatsApp id 208 via a different model
(`PartnerParameterMaster`). Per task 01/05's noted host-side CodeArtifact-auth limitation, run
migrations via `docker compose exec api python scripts/migrate.py ...`, not bare `uv run` on the
host.

### 2. Rewire `/attendance/config` onto the new table

`backend/app/modules/attendance/service.py`:
- Replace `get_config`/`update_config`'s calls into `tenant_params.get_int`/`get_str`/`get_bool`/
  `upsert` with a `_get_or_create_row(db, cdp_id) -> AttendanceLeaveConfigDetail` helper: look up
  by `care_delivery_program_master_id`; if missing, `db.add(AttendanceLeaveConfigDetail(care_delivery_program_master_id=cdp_id))`
  then `db.flush()` so column defaults populate from the DB — mirrors `tenant_params.upsert`'s
  lazy-row-creation so the API contract (defaults on first GET, no pre-seeding required) is
  unchanged.
- `get_config` maps the row's 16 attendance-owned columns straight onto `AttendanceConfigOut` — no
  more per-field accessor calls, no more `_parse_week_off_days` (the `ARRAY(Integer)` column
  already returns a `list[int]`).
- `update_config` does a `setattr(row, name, value)` loop over
  `payload.model_dump(exclude_unset=True).items()`, keeps the existing validation that
  `default_week_off_days` entries are 1-7, `db.commit()`, returns `get_config(db, principal)`.
- **No new fields on the API surface**: `AttendanceConfigOut`/`UpdateAttendanceConfigRequest` in
  `schemas.py` keep exactly today's 16 fields — the table has ~35 columns for future modules
  (leave, assembler tuning, ops, comp-off) to claim later; this task does not expose any of them
  through `/attendance/config`.
- **Two fields do get stricter validation**, decided during the admin-screen walkthrough (the
  current build has neither constraint — `regularization_window_days` accepts any int, and
  `regularization_approver` accepts any string, which is how the frontend ended up sending the
  wrong value `"HR"` instead of the documented `"HRAdmin"` with nothing catching it):
  - `regularization_window_days: int` → `Literal[3, 7, 15]` on `AttendanceConfigOut` and
    `Literal[3, 7, 15] | None = None` on `UpdateAttendanceConfigRequest` — matches
    `.design/Admin Console.dc.html`'s 3/7/15-day preset select exactly; a `PUT` with any other
    value now `422`s instead of silently accepting it.
  - `regularization_approver: str` → `Literal["ReportingManager", "HRAdmin"]` /
    `Literal["ReportingManager", "HRAdmin"] | None = None` — matches
    `scripts/seed_attendance_leave_masters.py`'s documented valid values; a `PUT` with `"HR"` (the
    value the live frontend currently sends — see task 06) now `422`s, surfacing the bug instead
    of silently persisting a value nothing else expects.

Delete (both existed solely to serve the EAV pattern this retires; confirmed no other module
imports either):
- `backend/app/services/tenant_params.py`
- `backend/scripts/seed_attendance_leave_masters.py`

`backend/app/tests/modules/test_attendance.py`: the existing config tests
(`test_config_defaults`, `test_config_partial_update_only_changes_supplied_keys`,
`test_config_can_update_approver_and_notify_toggle`, `test_config_unknown_key_rejected`,
`test_config_week_off_days_round_trips_as_list`, `test_encrypted_config_roundtrip`) only ever
exercise the API, not the EAV table directly — they should pass unchanged against the new storage.
Run them explicitly to confirm rather than assuming. Add one new test asserting a fresh CDP's row
is lazily created on first `GET` with no pre-seeding (matches current default-fallback behavior).

### 3. Docs

`docs/leave-and-attendance/` was restructured by domain on 2026-08-14; docs `09`, `12`, and `14`
no longer exist. Update **`docs/leave-and-attendance/shared/tenant-config-storage.md`** instead —
it now holds the framing rule, the accessor/storage-shape mechanics, and the "why fixed ids"
section that used to live across those three files. Replace its per-shift-override-reality
framing (added during the restructuring, per the flag above) with the dedicated-table description
once this task is re-scoped and executed — dropping the now-obsolete fixed-id-block rationale.
Also update `docs/leave-and-attendance/attendance/config-knobs.md` and
`docs/leave-and-attendance/leave/config-knobs.md`, which now hold the per-knob catalogues that
used to live in old docs `09`/`14`.

## Files

- `backend/app/models/attendance_leave_config_detail.py` (new)
- `backend/app/models/__init__.py` (register the new model)
- `backend/alembic/versions/<new>.py` (new migration)
- `backend/app/modules/attendance/service.py` (rewire `get_config`/`update_config`)
- `backend/app/modules/attendance/schemas.py` (tighten `regularization_window_days`/
  `regularization_approver` to `Literal` types)
- `backend/app/services/tenant_params.py` (delete)
- `backend/scripts/seed_attendance_leave_masters.py` (delete)
- `backend/app/tests/modules/test_attendance.py` (extend config tests)
- `docs/leave-and-attendance/shared/tenant-config-storage.md` (update storage description —
  replaces the old `09-`/`12-`/`14-*.md` targets, which no longer exist post-restructuring)
- `docs/leave-and-attendance/attendance/config-knobs.md`,
  `docs/leave-and-attendance/leave/config-knobs.md` (update per-knob catalogue)

## Acceptance criteria

- [ ] `attendance_leave_config_details` table exists with a unique constraint on
      `care_delivery_program_master_id`; migration applies cleanly via
      `scripts/migrate.py upgrade heads`.
- [ ] `parameter_masters` rows in id range 300-349 (and any
      `care_delivery_program_parameter_details` rows referencing them) are gone after the
      migration.
- [ ] `GET /api/v1/attendance/config` on a brand-new CDP with no prior row returns all 16 defaults
      correctly (lazy row creation verified) — no pre-seeding required.
- [ ] `PUT /api/v1/attendance/config` partial-update semantics (`exclude_unset=True`), the
      `default_week_off_days` 1-7 validation, the `extra="forbid"` 422 on unknown keys, and the
      encrypted round-trip all still work — full `test_attendance.py` passes, including the new
      lazy-row-creation test.
- [ ] `app/services/tenant_params.py` and `scripts/seed_attendance_leave_masters.py` are deleted
      with no dangling imports anywhere in the backend.
- [ ] `docs/leave-and-attendance/shared/tenant-config-storage.md`,
      `docs/leave-and-attendance/attendance/config-knobs.md`, and
      `docs/leave-and-attendance/leave/config-knobs.md` describe the dedicated table, not the EAV
      approach, for these knobs — and reconcile with the per-shift-override columns already live
      on `shift_masters` per the flag at the top of this task's Discussion.
- [ ] `PUT /api/v1/attendance/config` with `regularization_window_days` outside `{3,7,15}` or
      `regularization_approver` outside `{ReportingManager,HRAdmin}` returns `422`; valid values
      of both still round-trip correctly — add these as new test cases alongside the existing
      `test_config_unknown_key_rejected`.
- [ ] `docker compose up --force-recreate -d api` starts without import errors.
