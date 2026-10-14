---
task: 198
title: Home summary carries the real leave balance (drop the extra balances call)
status: done
depends_on: []
---

# 198 — Home summary carries the real leave balance (drop the extra balances call)

Built in the top-level `hrms/` clone (branch `feature/gowtham_HrmsDevConfig`), uncommitted.

## Scope
The Employee Home "Leave balance" tile made its own `GET /api/v1/leave/me/balances` call
because `GET /api/v1/home/summary` always returned `stats.leave_balance_days = null` (stale
"no leave module yet" stub). Fix the summary and make Home use it:

- **Backend** — `home.service.get_home_summary` fills `leave_balance_days` with the same
  number the tile used to compute client-side: the sum of `available_balance` over the
  caller's **paid** leave types, as returned by `leave.service._balances_for_employee`
  (types with a ledger row for the employee, active, not archived; available = ledger
  balance − pending committed). Exposed through a new public helper
  `leave.service.get_paid_available_days(db, tenant_id, employee) -> Decimal` so home does
  not import a private function.
  - Employee resolved **tenant-scoped** (home's `_resolve_caller_employee`, joins
    `corp_masters` on `principal.tenant_id`). No employee record in this CDP → `null`.
  - Employee with no credited types → `0`.
  - Schema type changes from `int | None` to `float | None` (balances are half-day
    granular; a `Decimal` would serialise as a JSON string).
- **Frontend** — `EmployeeHome.tsx` drops the `getMyLeaveBalances` call/state and reads
  `summary.stats.leave_balance_days`; shimmer while the summary loads, `—` / "not tracked
  yet" when null. `getMyLeaveBalances` itself stays in `api.ts` (My Leave still uses it).

Not in scope: the mobile app (it does not read `leave_balance_days`), announcements.

## Files
- `hrms/backend/app/modules/leave/service.py` — `get_paid_available_days`
- `hrms/backend/app/modules/home/service.py`, `schemas.py`, `router.py` (docstring)
- `hrms/backend/app/tests/modules/test_home.py` — summary leave-balance tests
- `hrms/frontend/src/dashboards/Employee/EmployeeHome.tsx`
- `hrms/frontend/src/lib/api.ts` — `HomeStats` comment

## Acceptance criteria
- [x] Summary returns the paid available-days sum (paid types only, pending requests deducted)
- [x] `null` without an employee record in the tenant; `0` with no credited types
- [x] Another tenant's ledger rows never count (org-scoping test)
- [x] Home page no longer calls `/leave/me/balances`; tile shows the summary value
- [x] `uv run pytest app/tests/modules/test_home.py` green; frontend type-check/lint clean on the touched file

Verified: test_home.py 24/24 and test_leave.py -k balance 13/13 on a throwaway pg:18 (local :5433 stack was down); tsc clean. Not smoke-tested in a running app.

Completed: 2026-10-08
