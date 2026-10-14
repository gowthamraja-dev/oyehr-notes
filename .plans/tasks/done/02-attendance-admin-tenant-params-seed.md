---
task: 02
title: Tenant knob accessor + seed script
status: done
depends_on: [1]
---

# 02 — Tenant knob accessor + seed script

Part of the Attendance admin-config backend slice. Builds the shared knob-reading service
that Task 03's `/attendance/config` endpoint depends on.

## Scope

`app/services/tenant_params.py` implements the accessor contract from
`docs/leave-and-attendance/14-config-knob-reference.md` §2, scoped to the 15 knobs this
slice's `/config` endpoint reads/writes (the full ~34-knob catalogue is completed later by
the leave/devices tasks — additive to this same file/dict, not a rewrite).
`scripts/seed_attendance_leave_masters.py` creates the matching `ParameterMaster` catalogue
rows at fixed ids so a write doesn't hit a FK violation on a fresh DB.

## Files

**`backend/app/services/tenant_params.py`** (new — `app/services/` today only has
`image_service.py`):

```python
PARAM_IDS: dict[str, int] = {
    "regularization_window_days": 300,
    "max_regularization_requests_per_month": 301,
    "auto_absent_days": 303,
    "late_marks_per_half_day": 304,
    "late_mark_reset_cycle": 305,
    "overtime_tracking_enabled": 307,
    "short_day_status": 309,
    "default_week_off_days": 311,
    "default_full_day_minutes": 312,
    "default_half_day_minutes": 313,
    "default_grace_in_minutes": 314,
    "default_time_zone": 316,
    "missing_punch_policy": 320,
    "leave_year_start_month": 330,
    "attendance_cutoff_day": 340,
}

def get_int(db, cdp_id, name, default) -> int: ...
def get_str(db, cdp_id, name, default) -> str: ...
def get_bool(db, cdp_id, name, default) -> bool: ...
def upsert(db, cdp_id, name, value) -> None: ...
```

(`get_date` from the spec's full signature is omitted here — none of these 15 knobs are
dates. Add it when a future knob needs it.)

Lookup: `select(CareDeliveryProgramParameterDetail).where(cdp_id==..., parameter_master_id==PARAM_IDS[name], is_active==True).order_by(id).limit(1)`
— no row → return `default` (pick the lowest `id` deterministically if duplicates exist,
never the latest — the table has no unique constraint on `(cdp, parameter_master_id)`).
`upsert()` writes both the typed column (`int_val`/`str_val`) and the mirrored
`parameter_value`, exactly matching `app/modules/organizations/service.py:64-93`
(`update_theme`)'s upsert loop: mutate the existing row if found, else `db.add(...)`, then
`db.commit()`.

No per-request cache in this task — `/config` reads ~15 knobs once per request. Add caching
when the assembler (a later phase) becomes a real per-employee-date hot-loop consumer.

**`backend/scripts/seed_attendance_leave_masters.py`** (new, global-only — no `--cdp`
per-tenant defaults in this task):

```bash
uv run python -m scripts.seed_attendance_leave_masters
```

Follows `scripts/seed_dev.py`'s exact `get_or_create` + fixed-id `ParameterMaster` pattern
(see `THEME_PARAMS` there). Creates one `ParameterMaster` row per entry in
`tenant_params.PARAM_IDS` (import the dict from there — single source of truth, don't
duplicate the id↔name mapping), `parameter_name` = the knob name, `parameter_desc` = a short
human label. Idempotent: `if db.get(ParameterMaster, param_id) is None: db.add(...)`.

## Acceptance criteria

- [x] `tenant_params.get_int/get_str/get_bool/get_date/upsert` implemented and importable.
- [x] `python -m scripts.seed_attendance_leave_masters` (run via `docker compose exec api`,
      per the host-side CodeArtifact 401 gotcha) creates 15 `ParameterMaster` rows at ids
      300-340.
- [x] Running the seed script twice leaves row counts unchanged (idempotency) — verified.
- [x] `upsert()` followed by `get_int/get_str/get_bool` round-trips against real CDP id 1,
      confirmed a repeat `upsert()` updates the existing row rather than duplicating it
      (row count stayed 1) — verified in a rolled-back transaction, no data left behind.

Completed: 2026-08-11
