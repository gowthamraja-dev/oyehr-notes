---
task: 42
title: Leave request, day-row and balance-ledger models + migration
status: done
depends_on: [21]
---

# 42 — Leave request, day-row and balance-ledger models + migration

## Discussion

Everything built so far under [[21-leave-policy-models-migration]]/[[22-leave-type-api]]/
[[23-leave-policy-api]] is leave **configuration** (types, policies) — no employee has ever
been able to actually apply for leave. This task lays the data foundation for that: the three
tables `docs/leave-and-attendance/leave/domain-model.md` §5.3–5.5 specifies but that don't exist
yet, plus a request-level audit table mirroring `leave_policy_audits`.

Read `docs/leave-and-attendance/leave/domain-model.md` §5.3–5.5 and `ledger.md` (all of it,
already read in this planning pass) before writing the models — the columns, keys and lifecycle
rules below are restated, not derived from scratch, from those docs. Do not re-derive the
ledger's append-only rules independently; they are load-bearing for [[43-leave-ledger-service]].

**Explicitly out of scope for this task and the whole leave-request arc (42-51):** the accrual
job, the carry-forward/rollover job, comp-off, encashment, and multi-stage approval workflows.
No job-runner mechanism exists anywhere in this repo
(`docs/leave-and-attendance/shared/jobs-and-scheduling.md`) and building one is a separate,
much larger initiative. Balances in this arc are seeded/corrected only via the manual
`Opening`/`Adjustment` ledger entry point built in [[45-leave-manager-approval-api]] — matching
CLAUDE.md-adjacent project scope ("complex accrual automation" excluded from v1) and
`gaps.md`'s existing deferrals (#1 comp-off, #10 encashment, #29 multi-stage).

## Files

### New models — `backend/app/models/`

1. `leave_request_detail.py` — `LeaveRequestDetail` → `leave_request_details`. Columns per
   `domain-model.md` §5.3: `employee_master_id` (FK `employee_masters.id`), `leave_type_master_id`
   (FK), `from_date`/`to_date` (Date), `from_half`/`to_half` (`String`, nullable, `FirstHalf` |
   `SecondHalf`), `total_days` (`Numeric(5,2)`), `reason` (Text), `contact_during_leave`
   (`String`, nullable), `status` (`String`, `Pending|Approved|Rejected|Cancelled`),
   `applied_at` (DateTime tz, `server_default=func.now()`), `approver_user_id` (FK `users.id`,
   nullable — resolved at apply time, per `employee-self-service.md` §5),
   `approver_remarks`/`rejection_reason` (Text, nullable), `actioned_at` (DateTime tz, nullable),
   `cancelled_at` (DateTime tz, nullable), `cancelled_by_id` (BigInteger, nullable), plus the
   standard tenant FK + `is_active`/`archive`/audit columns per CLAUDE.md conventions. **No
   `leave_year` column** — deliberate, per §5.3's note; it is derived from the day rows.
   Index: `ix_leave_request_details_employee_from_date` on `(employee_master_id, from_date)`.

2. `leave_request_day_detail.py` — `LeaveRequestDayDetail` → `leave_request_day_details`.
   `leave_request_detail_id` (FK, indexed), `leave_date` (Date), `day_fraction`
   (`Numeric(3,2)`), `is_week_off` (Boolean), `is_holiday` (Boolean). Unique constraint
   `uq_leave_request_day_details_request_date` on `(leave_request_detail_id, leave_date)`. No
   tenant FK needed directly — reachable via the parent request. No `is_active`/`archive` —
   rows live and die with the parent request (delete-and-rebuild on edit, per `ledger.md` §2.6).

3. `employee_leave_balance_ledger.py` — `EmployeeLeaveBalanceLedger` →
   `employee_leave_balance_ledgers`. **Append-only — no archive columns, per `domain-model.md`
   §5.5.** Columns: tenant FK, `employee_master_id` (FK), `leave_type_master_id` (FK),
   `leave_year` (Integer), `txn_type` (`String`, `Opening|Accrual|Availed|Reversal|
   CarryForward|Encashment|LapseExpiry|Adjustment`), `quantity` (`Numeric(6,2)`, signed),
   `balance_after` (`Numeric(6,2)`), `effective_date` (Date), `leave_request_detail_id`
   (BigInteger, nullable — no FK per the doc listing it optional, but add the FK since the
   referenced table now exists), `reversal_of_id` (FK to this same table, nullable), `remarks`
   (String, nullable), `created_by_id` (BigInteger, **nullable** — the future accrual job writes
   rows with no human actor), `is_active` (Boolean, `server_default=text("true")`),
   `updated_by_id` (BigInteger, nullable), `created_at`/`updated_at` (DateTime tz,
   `server_default=func.now()` on both — **do not** add `onupdate=func.now()` to `updated_at`;
   per `ledger.md` §5.3 the rule is `updated_at` always equals `created_at` and this column is
   never touched again after insert). Index: `ix_employee_leave_balance_ledgers_employee_type_year`
   on `(employee_master_id, leave_type_master_id, leave_year)`.

4. `leave_request_audit.py` — `LeaveRequestAudit` → `leave_request_audits`. Mirrors
   `leave_policy_audit.py` exactly (append-only, no `updated_at`): tenant FK,
   `leave_request_detail_id` (FK, indexed), `action` (`String(20)`, `CREATED|APPROVED|REJECTED|
   CANCELLED`), `changes` (`String(2000)`, nullable — e.g. rejection reason echoed, or the dates
   for a pending-request edit), `performed_by_id` (BigInteger), `created_at`. No table for this
   exists in the domain-model doc (it predates request-level features); this is a new addition
   following the same precedent `leave_policy_audits` itself set (`domain-model.md` §5.6: "no
   generic audit table exists anywhere in this codebase to reuse instead").

Register all four in `backend/app/models/__init__.py`, one `# noqa: F401` import line each.

### Migration

```
uv run python scripts/migrate.py revision --autogenerate -m "leave request day rows and balance ledger"
```

Hand-edit before applying to add the partial unique index `ledger.md` §7.4 / `gaps.md` #19
mandates — **the single highest-value schema addition in the whole leave-and-attendance
corpus**, without which a double-run of a future accrual job silently doubles every balance:

```sql
CREATE UNIQUE INDEX uq_leave_ledger_system_txn
  ON employee_leave_balance_ledgers
     (care_delivery_program_master_id, employee_master_id, leave_type_master_id,
      leave_year, txn_type, effective_date)
  WHERE txn_type IN ('Accrual','CarryForward','LapseExpiry','Opening');
```

`Availed`, `Reversal`, `Adjustment`, `Encashment` stay unconstrained — multiple legitimate rows
can share a date (e.g. two approvals landing on the same `effective_date`, or a reversal
followed by a re-approval).

Apply with `uv run python scripts/migrate.py upgrade heads` — **not** bare `alembic upgrade
head` (CLAUDE.md's nhforms two-head rule).

## Acceptance criteria

- [x] All four models exist, registered in `models/__init__.py`, one file per table.
- [x] Migration applies cleanly and the partial unique index exists (verified with `\d
      employee_leave_balance_ledgers` in `psql` — `uq_leave_ledger_system_txn` present with the
      correct partial `WHERE` clause).
- [x] `employee_leave_balance_ledgers` has no `archive`/`archived_at`/`archived_by_id` columns.
- [x] `leave_request_day_details`' unique constraint rejects a duplicate
      `(leave_request_detail_id, leave_date)` insert — spot-checked directly against the dev DB
      in a rolled-back transaction; got `duplicate key value violates unique constraint
      "uq_leave_request_day_details_request_date"`.
- [x] No model in this task references `employee_type_master_id` as a real FK — it stays absent
      per `gaps.md` #4's resolution (that gap is about `leave_policy_details`, already built;
      this task doesn't reopen it).

Completed: 2026-08-18
