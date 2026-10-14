---
task: 149
title: Docs — leave policy masters, provider mappings, year close, encashment
status: done
depends_on: [137, 138, 139, 140, 141, 142]
---

# 149 — Docs update

## Scope
Update `hrms/docs/leave-and-attendance/leave/`:
- `domain-model.md` — the four tables exactly as the DBML; `employee_type_master_id` dropped;
  unique (policy, leave type); nullable-date semantics; DEFAULT / LEGACY_V<n> backfill.
- `ledger.md` §7.1 — provider-mapping resolution replaces corp-only precedence; winner takes all;
  tie-break order; corp-scoped details. New sections: leave-year close, encashment.
- `admin-configuration.md` / `api-and-pages.md` — new HR Admin screens + endpoints; Employee /
  Manager read-only surfaces.
- "Changing a policy" runbook: edit in place vs New version (+ move assignments), and why.
- `docs/leave-and-attendance/shared/jobs-and-scheduling.md` — the three leave jobs and their
  order: `leave_accrual_dispatch` 02:00 → `leave_first_credit` 02:30 → `leave_year_close` 03:00;
  Yearly up front vs Monthly/Quarterly in arrears; the 30-day first-credit window; the scheduler
  cursor meaning ("start of the next unprocessed period") and `scripts/fix_leave_accrual_cursors.py`.
- `gaps.md` — close #4 (employee-type targeting now via mappings).
- Mark `.plans/leave-type-policy-defaulting.md` §2 ("no mapping table") as superseded.
- CLAUDE.md pointer only if a non-obvious flow needs one (e.g. the orphan-revision migration
  apply for hrms-dev).

## Acceptance criteria
- [x] Docs match shipped behaviour, verified against the code.

## Progress (29-Sep-26)
Written in the top-level `hrms/` clone (with the code it documents, branch `feature/gowtham_LeaveMasters`, uncommitted).
Every statement was checked against the code (models, `3c8e5a1f7d20`, `policy_service`, `assignment_service`,
`leave_policy_resolution_service`, `leave_accrual_service`, `leave_year_close_service`, `encashment_service`,
`job_defs`, `router.py`, `schemas.py`).
- `leave/domain-model.md` §5.2 (new): the three policy tables as built (keys, indexes, nullable-date semantics,
  one rule per leave type, `employee_type_master_id` dropped, app-level assignment rules + 409 shape),
  the `DEFAULT` / `LEGACY_V<n>` backfill, and the hrms-dev orphan-revision apply (§5.2.5). §5.1 notes the
  `allow_half_day` default and that types have no accrual fields.
- `leave/ledger.md`: §7.1 rewritten (provider-mapping resolution, tie-break order, winner takes all, the
  Doctor/Clinical/Standard example, corp-scoped rules). §7.2 gained accrual timing (Yearly up front,
  Monthly/Quarterly in arrears). §8 was rewritten to the **shipped** year close (2 rows: `LapseExpiry −unused` + `CarryForward
  +carry`; the old doc described 3), with governing rule, deferral, idempotency and what isn't applied. New §9 covers encashment.
- `leave/admin-configuration.md`: §5 is the three-tab screen (types, policies stepper, assignments + Check an
  employee). New §6 is the "Changing a policy" runbook (edit in place vs New version + move assignments, and why).
- `leave/api-and-pages.md`: status note, §2 pages (admin tabs, My Leave rules/history, manager profile Leave
  tab + no-write note), §3 endpoint index (policies, policy-details, assignments, resolution, encashment,
  `/me/policy`, `/me/ledger`, legacy bridge), new §4.14–4.16 samples.
- `shared/jobs-and-scheduling.md`: the three leave jobs + order (02:00 → 02:30 → 03:00), Yearly vs
  arrears, the 30-day first-credit window (the doc wrongly said it was gone), cursor meaning and
  `scripts/fix_leave_accrual_cursors.py`.
- `leave/gaps.md`: #4 closed (superseded by mappings); #9 mostly resolved (ledger views built; adjust UI still
  missing); #10 backend flow built, no UI; #40 now describes what the code does on a corp transfer.
- `leave/vocabularies.md`: ledger `source` values (SCHEDULED / ONBOARDING / ELIGIBILITY / YEAR_CLOSE / ENCASHMENT).
- `leave-and-attendance/README.md`: `employee_type_masters` exists now.
- `.plans/leave-type-policy-defaulting.md` §2 marked superseded.
- `hrms/CLAUDE.md`: a short pointer on the hrms-dev orphan revision (hand-written, guarded migrations).

Completed: 2026-09-29
