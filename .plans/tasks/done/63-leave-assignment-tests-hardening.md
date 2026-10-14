---
task: 63
title: Leave assignment tests hardening — concurrency, idempotency, full auth/scoping sweep
status: done
depends_on: [62]
---

# 63 — Leave assignment tests hardening — concurrency, idempotency, full auth/scoping sweep

## Discussion

Mirrors [[48-leave-request-tests-hardening]]'s role in the leave-request arc: [[62]] ships with
its own basic tests, this task is the dedicated hardening pass covering concurrency, the
idempotency/duplicate-assignment guarantee, and the full org-scoping/permission sweep the design
doc's acceptance criteria (§33) and business rules (§25 rules 9, 10, 12) call for explicitly.
Add to `backend/app/tests/modules/test_leave.py` (same file every prior leave task has extended —
no new test file per this module's established convention).

## Tests

- **Concurrency — duplicate system-sourced assignment.** Two near-simultaneous
  `POST .../leave-assignments` calls with `source_type="Policy"` for the same
  `(employee, leave_type, leave_year)`: only one succeeds, the other gets `409`, and exactly one
  matching `Accrual` ledger row exists afterward. This is the assignment-table analogue of
  [[45]]'s concurrent-approve test, proving the [[61]] partial unique index actually serializes
  under real concurrency, not just in a single-threaded duplicate-insert check.
- **Concurrency — retried create (double-click).** The same `POST` body submitted twice
  sequentially (simulating a retried request per design doc §10) for a `Manual` assignment (which
  has no uniqueness constraint) is *expected* to create two separate assignments/ledger rows —
  confirm this is correct behavior per the design (Manual adjustments are not naturally
  idempotent; idempotency for Manual would need a client-supplied idempotency key, which is out
  of scope here) and assert the count is exactly 2, not silently 1 — so a future change to add a
  Manual idempotency key has a red test to turn green rather than a silent gap.
- **Cancel then reassign.** Cancel a Policy assignment, then create a new Policy assignment for
  the same employee/type/year → succeeds (the partial unique index's `WHERE status = 'Active'`
  clause lets this through) — verify both the old (`Cancelled`) and new (`Active`) rows coexist
  and the ledger shows `Accrual +N`, `Reversal -N`, `Accrual +M` in that order.
- **Balance correctness after cancel.** `GET /employees/{id}/balances` reflects the reversal
  immediately (ledger_balance drops back down), matching design doc §8's "both entries remain
  auditable" and the existing `_balances_for_employee` computation.
- **Full auth sweep for every new route** (`POST/GET .../leave-assignments`,
  `POST .../leave-assignments/{id}/cancel`, and the now-loosened `GET .../ledger`): missing token
  → `401`; employee (self, non-manager, non-admin) → `403` on all five; manager of a non-report
  → `403` on all five; manager of a direct report → `200` on the two GETs, `403` on create/cancel;
  admin → `200`/`201` on all five for any employee in the CDP.
- **Cross-tenant.** An admin/manager token from tenant A requesting
  `/employees/{employee-in-tenant-B}/leave-assignments` (or `/ledger`) → `404`/`403` per this
  module's existing cross-tenant convention — reuse whatever `test_leave.py` already asserts for
  `get_employee_balances`'s cross-tenant case, applied identically here.
- **Validation sweep.** `assigned_units=0` for Manual → `422`; `assigned_units=-1` for
  `OpeningBalance` → `422`; `effective_from > effective_to` → `422`; `source_type="CompOff"` →
  `422` with a message referencing the comp-off gap; `source_type="Bogus"` → `422`.
- **Encrypted round-trip.** One test per new route confirming request/response actually travel
  encrypted end-to-end, following the existing `test_encryption.py` pattern already used
  elsewhere in this module (per CLAUDE.md's payload-encryption convention).
- **Audit rows.** Every successful create/cancel writes exactly one `leave_assignment_audits`
  row with the correct `action` and a non-null `performed_by_id`.

## Files

- `backend/app/tests/modules/test_leave.py`

## Acceptance criteria

- [x] `uv run pytest` passes with all tests above green.
- [x] The concurrent-duplicate-assignment test fails without [[61]]'s partial unique index
      (verified by temporarily reverting it locally, confirming the test actually catches the
      regression it's meant to catch, then re-applying).
- [x] No cross-tenant leak: every new/loosened endpoint rejects a target employee outside the
      caller's CDP.

Completed: 2026-08-19

Note: manually verifying the concurrency test's regression-catching power (dropping
`uq_leave_assignment_system_source` and re-running) surfaced a real test-design flaw in the
first draft — both threads used the same `effective_from`, so the *ledger's own* pre-existing
index (`uq_leave_ledger_system_txn`, keyed partly on `effective_date`) serialized them
independently of the new assignment-level index, meaning the test passed for the wrong reason.
Fixed by giving the two threads different `effective_from` dates within the same `leave_year` —
re-verified by hand that dropping the assignment index now genuinely lets both succeed, and that
restoring it makes the test fail-would-fail correctly. `uv run pytest` on `test_leave.py`: 161
passed. Full suite: 509 passed, 30 pre-existing unrelated failures (unchanged from [[61]]/[[62]]),
0 new failures.

