---
task: 282
title: Regularize — many employees at once (preview and apply API)
status: done
depends_on: [281]
---

# 282 — Regularize — many employees at once (preview and apply API)

## Scope
HR regularizes the **same date range and the same outcome** (Present / Half day / WFH, from 281) for **several employees** in one action. Built by looping the single-employee
core from 270/281, not by a new engine. No schema change. UI is 284. Out of scope: per-employee times/statuses (use the bulk import), undo, a CSV path.

### Refactor first
Pull the body of `regularize_range.apply` into `_apply_employee(db, principal, employee, dates, body) -> (results, request_ids, applied_dates)` that does everything except the final
`db.commit()`; single-employee `apply` becomes a thin wrapper (its behaviour and tests must not change). Same for `preview` → `_preview_employee`.

### Endpoints (attendance router, same `EncryptedRoute` class, `RequirePermission("APPROVE","ATTENDANCE")` + `sees_whole_org`, i.e. exactly the 270 gate)
1. `POST /api/v1/attendance/regularize-range/bulk/preview`
   `{ employee_ids: [..], from_date, to_date, mode, in_time, out_time, day_status, half }`
   → `{ employees: [{ employee_id, employee_code, name, days: [RangeDayPlan], summary }], summary: {employees, regularize, needs_override, skip, blocked} }`
2. `POST /api/v1/attendance/regularize-range/bulk`
   `{ targets: [{ employee_id, dates: [..] }], mode, in_time, out_time, day_status, half, reason_code, note, override_reason }`
   → `{ applied, skipped, failed, employees: [{ employee_id, applied, skipped, failed, results: [RegularizeRangeResult] }] }` (200 also on partial success)

Limits (422 otherwise): `employee_ids` / `targets` 1..**50** distinct ids; span ≤ 62 days (as 270); total employee-days ≤ **1,000** (preview: employees × span; apply: sum of `dates`).
Whole-request errors: 403 without org-wide scope / APPROVE, **404 if any employee id is not in the caller's tenant** (nothing is previewed or written — never leak which ids
exist), 422 bad body. `override_reason` is required only when some ticked day of some employee is locked (per-day `failed`/`LOCKED` otherwise, as 270).

Apply: each employee runs `_apply_employee` (each day still in its own `begin_nested()`), then **one** `db.commit()` for the whole call. One `in_app` summary notification **per
employee** (not per day) and one `log_activity` row per employee (as 270). Avoid N+1: resolve shifts/day types/rows/pending/closed periods per employee exactly as 270 does
(one set of queries per employee is acceptable at the 50-employee cap; do not add a per-day query).

Preview/apply read the same classification (`_classify`), so they cannot disagree. Preview writes nothing.

### Logging
INFO "Bulk range regularization by HR: tenant=… employees=… day_status=… applied=… skipped=… failed=…"; WARNING at each whole-call refusal. No notes, no names.

## Files
`backend/app/modules/attendance/{regularize_range,router,schemas}.py`, tests in `backend/app/tests/modules/test_attendance_regularize_range.py` (or a new
`test_attendance_regularize_bulk.py`) and `test_authz.py` for the gate.

## Acceptance criteria
- [x] Single-employee endpoints' behaviour and tests unchanged after the refactor
- [x] Preview for N employees writes nothing (row counts in requests/punches/attendance/audit unchanged) and returns one block per employee in the order requested
- [x] Apply: employees succeed/fail independently — one employee's blocked/failed days do not stop another's; per-employee counts add up to the totals
- [x] Each of `present`, `half_day`, `wfh` works through the bulk path (spot-check status, payable fraction, location)
- [x] 404 when any id belongs to another tenant (and nothing is written for the valid ones); 403 for a reporting manager and for a role without APPROVE ATTENDANCE; 401 without token
- [x] 422: empty / duplicate / >50 employees, >1,000 employee-days, blank note, bad `day_status`/`half` combination, `to_date < from_date`
- [x] One summary notification per employee; one activity row per employee
- [x] Encrypted round-trip test for the new routes
- [x] `uv run pytest` green for the attendance, shifts, authz and import suites

## As built (2026-10-27)
`apply` / `preview` now wrap `_apply_employee` / `_classify`; `apply_bulk` / `preview_bulk` loop them. `_require_hr_for_all` resolves every id in one tenant-scoped query and
404s the whole call if any is missing, before the org-wide check's result matters for the others (both checks run before anything is read or written). The shared audit fields
moved to `_RegularizeReason`. Preview returns an extra `employee_count`. Tests: `test_attendance_regularize_bulk.py` (16) + 6 gate cases in `test_authz.py`.
Not covered by a test: the exact 50-employee boundary (51 → 422 is).

Completed: 2026-10-27
