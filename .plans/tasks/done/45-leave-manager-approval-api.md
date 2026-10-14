---
task: 45
title: Manager approval queue — approve, reject, balances, manual ledger adjustment
status: done
depends_on: [43, 44]
---

# 45 — Manager approval queue — approve, reject, balances, manual ledger adjustment

## Discussion

The **manager** predicate arrives in `leave/service.py` for the first time. Per `README.md`
§3.3: the target's `reporting_manager_id` must equal the caller's `employee_master_id` — direct
reports only, not transitive. An `admin` caller sees the whole CDP. **A manager acting on a
non-report gets `403`, not an empty result** — this codebase's established rule (see
`shifts/service.py`'s `list_shift_assignments`, `40-shift-auto-assignment-engine.md`'s scope
resolution) applies identically here; mirror that existing scoping helper's shape rather than
inventing a new one.

### Endpoints — `backend/app/modules/leave/router.py`

Per `api-and-pages.md` §3.1b/§3.2 and the sampled contracts §4.10–§4.12:

| Method | Path | Who | Notes |
| --- | --- | --- | --- |
| GET | `/requests` | M, A | `?status=&employee_master_id=&from=&to=` — approval queue. Manager sees direct reports only; admin sees the CDP; a manager passing a non-report `employee_master_id` → `403` |
| GET | `/requests/{id}` | M, A, S (already built in [[44]] for S) | Detail shape per §4.10 — `balance`, `attachments`, `approval_flow`, `can_approve`/`can_reject`/`can_cancel` |
| POST | `/requests/{id}/approve` | M, A | See re-validation below |
| POST | `/requests/{id}/reject` | M, A | `reason` mandatory |
| GET | `/employees/{id}/balances` | M, A | For the approval modal's balance strip — reuses [[44]]'s balance-computation code, parameterized by target employee instead of caller |
| GET | `/employees/{id}/ledger` | A only | Raw ledger rows — no manager-facing mockup for this (`gaps.md` #9); keep admin-only until a UI need for managers appears |
| POST | `/employees/{id}/ledger/adjust` | A only | Writes one `Adjustment` row via `ledger_service.write_ledger_entry`. **This is the only leave-balance seeding mechanism in v1** — see the scope note in [[42]]'s discussion. Body: `{leave_type_master_id, leave_year, quantity, effective_date?, remarks}`. `quantity` is signed — a negative value is a legitimate correction, not an error |

### Approve — `ledger.md` §5.2/§6.2, `manager-approvals.md` §2.4

Inside the advisory lock for `(tenant, employee, leave_type, leave_year)` — **note a request
straddling a leave-year boundary needs the lock (and a separate `write_ledger_entry` call) for
*each* leave year it touches**, per `ledger.md` §4.1:

1. Re-check `status == Pending` (guards a double-click / two-manager race — return `409` if not).
2. Re-run the overlap gate (built in [[43]]) — another request may have been approved since.
3. Re-run the balance gate against **current** `available_balance` — may have moved. On
   failure, `409` with both numbers: `"Balance changed since this request was raised: requested
   {X}, available {Y}"` (verbatim shape from `manager-approvals.md` §2.4).
4. Enforce the document gate **here** (not at apply time) — `requires_document` needs an
   `image_details` row already attached via [[44]]'s attachment endpoint; if missing, `422`.
5. On success: `status → Approved`, `approver_user_id`/`approver_employee_master_id` (caller,
   not the applicant's own resolved approver — the caller performing this action *is* the
   approver of record) and `actioned_at` set. One `Availed` ledger row **per leave year
   touched**, `quantity = -Σ day_fraction` for that year's days. Write
   `leave_request_audits`, `action="APPROVED"`.
6. Queue the affected attendance dates for rebuild — this task calls
   `attendance_recompute_service.recompute_attendance_day` directly, once per affected date, in
   the same transaction (no job queue exists — see [[42]]'s scope note on jobs generally; a
   handful of dates per approval is cheap enough to do inline). This is the hook
   [[46-leave-attendance-integration]] depends on existing correctly *before* it can be
   exercised — build [[46]] first if you want attendance to actually observe the new `Availed`
   status in the same PR; otherwise the call here is a no-op until [[46]] lands (calling an
   unmodified `recompute_attendance_day` is harmless — it just won't yet reflect the leave).
   Sequence these two tasks in whichever order the implementer prefers; this task's job is only
   to make the call, not to make attendance leave-aware.

### Reject

`reason` mandatory (`422` if blank/whitespace). `status → Rejected`, `actioned_at`/
`approver_user_id` set, **no ledger row**. Write `leave_request_audits`, `action="REJECTED"`,
`changes` = the reason text.

### Manager's own cancel-on-behalf-of

`api-and-pages.md` §3.2 lists `POST /requests/{id}/cancel` as also reachable by M — reuse
[[44]]'s cancel implementation, just widen its authorization check to accept the manager
predicate for the target's own reports (same re-check logic, same ledger effects).

## Files

- `backend/app/modules/leave/router.py`, `schemas.py`, `service.py`
- `backend/app/tests/modules/test_leave.py`

## Tests

- Queue: manager sees only direct reports' requests; admin sees the whole CDP; manager +
  non-report `employee_master_id` → `403`.
- Approve happy path: `Pending → Approved`, correct `Availed` row(s), `actioned_at` set,
  `leave_request_audits` row written.
- Approve across a leave-year boundary: two `Availed` rows, correct `leave_year` on each.
- Approve re-validation failures: overlap appeared since apply → `422`/`409` (pick the code
  matching this module's existing convention — check what `23-leave-policy-api` used for a
  similar "state changed underneath you" case); balance insufficient at approve time even though
  it was sufficient at apply time → `409` with both numbers; missing required document → `422`.
- Concurrent approve: two near-simultaneous `POST .../approve` calls for the same request — only
  one succeeds in transitioning `Pending → Approved` (the other gets `409` "already actioned"),
  and exactly one `Availed` row exists afterward. This is the ledger's concurrency proof from the
  manager side, complementing [[43]]'s raw `write_ledger_entry` concurrency test.
- Reject: missing reason → `422`; success writes no ledger row.
- `POST /employees/{id}/ledger/adjust`: writes exactly one `Adjustment` row with the given
  signed quantity; non-admin caller → `403`.
- Full 401/403/cross-tenant/encrypted-round-trip sweep for every new route.

## Acceptance criteria

- [ ] A manager can see their team's queue, open a request's detail, approve or reject it, and
      the numbers shown in the balance strip are `available_balance`, not raw `ledger_balance`.
- [ ] Approve is transaction-safe under concurrency — two managers (or one manager double-
      clicking) cannot both debit the ledger for the same request.
- [ ] Reject always requires a reason and never touches the ledger.
- [ ] Admin can manually seed/correct a balance via the adjustment endpoint; no other code path
      writes an `Opening` or `Adjustment` row in this arc.

Completed: 2026-08-18
