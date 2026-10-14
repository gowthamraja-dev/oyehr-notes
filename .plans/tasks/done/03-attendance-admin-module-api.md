---
task: 03
title: Attendance admin module — router/service/schemas
status: done
depends_on: [1, 2]
---

# 03 — Attendance admin module — router/service/schemas

Part of the Attendance admin-config backend slice. Builds the actual API surface over the
Task 01 models and Task 02 knob accessor.

## Scope

`backend/app/modules/attendance/` — admin-only CRUD for work locations, shifts + week-offs,
holiday calendars + holidays (+ CSV import), employee shift assignment, and the tenant
config endpoint. **No leave endpoints, no devices/punches, no frontend** — those are separate
future tasks.

**Auth**: every endpoint in this task requires `principal.is_admin` (see the parent plan's
"Auth simplification" note — the `hr_manager`/`hr_employee` dashboards don't exist yet, so
there's no manager/self target to differentiate for these tenant-wide master tables; loosen
this when those dashboards are built).

## Files

```
backend/app/modules/attendance/
├── __init__.py
├── router.py     # `router` (EncryptedRoute, JSON) + `_upload_router` (plain, CSV import),
│                 # both mounted via `include_in(api_router)` — mirrors
│                 # app/modules/organizations/router.py exactly
├── schemas.py
└── service.py
```

### `service.py`

```python
def _require_admin(principal: AuthPrincipal) -> None:
    if not principal.tenant_id:
        raise PermissionDenied("No tenant in token")
    if not principal.is_admin:
        raise PermissionDenied("Admin only")
```
Called first by every function below. CDP scoping is a direct
`.where(Model.care_delivery_program_master_id == principal.tenant_id)` — these 6 tables carry
the tenant column directly, unlike `employee_masters` (no join through `corp_masters` needed
for them; the join IS needed when validating an `employee_master_id` input, e.g. in
employee-shifts — see `app/modules/employees/service.py:31-39` for that pattern).

**Work locations** — `GET/POST /work-locations`, `GET/PATCH/DELETE /work-locations/{id}`:
- Create/update validates `corp_master_id` resolves to a `CorpMaster` with
  `care_delivery_program_master_id == principal.tenant_id` (else `NotFound`).
- Validate `time_zone` via `zoneinfo.ZoneInfo(name)` in try/except → `422` on unknown zone.
- Detail includes address via
  `select(AddressDetail).where(addressable_type=="WorkLocationMaster", addressable_id==id)`
  (mirrors `organizations/service.py`'s `_current_address`). Create/update accept optional
  nested `address: AddressIn | None`, written with `AddressDetail.for_owner(location, ...)`
  after the location row is flushed.
- `DELETE` sets `archive=True`, `archived_by_id`, `archived_at` (**not** `is_active=False`
  — this module's convention, distinct from organizations'). Lists filter `archive == False`.

**Shifts** — `GET/POST /shifts`, `PATCH/DELETE /shifts/{id}`, `GET/PUT /shifts/{id}/week-offs`:
- Validate `is_night_shift == (end_time <= start_time)` exactly — `422` on mismatch, never
  silently infer. Validate `min_half_day_minutes < min_full_day_minutes` when both set.
- `GET /shifts` list includes a `week_off_count` per shift.
- `PUT .../week-offs` is a whole-set replace: delete existing `ShiftWeekOffDetail` rows for
  the shift, insert the new set, one transaction. Validate `day_of_week` ∈ 1–7,
  `week_of_month` ∈ {None, 1, 2, 3, 4, 5} per row → `422` otherwise. `week_of_month` is the
  Nth occurrence of that weekday in the month, **not** the ISO calendar week — this task only
  stores/validates the rule, no date math needed here.

**Holiday calendars & holidays**:
- `GET /holiday-calendars?year=&work_location_master_id=`, `POST /holiday-calendars`.
- `GET/POST /holiday-calendars/{id}/holidays`, `PATCH /holidays/{id}`,
  `DELETE /holidays/{id}` (soft-archive). `holiday_type` ∈ `Public|Restricted|Optional`,
  default `Public`.
- `POST /holiday-calendars/{id}/import` — **plain router**, multipart CSV
  (`date,name,type` columns). Validate every row first; on any invalid row (bad date, missing
  name, bad type, date collides with `uq_holiday_details_calendar_date` in-file or against
  existing rows) return `422` listing failing rows and **insert nothing**. Commit only once
  the whole batch validates.
- `GET /holidays?year=` — resolved calendar for the caller. Simplified resolution (**not**
  the full shared calendar resolver, which doesn't exist until a later phase — don't
  duplicate that logic, just enough for this screen, and comment that it must be superseded
  later):
  1. Look up caller's `EmployeeMaster` via `user_id == principal.user.id`; none → step 4.
  2. Current `EmployeeShiftDetail` (`trmntn_dt IS NULL`, latest `effctv_dt`) with a
     `holiday_calendar_master_id` set → use that calendar.
  3. Else if that assignment has a `work_location_master_id` → the calendar for that
     location + requested year.
  4. Else the CDP's calendar with `work_location_master_id IS NULL` for that year.
  5. Nothing resolves → `[]`, not `404`.

**Employee shift assignment** — `GET/POST /employee-shifts`, `PATCH /employee-shifts/{id}`:
- `GET ?employee_master_id=` — history, newest `effctv_dt` first. Validate the employee
  resolves within the caller's CDP via the `corp_masters` join.
- `POST` — terminates the current assignment in the same transaction: find the row with
  `trmntn_dt IS NULL` for that employee, set `trmntn_dt = new.effctv_dt - 1 day`, insert the
  new row, one `db.commit()`. Validate `shift_master_id`/`work_location_master_id`/
  `holiday_calendar_master_id` (if given) belong to the caller's CDP.
- `PATCH` — set `trmntn_dt` or correct other fields.

**Config** — `GET/PUT /config`:
- `GET` returns the flat object (all 15 knobs from Task 02, via `tenant_params.get_int/
  get_str/get_bool`).
- `PUT` accepts a partial object; use Pydantic `model_config = ConfigDict(extra="forbid")`
  on the request schema so an unknown key → `422` automatically. `default_week_off_days` is
  stored as a comma-joined string (`"6,7"`); the schema converts to/from `list[int]` at the
  API boundary.

### `schemas.py`

One `In`/`Out` pair per resource: `WorkLocationIn`/`WorkLocationOut`,
`WorkLocationDetailOut` (adds `address: AddressOut | None`), `ShiftIn`/`ShiftOut`,
`WeekOffRuleIn`/`WeekOffRuleOut` + `WeekOffsIn` (wrapper for the replace-set body),
`HolidayCalendarIn`/`Out`, `HolidayIn`/`Out`, `EmployeeShiftIn`/`Out`,
`AttendanceConfigOut`, `UpdateAttendanceConfigRequest` (`extra="forbid"`). Match the naming
and structure of `app/modules/organizations/schemas.py` exactly (`AddressIn`/`AddressOut`,
`ContactsIn` for the wrapper-list precedent).

### Mount

`backend/app/api/router.py`:
```python
from app.modules.attendance.router import include_in as include_attendance
...
include_attendance(api_router)
```

## Acceptance criteria

- [x] All 22 endpoints implemented, admin-gated (`_require_admin`), CDP-scoped — confirmed
      via `GET /openapi.json` listing every path exactly as specified.
- [x] Timezone/night-shift/half-day/week-off/holiday-dedupe/CSV-atomicity validations all
      enforced with `422` — verified live: bad night-shift flag → 422, duplicate holiday
      date → 422, CSV with one bad row → 422 with zero rows inserted, unknown `/config`
      key → 422 (via Pydantic `extra="forbid"`).
- [x] Employee-shift assignment correctly terminates the prior row in the same
      transaction — verified live: assigning a second shift set the first row's
      `trmntn_dt` to `new.effctv_dt - 1 day` in one call.
- [x] `/config` GET/PUT round-trips correctly, rejects unknown keys — verified live.
- [x] `docker compose restart api` starts cleanly (no import errors); a full manual curl
      smoke pass (login → create work location → create shift → set week-offs → create
      holiday calendar + holiday + CSV import → assign/reassign employee shift →
      GET/PUT config → soft-archive a holiday → 401 unauthenticated) succeeded
      end-to-end against the local `db` compose service. All smoke-test rows cleaned up
      afterward — dev DB left as found.

Note: `docker-compose.yml`'s `DATABASE_URL` had an uncommitted local change pointing at a
remote host with plaintext credentials; reverted to the local `db` service
(`postgresql+psycopg://hrms:hrms@db:5432/hrms_dev`) per user confirmation before running
any migration. Host-side `uv run` is blocked by the known CodeArtifact/nhforms 401 — every
command in this task ran via `docker compose exec api ...` instead.

Completed: 2026-08-11
