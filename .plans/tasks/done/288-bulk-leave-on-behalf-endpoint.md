---
task: 288
title: Bulk leave on behalf (preview + apply)
status: done
depends_on: []
---

# 288 — Bulk leave on behalf (preview + apply)

## Scope
The grid applies leave for many cells at once. Existing endpoints are per employee and per contiguous range: `POST /leave/employees/{id}/requests/record[/preview]` (leave already
taken, UPDATE LEAVE) and `.../requests/apply[/preview]` (on behalf; Pending to the approver, or `approve_now` with APPROVE LEAVE).

Add `POST /leave/requests/bulk-on-behalf/preview` and `POST /leave/requests/bulk-on-behalf`:
`{ mode: "record" | "apply", approve_now?: bool, leave_type_master_id, half_day?: {...as the single endpoints...}, reason, approver_remarks?, runs: [{employee_id, from_date, to_date}] }`.
The client turns the selected cells into per-employee CONTIGUOUS runs (task 292). Limits: 50 employees, 1,000 employee-days per request.

Each run goes through the SAME service function as the single endpoint (`record_leave_on_behalf` / `apply_leave_on_behalf`: policy resolution, ledger lock, gates, audit rows,
attendance rebuild) inside its own savepoint, so one run's failure never stops another (HTTP 200, per-run `applied | failed` with the violation message). Preview returns each run's gate
result without writing. Any foreign-tenant employee id 404s the whole call. Permissions per mode as the single endpoints; `approve_now` also needs APPROVE LEAVE.
Notify each employee once per applied run exactly as the single path does (do not add a new notification kind).

## Files
`backend/app/modules/leave/router.py`, `schemas.py`, `service.py` (thin bulk wrapper — do not copy gate logic), `backend/app/tests/modules/test_leave_bulk_on_behalf.py`, `docs/` note in task 294.

## Acceptance criteria
- [ ] Record mode and apply mode each produce the same rows as the single endpoint for one run (test compares)
- [ ] A run failing a gate (balance, overlap, notice, before opening balance) is reported per run; other runs still apply
- [ ] Cross-tenant id -> 404 for the whole call; missing UPDATE LEAVE -> 403; `approve_now` without APPROVE LEAVE -> 403
- [ ] > 1,000 employee-days or > 50 employees -> 422; one employee's runs are applied in date order under one ledger lock

## As built (2026-10-28)
`POST /leave/requests/bulk-on-behalf[/preview]` (`leave/bulk_on_behalf.py`, schemas `BulkLeave*`, routes in `router.py`). Runs carry their own `from_half`/`to_half`. A gate refusal is reported per run with the gate message (no rollback needed — gates run before any write); an unexpected error rolls back and reports "Unexpected error". Preview checks each run alone; apply re-checks in date order. Limits: 50 employees, 1,000 employee-days, 62 days per run, no overlapping runs per employee. `approve_now` only with `mode=apply`. 14 tests in `test_leave_bulk_on_behalf.py`.

Completed: 2026-10-28
