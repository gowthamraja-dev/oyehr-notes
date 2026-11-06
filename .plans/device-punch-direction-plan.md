# Per-device punch direction (Entry / Exit terminals)

Schema (approved 2026-11-02): [`device-punch-direction-schema.dbml`](device-punch-direction-schema.dbml) — superseded by v2 (approved 2026-11-04), which adds the `Alternate` value: [`device-punch-direction-schema-v2.dbml`](device-punch-direction-schema-v2.dbml). This plan links them and does not restate them.
Paths are relative to `workspace-2/hrms/`.

## Why
CDP 100240 (nxti) has an entry terminal and an exit terminal. Its terminals send ZKTeco status 255 ("no in/out"), so ingest
(`backend/app/modules/devices/service.py: ingest_attlog`) falls to `derive_direction()`, which alternates IN/OUT from the employee's
previous punch. Which terminal the punch came from is never read, so a scan on the exit terminal is stored as IN whenever it is the
employee's first punch of the business day. HR declares each terminal's role once, in Device Integration, and ingest uses it.

## Scope
In:
- New column `attendance_device_masters.punch_direction` (`Auto | In | Out`, default `Auto`).
- Ingest uses it as the FIRST direction rule.
- Device Integration screen: set it when adding a terminal and when editing one; show it on the device list/card.
- The "untrusted punch sources" concept (`DIRECTION_UNTRUSTED_SOURCES` / `trusts_direction`) is removed (user decision, 2026-11-02): a stored direction is read as stored for every source and CDP; only a NULL direction falls back to position. This replaces the planned `raw.direction_source` stamp.
- Docs for the rule order.

Out of scope:
- Re-tagging punches already stored, or recomputing their days (decision 2). A separate task if HR asks.
- Attendance import. It stores `attendance_device_master_id = NULL` and has its own `direction` option (`attendance_import/punch_log.py`); unchanged.
- Changing `trust_device_direction`, `biometric_trusted_direction_cdp_ids`, or `derive_direction()` itself.
- Any per-employee or per-shift direction setting.

## Flow
Direction of a Biometric punch at ingest, first match wins. Written once in `devices/service.py`, next to `derive_direction`:
1. Terminal `punch_direction = In` → `IN`; `Out` → `OUT`. Applies even when the PIN is unmapped (no previous punch needed).
2. Terminal status byte (`_DIRECTION_BY_STATUS`) when `trust_device_direction` is on (status 255 maps to nothing).
3. `derive_direction()` alternation, only for CDPs in `biometric_trusted_direction_cdp_ids`, and only when the employee is known.
4. Otherwise NULL, as today.

`Auto` skips rule 1, so every existing terminal behaves exactly as before.

## Backend
- `app/models/attendance_device_master.py`: add `punch_direction` (`String(10)`, `server_default text("'Auto'")`, NOT NULL, CHECK constraint `ck_attendance_device_masters_punch_direction`). Task 323.
- Alembic revision on the HRMS branch (autogenerate, review, apply through `scripts/migrate.py upgrade heads`). Task 323.
- `devices/service.py`:
  - `DeviceConfig` gains `punch_direction: str = "Auto"`. **Every builder must pass it**: `service.resolve_device` (the live ingest path, line ~187), `router._config_for` (used by `_to_out` and `data_sync._device_cfg`). Missing it on `resolve_device` would silently leave the feature off in production.
  - `ingest_attlog`: apply the rule order above; the per-punch activity line (`record_event`) says when the direction came from the device setting. Nothing extra is stored.
- `devices/schemas.py`: `DeviceCreate.punch_direction` (default `Auto`), `DeviceUpdate.punch_direction: str | None`, `DeviceOut.punch_direction`; validate against `("Auto","In","Out")` → 422.
- `devices/router.py`: `create_device` sets it; `update_device` sets it when present (`exclude_unset`); `_to_out` returns it; log at INFO on change with `serial` and old/new value (no PII).
- `services/attendance_recompute_service.py`, `modules/attendance/service.py`, `modules/attendance/dashboard_service.py`: delete `DIRECTION_UNTRUSTED_SOURCES` and `trusts_direction`; each former call site tests `punch.direction is not None` instead. No `raw.direction_source` stamp is written.
- RBAC: unchanged. Device writes keep their existing gate.
- Tenant scoping: `_owned_row` already filters on `principal.tenant_id`; no new query.
- Activity log: changing a terminal's direction is a configuration change on an existing record, not a delete/ownership/login action, so `hrms-activity-logging` needs no manual call beyond the automatic middleware row.

## Frontend
- `frontend/src/lib/api.ts`: `AttendanceDevice.punch_direction`, `DeviceInput.punch_direction`.
- `frontend/src/dashboards/hrManager/AttendanceDevices.tsx`: a three-way choice on the add and edit forms — "Auto (use the terminal's own in/out)", "Entry terminal — every scan is IN", "Exit terminal — every scan is OUT" — with a one-line explanation, and a small badge on the device row/card (Entry / Exit; nothing for Auto). Tailwind only, shared components, no new skeleton needed (existing page loading state is reused).

## Tests (`backend/app/tests/modules/test_devices.py`, `test_attendance_recompute.py`)
- Exit terminal, status 255, employee's first punch of the day → `OUT`; entry terminal → `IN`; `Auto` → unchanged (alternation).
- Device setting beats a contrary status byte (status 0 on an Exit terminal → `OUT`).
- Unmapped PIN on an Exit terminal gets `OUT`; on an `Auto` terminal stays NULL.
- No marker is stored beside a declared direction.
- `resolve_device` (the real ingest entry point) carries the setting, not just `_config_for`.
- A stored device direction is read as stored in every CDP (`is_open_session`, `_break_minutes`); a NULL direction still falls back to position.
- API: create/update/read round-trip, invalid value → 422, a device of another tenant → 404 (existing `_owned_row` behaviour), re-adding an archived terminal keeps/sets the value.
- Encrypted round-trip: the devices router's existing coverage applies; extend only if the router is encrypted.

## Rollout notes
- No backfill, no behaviour change until HR sets a terminal to Entry or Exit.
- After setting nxti's exit terminal to Exit, only NEW punches follow it. Earlier punches keep their stored direction.
- Rebuild the API image (`docker compose up --build -d api`) after the model change.

## Open decisions
None. The four questions in the schema file were approved with the proposed defaults.

## Tasks
- 323 — model + migration
- 324 — backend: schemas, router, ingest rule order, removal of the untrusted-sources concept, tests, docs
- 325 — Device Integration screen

## v2 — `Alternate` (single-terminal premises), approved 2026-11-04
Why: Nano Health has ONE terminal for both clock-in and clock-out. Left on `Auto` it sends status `0` on almost every scan, and since
324 a stored `IN` is believed, so departures read "clocked in". Schema: the CHECK widens to `Auto | In | Out | Alternate`
([v2 DBML](device-punch-direction-schema-v2.dbml)); nothing else changes in the schema.

Rule order at ingest becomes (written once in `punch_direction_for`):
1. Declared role: `In` → IN, `Out` → OUT, **`Alternate` → `derive_direction()` alternation (odd scan of the business day IN, even OUT)**.
   Beats the status byte; applies in every CDP (not only `biometric_trusted_direction_cdp_ids`). Unmapped PIN → NULL.
2. Status byte, 3. alternation for listed CDPs, 4. NULL — unchanged, and skipped for `Alternate` (it already decided or stayed NULL).

Out of scope: re-tagging punches already stored (Nano Health's existing `IN`s stay), per-employee settings.
Tasks: 327 (CHECK migration), 328 (ingest rule, validator, UI, tests, docs).
