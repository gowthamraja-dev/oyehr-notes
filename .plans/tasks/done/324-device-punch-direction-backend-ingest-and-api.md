---
task: 324
title: Device punch direction — API, ingest rule order, trusted display, tests, docs
status: done
depends_on: [323]
---

# 324 — Device punch direction: backend

## Scope
Make the saved terminal setting (`attendance_device_masters.punch_direction`: `Auto | In | Out`, task 323) the FIRST rule for a Biometric punch's direction, expose it on the devices API, and let the clocked-in/out display trust such a punch.
Does NOT cover the UI (task 325), re-tagging stored punches, or the attendance import (it has `attendance_device_master_id = NULL` and its own `direction` option). Plan: `.plans/device-punch-direction-plan.md`. Paths relative to `workspace-2/hrms/`.

## Rule order at ingest (first match wins) — `backend/app/modules/devices/service.py: ingest_attlog`
1. `punch_direction = In` → `IN`, `Out` → `OUT`. Applies even when the PIN is unmapped (`employee_master_id` NULL).
2. Terminal status byte via `_DIRECTION_BY_STATUS`, when `trust_device_direction` (status 255 → nothing).
3. `derive_direction()` alternation, only when the CDP is in `biometric_trusted_direction_cdp_ids` and the employee is known.
4. Otherwise NULL (as today).
`Auto` skips step 1. Write this order once, as a comment/docstring beside `derive_direction`; do not repeat it in import or recompute code.

## Changes
- `DeviceConfig` (`devices/service.py`) gains `punch_direction: str = "Auto"`. **Pass it from every builder**: `service.resolve_device` (the live ADMS path, ~line 187) AND `devices/router.py: _config_for` (feeds `_to_out` and `data_sync._device_cfg`). Forgetting `resolve_device` leaves the feature off in production.
- `devices/schemas.py`: `DeviceCreate.punch_direction: str = "Auto"`, `DeviceUpdate.punch_direction: str | None = None`, `DeviceOut.punch_direction: str`; a validator accepts only `Auto`, `In`, `Out` (else 422).
- `devices/router.py`: `create_device` sets it (also when re-adding an archived terminal); `update_device` sets it when present (the handler uses `model_dump(exclude_unset=True)`); `_to_out` returns it. Log `device_direction_changed`-style INFO with serial, old and new value on change; no PII.
- `ingest_attlog`: per-punch `record_event` line shows the direction and, when from the setting, says so (e.g. `OUT (device setting)`).
- **Remove the "untrusted sources" concept (user decision 2026-11-02).** Delete `DIRECTION_UNTRUSTED_SOURCES` and `trusts_direction` from `services/attendance_recompute_service.py`; every call site (`is_open_session`, `open_sessions_for_latest_punches`, `_break_minutes`, `modules/attendance/service.py` today-punches, `modules/attendance/dashboard_service.py` prefill) tests `punch.direction is not None` instead. A stored direction is read as stored for every source and CDP; a NULL direction still falls back to position. No `raw.direction_source` stamp. `biometric_direction_trusted` stays: it only gates the ingest alternation. Behaviour change for CDPs outside `biometric_trusted_direction_cdp_ids`: a device punch stored with status 0 (default IN) is now believed, so a departure stored as IN reads "clocked in" until the next punch.

## Rules
- Tenant scoping stays via `_owned_row` (`principal.tenant_id`); no new query. Plain stdlib/structlog logging, no PINs/names in new log lines beyond what `record_event` already shows.
- No change to the existing device RBAC gate.
- Docs: add `docs/device-punch-direction.md` (what the three values mean, the rule order above, that only new punches follow a change, how nxti's exit terminal is set up), and link it from the Device Integration/attendance section of `workspace-2/hrms/CLAUDE.md` if one exists there, else from `docs/leave-and-attendance/attendance/admin-configuration.md`.

## Tests — `backend/app/tests/modules/test_devices.py`, `test_attendance_recompute.py`
- Status 255, employee's first punch of the day: Exit terminal → `OUT`, Entry terminal → `IN`, `Auto` → alternation as before.
- A contrary status byte (status 0 on an Exit terminal) → `OUT`.
- Unmapped PIN: Exit terminal → `OUT`; `Auto` terminal → NULL.
- Through `resolve_device` (the real entry point), not only `_config_for`.
- A stored device direction is read as stored in a CDP outside `biometric_trusted_direction_cdp_ids`; direction-less punches keep the position rule; `is_open_session` reads a stored `OUT` as closed.
- API: create/read/update round-trip; invalid value → 422; another tenant's device → 404; re-adding an archived terminal.

## Acceptance criteria
- [x] Exit terminal punches store `OUT` and entry terminal punches store `IN` with status 255, including for an unmapped PIN
- [x] `Auto` terminals behave as before (the existing devices / recompute ingest tests pass unchanged)
- [x] `resolve_device` and `_config_for` both carry the setting (tested through `resolve_device` and `_config_for`)
- [x] `DIRECTION_UNTRUSTED_SOURCES` / `trusts_direction` gone from code and docs; the old position-rule tests rewritten for direction-less punches, plus new tests for stored directions
- [x] API accepts/returns `punch_direction`; bad value is refused (pydantic validation, i.e. 422 over HTTP); tenant scoping test passes — tested by calling the route functions, not over HTTP (the router is encrypted and had no HTTP-level tests)
- [ ] `uv run pytest app/tests/modules/test_devices.py app/tests/modules/test_attendance_recompute.py` green; ruff clean on changed files — NOT fully met: 209 passed, 4 failed (`test_open_day_is_present_then_settles_after_close` x3, `test_grace_absent_late_punch_turns_day_back_to_present`), and they fail identically on the untouched tree. Ruff reports only old E741 / F841 warnings, none on lines of this change
- [x] Doc written and linked: `docs/device-punch-direction.md`, linked from `docs/leave-and-attendance/attendance/admin-configuration.md` §7.1 and `assembler.md`; the stale parts of `assembler.md` were corrected
- [ ] Checked by hand against a running API — NOT done (no server approved or started)

## Closed with these gaps (2026-11-02, at the user's request)
- Tests ran on a scratch Postgres 18 built from the models, removed afterwards. The other attendance test files (`test_attendance.py`, `test_attendance_dashboard.py`, `test_webhooks.py`, the regularize tests) were NOT run: their fixtures fail on that scratch DB (`status_masters.created_by_id` is NOT NULL there). `dashboard_service.py` (the prefill edit) is therefore covered only by `test_attendance_recompute.py`.
- Behaviour change for CDPs outside `biometric_trusted_direction_cdp_ids` that leave a terminal on `Auto` and receive status 0: that default IN is now believed (a departure reads "clocked in" until the next punch). Setting the terminal to Exit / Entry avoids it.
- Built in `workspace-2/hrms`, NOT committed. `frontend/.env.dev` in that clone carries an unrelated one-line change that must not be committed with this work.

Completed: 2026-11-02
