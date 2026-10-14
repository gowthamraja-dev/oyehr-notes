---
task: 116
title: HolidayDetail is missing archived_by_id/archived_at that its sibling tables both have
status: ongoing
depends_on: []
---

# 116 — HolidayDetail is missing archived_by_id/archived_at that its sibling tables both have

## Scope

`backend/app/models/holiday_detail.py` (lines 19-31) has only `is_active`/`archive` — no
`archived_by_id`/`archived_at`:

```python
is_active: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
archive: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))
created_by_id: Mapped[int | None] = mapped_column(BigInteger)
updated_by_id: Mapped[int | None] = mapped_column(BigInteger)
```

Compare its two siblings in the same feature area, both of which carry the full set:

- `backend/app/models/work_location_master.py:50-51` — `archived_by_id`, `archived_at`
- `backend/app/models/holiday_calendar_master.py:27-28` — `archived_by_id`, `archived_at`

And the corresponding service functions correctly populate all three fields on archive —
`archive_work_location` (`backend/app/modules/attendance/service.py:289-305`):

```python
loc.archived_by_id = principal.user.id
loc.archived_at = _now()
```

— while `archive_holiday` (`backend/app/modules/attendance/service.py:448-458`) can only set
`archive = True` + `updated_by_id`, because the columns to record who archived it and when don't
exist on the model:

```python
def archive_holiday(db: Session, principal: AuthPrincipal, holiday_id: int) -> None:
    require_admin_or_permission(db, principal, "DELETE", "HOLIDAY_CALENDAR")
    holiday = _get_holiday(db, principal, holiday_id)
    holiday.archive = True
    holiday.updated_by_id = principal.user.id
    log_activity(...)
    db.commit()
```

There is no "who archived this holiday and when" trail at all for `holiday_details`, unlike
every other archivable entity in this module. This matters for the same reason `gaps.md`'s
resolved gap #17 (audit trail) cared about it: an HR admin later asking "who removed this
holiday, and when" for `holiday_details` specifically has no answer, even though the generic
`user_activity_details` row from `log_activity` records the *action* (there's a row for
"DELETE /attendance/holidays/{id}") but not a queryable column on the holiday row itself the way
`work_location_masters`/`holiday_calendar_masters` support (e.g. for display in an admin
"archived by X on Y" tooltip, matching whatever the work-location/holiday-calendar admin screens
already show, if they show it).

## Files

### Edited

- `backend/app/models/holiday_detail.py`
  - Add, matching `work_location_master.py`'s exact column definitions:
    ```python
    from datetime import date, datetime
    archived_by_id: Mapped[int | None] = mapped_column(BigInteger)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ```
- `backend/app/modules/attendance/service.py`
  - `archive_holiday` (line 448-458): set both new fields alongside the existing
    `archive = True`/`updated_by_id`, mirroring `archive_work_location`:
    ```python
    holiday.archive = True
    holiday.archived_by_id = principal.user.id
    holiday.archived_at = _now()
    holiday.updated_by_id = principal.user.id
    ```
- Migration: `uv run alembic revision --autogenerate -m "add archived_by_id/archived_at to holiday_details"`
  from `backend/`, review the generated file, then `uv run alembic upgrade head`.
- If `HolidayOut`/`HolidayAdminOut` (in `backend/app/modules/attendance/schemas.py`) already
  surface `archived_by_id`/`archived_at` for `work_location_masters`/`holiday_calendar_masters`
  responses, add the equivalent fields to the holiday response schema(s) too, for parity —
  check during implementation whether the frontend admin screen for holidays already has a slot
  for this or whether that's a separate frontend task.

### Tests

- `backend/app/tests/modules/test_attendance.py`
  - New test: archiving a holiday sets `archived_by_id` to the acting user's id and
    `archived_at` to a non-null, recent timestamp — mirrors whatever existing test covers
    `archive_work_location`'s equivalent fields, if one exists (use it as the template).

## Acceptance criteria

- [ ] `holiday_details` has `archived_by_id`/`archived_at` columns, added via a reviewed Alembic
      migration.
- [ ] `archive_holiday` populates both fields on every archive, matching
      `archive_work_location`'s pattern exactly.
- [ ] A test asserts both fields are set correctly after archiving.
- [ ] Full backend suite passes (`uv run pytest`).
