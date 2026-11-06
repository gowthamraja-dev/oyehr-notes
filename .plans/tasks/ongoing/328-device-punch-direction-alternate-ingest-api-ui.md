---
task: 328
title: Device punch direction v2 — Alternate: ingest rule, API, Device Integration UI, tests, docs
status: ongoing
depends_on: [327, 324, 325]
---

# 328 — Device punch direction v2: `Alternate` — backend + UI

## Scope
Make `punch_direction = 'Alternate'` work end to end for a premises with one terminal (Nano Health): odd scan of the employee's business day = IN, even = OUT, regardless of the status byte and of the CDP. Contract: `.plans/device-punch-direction-schema-v2.dbml`; plan section "v2". Refreshes task 324 (and the UI of 325), which stay in `done/`/`ongoing/` as they are.
Does NOT cover re-tagging punches already stored, the attendance import, or changing `derive_direction()` itself. Paths relative to `workspace-2/hrms/`.

## Rule order — `backend/app/modules/devices/service.py: punch_direction_for` (first match wins; written once there)
1. Declared role: `In` → `IN`, `Out` → `OUT`, **`Alternate` → `derive()`'s alternation** — the status byte is NOT consulted and the CDP need not be in `biometric_trusted_direction_cdp_ids`. An unmapped PIN (no employee) → NULL, as `Auto`.
2. Status byte when `trust_device_direction` (not for `Alternate`).
3. `derive()` for CDPs in `biometric_trusted_direction_cdp_ids` (not reached for `Alternate`, which already decided).
4. NULL.

## Changes
- `service.py`: `PUNCH_DIRECTIONS = ("Auto", "In", "Out", "Alternate")`. `ingest_attlog` currently passes `derive` returning None unless `derive_directions` (the CDP flag) is on; for an `Alternate` terminal the derive callable must run whenever the employee is known. The returned `from_setting` flag is True for `Alternate` too (activity line says `IN (device setting)`).
- `schemas.py`: validators already use `PUNCH_DIRECTIONS`, so `Alternate` is accepted; any other value still 422. Check the error message lists four values.
- `router.py`: no logic change expected (create/update/_to_out/_config_for already carry the value); verify.
- Frontend: `lib/api.ts` `PunchDirection` gains `"Alternate"`; `punchDirectionBadge` returns `"Single"` for it (return type widened); `DeviceForms.tsx` `DIRECTIONS` gets a fourth card — title "Single terminal", sub "Scans alternate clock-in / clock-out (odd = in, even = out)" — and the "new punches only" line stays; `DevicePanels.tsx` "Scan direction" row shows "Single terminal: scans alternate clock-in / clock-out". Tailwind only, existing components; `npx tsc --noEmit` + eslint on changed files.
- Docs: `docs/device-punch-direction.md` — fourth value in the table, the new rule 1, the caveat that one missed/extra scan flips the rest of that business day (count restarts each day), "Setting up a single terminal (Nano Health)". Fix the "three values" wording and `config.py`'s `biometric_trusted_direction_cdp_ids` comment if it implies it is the only alternation switch.

## Tests — `backend/app/tests/modules/test_devices.py`
- `Alternate` terminal, status 255: 1st scan of the day IN, 2nd OUT, 3rd IN; next business day restarts at IN.
- Status 0 (and status 1) on an `Alternate` terminal is ignored (1st scan IN, 2nd OUT).
- A CDP NOT in `biometric_trusted_direction_cdp_ids` still alternates on an `Alternate` terminal; an `Auto` terminal there is unchanged.
- Unmapped PIN on `Alternate` → NULL direction.
- A double-tap inside the debounce window repeats the previous direction (existing `derive_direction` behaviour).
- Through `resolve_device`; API create/update/read round-trip with `Alternate`; `'alternate'` / `'Sideways'` → 422; another tenant's device → 404.
- Existing In/Out/Auto tests unchanged and green.

## Acceptance criteria
- [x] Alternate terminal stores IN/OUT/IN… per employee-business-day in any CDP, ignoring the status byte
- [x] `Auto`, `In`, `Out` behave exactly as before (existing devices / recompute tests pass)
- [x] API accepts and returns `Alternate`; invalid value refused
- [ ] Device Integration add/edit shows and saves the fourth option; the list badge and detail row read correctly (browser check only if a server is approved)
- [x] `uv run pytest app/tests/modules/test_devices.py app/tests/modules/test_attendance_recompute.py` green apart from the 4 known failures that also fail on the untouched tree; ruff clean on changed lines
- [x] Doc updated

## Progress (2026-11-04)
Built in `workspace-2/hrms`, NOT committed. `devices/service.py`: `PUNCH_DIRECTIONS` has `Alternate`; `punch_direction_for` rule 1 returns `derive()` for it (flag true only when a direction came back); new `alternates_directions()` switches derivation on for an Alternate terminal in any CDP. UI: fourth "Single terminal" card (2-column grid), badge "Single", detail-panel row. Doc and `config.py` comment updated. 9 new tests in `test_devices.py` ("Alternate" section). Checked: `punch_direction_for` / validators / model CHECK by a throwaway offline script; `npx tsc --noEmit` and eslint on the four frontend files exit 0; ruff shows only 2 old warnings. The new pytest tests have NOT been run (no database; waiting on approval for a scratch Postgres). No browser check (no server approved).

## Verification (2026-11-04)
Same scratch Postgres 18 as task 327 (removed afterwards). Schema built from the models, the user + `scripts/seed_attendance_status_masters.py` seeded (needed by the recompute fixtures).
`uv run pytest app/tests/modules/test_devices.py app/tests/modules/test_attendance_recompute.py`: **219 passed, 4 failed**. The 4 are the ones task 324 already recorded as failing on the untouched tree (`test_open_day_is_present_then_settles_after_close` x3, `test_grace_absent_late_punch_turns_day_back_to_present`). All 10 Alternate tests pass; the existing In/Out/Auto tests pass unchanged.
Still open: the UI criterion is met in code and by `npx tsc --noEmit` + eslint (exit 0) but NOT seen in a browser — no frontend server approved. Unseen: the 2-column radio layout with four cards, the "Single" badge, the new detail-panel row. Task stays in `ongoing/` for that reason (same as 325).

## Applied to the shared hrms-dev DB (2026-11-05)
At the user's explicit request, for task 327's migration `a7d3f9c1e5b2`. Read-only check first: stamp `8012104013b3`, column present (`varchar(10)` NOT NULL default `'Auto'`), CHECK still the three-value one, 10 device rows (8 `Auto`, 1 `In`, 1 `Out`). The migration's own `upgrade()` was run through `alembic.operations.Operations` in ONE transaction with `lock_timeout = 5s`; stamp left alone. After: the CHECK allows `Auto / In / Out / Alternate`, the 10 rows are unchanged, `compare_metadata` (read-only) reports no drift for `attendance_device_masters`. The running API on that DB needs the new code before a terminal can be set to `Alternate` (the old validator refuses it with 422).
