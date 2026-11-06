---
task: 327
title: Device punch direction v2 — Alternate value: model CHECK and migration
status: done
depends_on: [323]
---

# 327 — Device punch direction v2: `Alternate` — model CHECK + migration

## Scope
Widen the one CHECK on `attendance_device_masters.punch_direction` from `('Auto','In','Out')` to `('Auto','In','Out','Alternate')`. Contract: `.plans/device-punch-direction-schema-v2.dbml` (approved 2026-11-04); plan section "v2" in `.plans/device-punch-direction-plan.md`.
Does NOT cover ingest, API validation or UI (task 328). Paths relative to `workspace-2/hrms/`. Refreshes task 323, which stays untouched in `done/` (its migration is applied; never edit it).

Column is unchanged: `String(10)`, NOT NULL, default `'Auto'`. `Alternate` = one terminal used for both clock-in and clock-out; the odd scan of the employee's business day is IN, the even one OUT. No new table, column or index, no backfill (every existing row already satisfies the wider CHECK).

## Files
- `backend/app/models/attendance_device_master.py` — CHECK text `punch_direction IN ('Auto','In','Out','Alternate')` (same name `ck_attendance_device_masters_punch_direction`) and the column comment gaining the fourth value.
- `backend/alembic/versions/<new>_device_punch_direction_alternate.py` — `down_revision = "f4a8c2e6b913"`.

## Rules
- NEW revision; never edit `f4a8c2e6b913`. Hand-written and existence-guarded like it (the shared hrms-dev DB is stamped at orphan `8012104013b3` and cannot be `alembic upgrade`d): `upgrade()` drops the CHECK if present and re-creates it with four values; a re-run is a no-op. `downgrade()` restores the three-value CHECK; it must first reset any `Alternate` rows to `Auto` (otherwise the narrower CHECK fails) — say so in a comment.
- Applying to hrms-dev: read memory `reference-shared-hrms-dev-db.md` first; only at the user's explicit request; one transaction, `lock_timeout = 5s`, stamp left alone (same procedure as 323).
- Check the new file for unrelated drift; run through `uv run python scripts/migrate.py upgrade heads` (several heads), not bare `alembic upgrade head`. Prefer a scratch DB; ask before starting one.

## Acceptance criteria
- [x] Model CHECK accepts exactly `Auto / In / Out / Alternate`
- [x] Migration chains off `f4a8c2e6b913`, contains only the CHECK change, ruff clean
- [x] On a scratch DB (checked 2026-11-04, from the v1 three-value state with an existing `Out` row): `Alternate` accepted; `'alternate'`, `'Sideways'`, `''` rejected; existing rows unchanged; second upgrade is a no-op
- [x] Downgrade turns `Alternate` rows into `Auto`, restores the three-value CHECK, second downgrade is a no-op
- [x] `compare_metadata` reports no drift for `attendance_device_masters`

## Verification notes (2026-11-04)
Built in `workspace-2/hrms`, NOT committed. Model CHECK widened; migration `a7d3f9c1e5b2_device_punch_direction_alternate.py` (chained off `f4a8c2e6b913`; hand-written, existence-guarded; downgrade resets `Alternate` rows to `Auto` first); ruff clean.
Scratch Postgres 18 container `hrms-ws2-scratch-pg` on 127.0.0.1:55432 (started with the user's approval, removed afterwards; the shared hrms-dev DB was not touched). Schema built from the models, then put in the v1 state (three-value CHECK, one existing `Out` row) and the migration's `upgrade()` / `downgrade()` run through Alembic `Operations`: after upgrade the CHECK has four values, the old row still reads `Out`, `Alternate` / `Auto` / `In` / `Out` accepted, `alternate` / `Sideways` / `''` / NULL rejected; second upgrade a no-op; `compare_metadata` (type + server defaults) reports no drift for `attendance_device_masters`; downgrade turns the `Alternate` row into `Auto` and restores three values, second downgrade a no-op; re-upgrade works. Not run: `scripts/migrate.py upgrade heads` (the earlier `f2a9d4c7b180_seed_reference_data` fresh-chain failure from task 323 still blocks a full chain), so "applies on a fresh DB" and `alembic check` are met by the substitutes above.
NOT applied to the shared hrms-dev DB — that is a separate step, only at the user's explicit request (guarded `upgrade()` through `Operations` in one transaction with `lock_timeout = 5s`, stamp left at `8012104013b3`, as in 323).

Completed: 2026-11-04
