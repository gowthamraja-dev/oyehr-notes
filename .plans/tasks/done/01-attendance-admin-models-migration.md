---
task: 01
title: Attendance admin-config models + migration
status: done
depends_on: []
---

# 01 — Attendance admin-config models + migration

Part of the Attendance admin-config backend slice (see
`docs/leave-and-attendance/` for the full module spec; this task builds only the 6
admin-config tables, not the full 16-table module — leave and device/punch tables are
separate future tasks).

## Scope

Six new SQLAlchemy models (one file each, per `CLAUDE.md`'s one-file-per-table rule),
registered in `app/models/__init__.py`, plus the Alembic migration that creates them.
DDL is verbatim from `.design/sql/Attendance & Leave/HRMS.sql` lines 55–169.

## Files

`backend/app/models/`:

| File | Class | Table |
|---|---|---|
| `work_location_master.py` | `WorkLocationMaster` | `work_location_masters` |
| `shift_master.py` | `ShiftMaster` | `shift_masters` |
| `shift_week_off_detail.py` | `ShiftWeekOffDetail` | `shift_week_off_details` |
| `holiday_calendar_master.py` | `HolidayCalendarMaster` | `holiday_calendar_masters` |
| `holiday_detail.py` | `HolidayDetail` | `holiday_details` |
| `employee_shift_detail.py` | `EmployeeShiftDetail` | `employee_shift_details` |

All six carry `care_delivery_program_master_id: Mapped[int]` (FK
`care_delivery_program_masters.id`, indexed — the tenant), matching
`app/models/employee_master.py`'s `Mapped`/`mapped_column`/`server_default=text(...)` style.

**`work_location_masters`**: `corp_master_id` (FK `corp_masters.id`, NOT NULL), `name`
(String(120) NOT NULL), `code` (String(50), nullable), `time_zone` (String(64) NOT NULL,
`server_default=text("'Asia/Kolkata'")`), `lttd`/`lgtd` (`Numeric(10,7)`, nullable),
`geo_fence_radius_mtrs` (Integer, nullable), `is_active`, `effctv_dt`/`trmntn_dt` (Date,
nullable), `archive`, `archived_by_id`/`archived_at`, `created_by_id`/`updated_by_id`,
`created_at`/`updated_at`. Add the read-only polymorphic collection like
`EmployeeMaster.address_details`:
`address_details: Mapped[list["AddressDetail"]] = polymorphic_children("AddressDetail", owner="WorkLocationMaster", via="addressable")`.

**`shift_masters`**: `name` (String(120) NOT NULL), `code` (String(50), nullable),
`start_time`/`end_time` (`sqlalchemy.Time`, NOT NULL — first use of `Time` in this codebase),
`is_night_shift` (Boolean, `server_default=text("false")`), `break_minutes`,
`grace_in_minutes`, `grace_out_minutes` (Integer, `server_default=text("0")`),
`min_full_day_minutes`/`min_half_day_minutes`/`ot_after_minutes` (Integer, nullable),
`is_flexible` (Boolean, `server_default=text("false")`), `is_active`, `effctv_dt`/`trmntn_dt`,
`archive`, `archived_by_id`/`archived_at`, `created_by_id`/`updated_by_id`,
`created_at`/`updated_at`.

**`shift_week_off_details`**: `shift_master_id` (FK `shift_masters.id`, NOT NULL, indexed),
`day_of_week` (Integer NOT NULL — ISO 1=Mon..7=Sun), `week_of_month` (Integer, nullable),
`is_half_day` (Boolean, `server_default=text("false")`), `is_active`, `archive`,
`created_by_id`/`updated_by_id`, `created_at`/`updated_at`. **No** `effctv_dt`/`trmntn_dt`/
`archived_*` — matches the SQL exactly (whole-set-replaced, not soft-archived per row).

**`holiday_calendar_masters`**: `name` (String(120) NOT NULL), `year` (Integer NOT NULL),
`work_location_master_id` (FK `work_location_masters.id`, nullable — NULL = all locations),
`is_active`, `effctv_dt`/`trmntn_dt`, `archive`, `archived_by_id`/`archived_at`,
`created_by_id`/`updated_by_id`, `created_at`/`updated_at`.

**`holiday_details`**: `holiday_calendar_master_id` (FK `holiday_calendar_masters.id`, NOT
NULL), `holiday_date` (Date NOT NULL), `name` (String(255) NOT NULL), `holiday_type`
(String(30) NOT NULL, `server_default=text("'Public'")`), `is_active`, `archive`,
`created_by_id`/`updated_by_id`, `created_at`/`updated_at`. `__table_args__` includes
`UniqueConstraint("holiday_calendar_master_id", "holiday_date", name="uq_holiday_details_calendar_date")`.

**`employee_shift_details`**: `employee_master_id` (FK `employee_masters.id`, NOT NULL),
`shift_master_id` (FK `shift_masters.id`, NOT NULL), `work_location_master_id`/
`holiday_calendar_master_id` (nullable FKs), `effctv_dt` (Date NOT NULL), `trmntn_dt` (Date,
nullable — NULL = current), `is_active`, `archive`, `archived_by_id`/`archived_at`,
`created_by_id`/`updated_by_id`, `created_at`/`updated_at`. `__table_args__` includes
`Index("ix_employee_shift_details_employee_effctv", "employee_master_id", "effctv_dt")`.

`app/models/__init__.py` — append after the existing employee/corp block, `shift_masters`
before `shift_week_off_details`/`employee_shift_details`, `work_location_masters` before
`holiday_calendar_masters`/`employee_shift_details`:
```python
from app.models.work_location_master import WorkLocationMaster  # noqa: F401
from app.models.shift_master import ShiftMaster  # noqa: F401
from app.models.shift_week_off_detail import ShiftWeekOffDetail  # noqa: F401
from app.models.holiday_calendar_master import HolidayCalendarMaster  # noqa: F401
from app.models.holiday_detail import HolidayDetail  # noqa: F401
from app.models.employee_shift_detail import EmployeeShiftDetail  # noqa: F401
```

Migration:
```bash
cd backend
uv run python scripts/migrate.py revision --autogenerate -m "attendance admin config tables"
# review alembic/versions/<new>.py — indexes/constraints from __table_args__ above should
# already be present via autogenerate, no hand-editing expected for these 6 tables
uv run python scripts/migrate.py upgrade heads   # never bare `alembic`
```

## Acceptance criteria

- [x] All 6 model files created, columns match the SQL sketch exactly, registered in
      `models/__init__.py`.
- [x] `uq_holiday_details_calendar_date` and `ix_employee_shift_details_employee_effctv`
      appear in the generated migration.
- [x] `python scripts/migrate.py upgrade heads` applies cleanly against the local `db`
      compose service (`postgresql+psycopg://hrms:hrms@db:5432/hrms_dev` from inside the
      `api` container — host-side `uv run` is blocked by the known CodeArtifact/nhforms
      401, so migrations run via `docker compose exec api python scripts/migrate.py ...`).
- [x] `docker compose up --force-recreate -d api` starts without import errors; all 6
      tables confirmed present via `psql \dt`.

Completed: 2026-08-11
