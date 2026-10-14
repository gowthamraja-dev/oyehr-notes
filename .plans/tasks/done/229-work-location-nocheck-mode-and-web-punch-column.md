---
task: 229
title: Models + migration — NoCheck check mode, web_punch_enabled and web_punch_check_mode
status: done
depends_on: []
---

# 229 — Models + migration: NoCheck check mode, `web_punch_enabled` and `web_punch_check_mode`

Clone: **top-level `hrms/`**, branch `feature/gowtham_ClockInNoCheck`.
Implements the approved schema (rev 2) `.plans/clockin-other-mode-web-key-schema.dbml` exactly. Plan: `.plans/clockin-other-mode-web-key-plan.md`.

## Scope
Schema only. The behaviour that uses these columns is task 230.

1. `backend/app/models/work_location_master.py`, after `mobile_punch_check_mode`:
   - `web_punch_enabled: Mapped[bool]`, `server_default=text("false")`: "Allow web clock-in".
     Only effective while `mobile_punch_enabled` is on.
   - `web_punch_check_mode: Mapped[str]`, `String(20)`, `server_default=text("'Geofence'")`:
     `'Geofence' | 'NoCheck'`, independent of the app mode, never Wi-Fi.
   - Update the `mobile_punch_check_mode` comment to list `'NoCheck'`.
2. `backend/app/services/punch_verification_service.py`:
   - `CHECK_NONE = "NoCheck"`, added to `CHECK_MODES`. Without it, `check_mode()` maps NoCheck
     back to WifiAndGeofence;
   - `WEB_CHECK_MODES = (CHECK_GEOFENCE, CHECK_NONE)`;
   - `web_check_mode(loc)`, which falls back to Geofence for unknown or NULL values.
3. Migration `e5b2c8a14f70_work_location_nocheck_and_web_punch.py` (revises `b4d7e1a90c52`).
   Hand-written and existence-guarded, because hrms-dev gets this DDL directly:
   - add `web_punch_enabled boolean NOT NULL DEFAULT false`;
   - add `web_punch_check_mode varchar(20) NOT NULL DEFAULT 'Geofence'`, with
     `ck_work_location_masters_web_punch_check_mode IN ('Geofence','NoCheck')`;
   - drop and re-create `ck_work_location_masters_mobile_punch_check_mode` with `NoCheck` added;
   - downgrade refuses while any row has app mode `NoCheck`. Otherwise it restores the
     3-value CHECK and drops both web columns and their CHECK.

## Files
- `backend/app/models/work_location_master.py`
- `backend/app/services/punch_verification_service.py` (constants and the accessor only)
- `backend/alembic/versions/e5b2c8a14f70_work_location_nocheck_and_web_punch.py`

## Acceptance criteria
- [x] The migration matches the DBML: two columns with the DBML's defaults, the web CHECK without Wi-Fi, and the app CHECK widened by `NoCheck`.
- [x] The migration has been reviewed by the user.
- [x] It applies on a fresh DB through `scripts/migrate.py upgrade heads`, and re-running it is a no-op. On an empty DB, run `upgrade c3f8d21a9e47` first: an existing ordering bug in `b4d7e1a90c52` on `main`, outside this task.
- [x] Downgrade refuses while a `NoCheck` row exists. It works when none does, and upgrading again works.
- [x] `alembic check` reports no drift on `work_location_masters`. Drift on other tables already exists on `main`.
- [x] `check_mode(loc)` returns `NoCheck` for a NoCheck row. `web_check_mode(loc)` returns the stored value, falling back to `Geofence`. The DB rejects `web_punch_check_mode='Wifi'`.
- [x] The DDL is applied to shared hrms-dev, which needs the user's go-ahead. Until then the live `:8000` container (serving this clone) errors on any query that loads `WorkLocationMaster`.

Verified 13-Oct-26 on a throwaway postgres:18; `ruff` clean. DDL applied to hrms-dev 13-Oct-26 at the user's go-ahead (guarded, one transaction, not stamped): 35 rows, all `web_punch_enabled=false`, `web_punch_check_mode='Geofence'`; ORM read through the live container confirmed. Uncommitted on `feature/gowtham_ClockInNoCheck`.

Completed: 2026-10-13
