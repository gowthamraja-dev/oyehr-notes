---
task: 142
title: Leave encashment eligibility + ledger transaction
status: done
depends_on: [138]
---

# 142 — Leave encashment eligibility + transaction

## Scope
Leave decides eligibility and quantity; payroll consumes the transaction later (no payroll math,
no payroll changes). Existing ledger columns only.
- `GET /leave/employees/{id}/encashment?leave_type_id=` → `{eligible, encashable_quantity,
  available_balance, max_encashment}`. Eligible only when the employee's resolved detail (138) has
  `encashable = true`; quantity = `min(available_balance, max_encashment)` (no cap if NULL), never
  negative.
- `POST /leave/employees/{id}/encashment` `{leave_type_master_id, quantity, remarks}` — gated
  `APPROVE LEAVE`; under the ledger lock writes one `Encashment` debit (`-quantity`) with
  `leave_policy_detail_id`; rejects `quantity > encashable_quantity` or a non-encashable type.
- `list_encashments(db, tenant_id, employee_id, from_date, to_date)` for payroll to read later.

## Files
- `hrms/backend/app/modules/leave/encashment_service.py` (new), `schemas.py`, `router.py`
- `hrms/backend/app/tests/modules/test_leave_encashment.py` (new)

## Acceptance criteria
- [x] Non-encashable → `eligible=false`, POST 422. Cap respected. Ledger balance reduced.
- [x] 403 without APPROVE; cross-tenant 404; `log_activity` on POST.

## Verification notes
- `test_leave_encashment.py` — 13 tests: eligibility (available 10, cap 4 → 4 encashable), record 3
  → `Encashment −3` row with `leave_policy_detail_id` / `ENCASHMENT` / the current leave year,
  balance 7; afterwards already-encashed 3 → 1 left, requesting 2 → 422 and balance unchanged;
  uncapped rule encashes the whole balance, then "Nothing left"; non-encashable → eligible=false +
  POST 422; no policy → eligible=false + 422; quantity 0 / negative / 3 decimals → 422;
  `user_activity_details` row on record; 401 both routes; manager can check a report (200), not a
  non-report (403), and can never record (403); admin with a READ-only LEAVE grid → POST 403;
  another tenant's employee or leave type → 404; `list_encashments` filters by tenant, employee
  and date window. Full leave set + `test_authz.py`: 300 passed.

## Decisions made while building
- **`max_encashment` is a per-leave-year cap** (sum of this year's `Encashment` rows counts
  against it) — a per-transaction cap would let repeated encashments bypass it.
- **Recording is HR-only** (`sees_all_employees`, on top of the `APPROVE LEAVE` gate) — a line
  manager with APPROVE for leave requests must not be able to convert a report's leave into pay.
  Reading eligibility is manager-or-admin, like the other `/employees/{id}/…` leave reads.
- Encashable = available balance (ledger − pending requests), so days already reserved by a
  pending request can't also be encashed; the decision and the debit happen under the series'
  advisory lock.
- Encashment always applies to the leave year current on the day it's recorded.

Completed: 2026-09-29
