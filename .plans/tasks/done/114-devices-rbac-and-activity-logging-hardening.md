---
task: 114
title: Devices module has no RBAC gates at all, and map_enrollment is missing its activity log
status: ongoing
depends_on: []
---

# 114 — Devices module has no RBAC gates at all, and map_enrollment is missing its activity log

## Scope

Found while analysing the attendance calculation pipeline end to end (punch ingestion feeds
attendance calculation directly, so the devices module is in-scope even though it isn't the
recompute engine itself).

`backend/app/modules/devices/router.py` has **zero** permission gates. Every route depends only
on `CurrentPrincipal, DbSession` — contrast with `backend/app/modules/attendance/router.py`,
which defines `_APPROVE`/`_CREATE`/`_READ`/`_UPDATE` (`RequirePermission(..., "ATTENDANCE")`,
lines 54-57) and applies them to every route that touches other people's data. Devices has no
equivalent at all. Concretely ungated, reachable by **any** authenticated tenant user regardless
of role:

- `POST /devices` — register a new biometric terminal (`create_device`, line 288)
- `PATCH /devices/{serial}` — reconfigure a terminal (`update_device`, line 329)
- `DELETE /devices/{serial}` — soft-delete a terminal (`remove_device`, line 349) — a destructive
  action with no gate at all
- `PUT /devices/{serial}/users/{device_user_id}/mapping` — reassign which employee a biometric
  PIN attributes attendance to (`map_enrollment`, line 444) — this directly controls *whose*
  attendance record a device punch lands on, i.e. it can misattribute pay-affecting attendance
- `DELETE /devices/{serial}/users/{device_user_id}/mapping` (`unmap_enrollment`, line 479)
- `POST /devices/{serial}/users/sync` (`sync_device_users`, line 199)
- `POST /devices/{serial}/logs/raw-capture` (`set_raw_capture`, line 388) — toggles capturing raw
  device payloads, which can include biometric template bytes

There is no `DEVICE` row in the Roles & Permissions grid either — `grep -n "ATTENDANCE\|DEVICE"
backend/app/modules/roles/permissions.py` only turns up `ATTENDANCE`/`HOLIDAY_CALENDAR` rows.
Per `hrms/CLAUDE.md`'s own "Roles & Permissions" section: *"Where a module can do something the
grid has no cell for (Attendance/Settings deletes), gate it on the nearest cell (UPDATE), never
leave it ungated."* `attendance/service.py`'s `archive_work_location`/`archive_holiday` follow
this correctly (`require_admin_or_permission(db, principal, "DELETE", "HOLIDAY_CALENDAR")`
pattern); devices never got the same treatment. `backend/app/tests/modules/test_devices.py` (503
lines) has zero RBAC/403 assertions, which is why this was never caught.

Separately, `map_enrollment` (`router.py:443-475`) — an ownership/assignment-change action per
the `hrms-activity-logging` skill ("attach PIN X to employee Y") — has **no** `log_activity`
call, while its sibling `unmap_enrollment` (`router.py:478-493`) does:

```python
# unmap_enrollment already does this (line 484-488):
log_activity(
    db, user_id=principal.user.id, tenant_id=principal.tenant_id, role_master_id=principal.role_master_id,
    action_type="DELETE", action_path=f"/devices/{serial}/users/{device_user_id}/mapping",
    deleted_data={"enrollment_no": device_user_id},
)
```

Re-mapping a PIN silently changes whose attendance a future punch attributes to — exactly the
"assign X to Y" case the skill calls out — yet only the *un*-mapping half is logged.

**Not in scope**: the `iclock_router` (device-serial-authenticated push endpoint, no JWT) is a
different surface by design and is out of scope here — this task is only the JWT-authenticated,
tenant-scoped `/api/v1/devices/*` router.

## Files

### Edited

- `backend/app/modules/devices/router.py`
  - Add `_UPDATE = RequirePermission("UPDATE", "ATTENDANCE")` (mirroring
    `attendance/router.py`'s pattern — devices lives under the same "Attendance & Shifts" grid
    row per `permissions.py` line 47, so gate on the nearest existing cell rather than adding a
    new grid row, matching the CLAUDE.md convention cited above).
  - Apply `_UPDATE` (as a route `dependencies=[...]` or a parameter default, matching whichever
    style `attendance/router.py` uses) to: `create_device`, `update_device`, `remove_device`,
    `map_enrollment`, `unmap_enrollment`, `sync_device_users`, `set_raw_capture`.
  - Leave read-only routes (`list_devices`, `list_device_users`, `list_work_locations`,
    `list_device_logs`, `list_mappable_employees`, `test_connection`) as-is unless the team wants
    a `_READ` gate too — decide during implementation; the write endpoints are the actual risk.
  - In `map_enrollment` (line 466-470, right after `service.map_enrollment(...)` and before
    `db.commit()`), add:
    ```python
    log_activity(
        db, user_id=principal.user.id, tenant_id=principal.tenant_id, role_master_id=principal.role_master_id,
        action_type="UPDATE", action_path=f"/devices/{serial}/users/{device_user_id}/mapping",
    )
    ```
    (no `deleted_data` — nothing is deleted here, unlike the unmap case).

### Tests

- `backend/app/tests/modules/test_devices.py`
  - New tests: a non-privileged role (e.g. plain Employee) gets 403 on `create_device`,
    `update_device`, `remove_device`, `map_enrollment`, `unmap_enrollment`, `sync_device_users`,
    `set_raw_capture`.
  - New test: a privileged role (HR Admin, or whatever role holds `UPDATE ATTENDANCE` in the
    test fixtures) still succeeds on all of the above — a regression guard against over-gating.
  - New test: `map_enrollment` writes a `user_activity_details` row (query it back, or assert via
    whatever helper `test_attendance.py`/`test_shifts.py` already use to check `log_activity`
    side effects) — mirrors the existing `unmap_enrollment` coverage if any, or is new for both.

## Acceptance criteria

- [ ] Every write endpoint in `devices/router.py` (`create_device`, `update_device`,
      `remove_device`, `map_enrollment`, `unmap_enrollment`, `sync_device_users`,
      `set_raw_capture`) is gated on `RequirePermission("UPDATE", "ATTENDANCE")` (or an
      explicitly-decided alternative, if the team chooses a dedicated `DEVICE` grid row instead —
      record that decision here if taken).
- [ ] A caller without the permission gets 403 on each of the above; a caller with it still
      succeeds (regression tests for both directions).
- [ ] `map_enrollment` writes a `log_activity(...)` row on every successful mapping, matching
      `unmap_enrollment`'s existing pattern.
- [ ] Full backend suite passes (`uv run pytest`).
