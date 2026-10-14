---
task: 24
title: Leave Policy backend — full test coverage
status: done
depends_on: [22, 23]
---

## As-built notes

Most of this checklist was already satisfied incidentally by the tests written alongside
[[22-leave-type-api]] and [[23-leave-policy-api]] (CLAUDE.md's "add tests in the same change as
the feature" rule) — this task's actual work was auditing that coverage against the checklist
below and closing the gaps found:

- **Auth/admin gating was only spot-checked per route family**, not exhaustively. Replaced the
  ad hoc checks with two fully parametrized tests (`test_leave_endpoints_require_authentication`,
  `test_leave_endpoints_require_admin`) covering all 9 route/method combinations (4 leave-type,
  5 leave-policy) in one table-driven pair, following `test_shifts.py:82-90`'s pattern.
- **Cross-tenant GET isolation** was only tested for `PATCH .../policies/{id}`; added the GET-side
  equivalents (`GET .../policy`, `GET .../policies` against another tenant's leave type both
  404) plus `PATCH .../status` cross-tenant.
- **Audit `action="UPDATED"`** was never explicitly asserted (only `CREATED`/`DEACTIVATED` were).
  Added `test_audit_action_updated_on_patch`.
- **Audit append-only immutability** (a row's `created_at` must never change after a later,
  unrelated mutation) had no test. Added `test_audit_rows_are_never_updated_after_insert`.
- **Status-patch no-op writes no audit row** — extended `test_audit_written_on_success_and_not_on_rejection`
  to also assert a repeat `is_active: false` patch (already false) adds nothing.
- `test_leave.py` grew from 41 to 57 tests; no scope beyond auditing/filling this checklist.

# 24 — Leave Policy backend — full test coverage

## Scope

Bring `backend/app/tests/modules/test_leave.py` (started incidentally in
[[22-leave-type-api]]) up to the coverage bar CLAUDE.md and
`docs/leave-and-attendance/leave/api-and-pages.md` §7 both require. Mirrors
`test_shifts.py`'s structure and fixture style — read that file's top ~60 lines (local
`admin_token` fixture built from `tenant`, path-parametrized auth/admin-gating tests) before
writing this one.

## Files

- `backend/app/tests/modules/test_leave.py`

## Fixtures needed (module-local, following `test_shifts.py:53`'s pattern — no shared
`admin_token` fixture exists in `conftest.py`)

- `admin_token(client, tenant, db_session)` — mints a JWT for the `tenant` fixture's admin user,
  same shape as `test_shifts.py`'s version
- A second `CareDeliveryProgramMaster` + `CorpMaster` + membership, built inline in the
  cross-tenant tests, same as `test_employees.py` does — for isolation tests

## Required coverage

### Auth / admin gating (parametrized over every route, like `test_shifts.py:83-88`)

- [x] `test_endpoints_require_authentication` — every `leave` route returns `401` with no token
- [x] `test_endpoints_require_admin` — every route returns `403` for a non-admin `tenant` token

### Leave types

- [x] Create, list (empty → populated), patch, archive (soft) round-trip
- [x] Duplicate `code` within a tenant → `422`; same `code` across two tenants → both succeed
- [x] Archiving a type with a live policy → `409`
- [x] Negative `min_notice_days` / `doc_required_after_days` / `max_consecutive_days` /
      `applicable_after_days` → `422`
- [x] Cross-tenant: tenant B never sees tenant A's leave types in `GET /leave/types`

### Leave policies

- [x] `GET .../policy` with no policy yet → `404` with the `NO_POLICY` body shape (leave type
      still present in the body)
- [x] Create a policy, `GET .../policy` resolves it
- [x] `accrual_frequency` outside the four literal values → `422`
- [x] `reset_month` outside `1..12` (e.g. `0`, `13`) → `422`
- [x] Negative `accrual_quantity` / `max_balance` / `max_carry_forward` / `max_encashment` →
      `422`
- [x] `trmntn_dt < effctv_dt` → `422`
- [x] Create with `carry_forward=false` and a non-null `max_carry_forward` → `422`; same for
      `encashable=false` + `max_encashment`
- [x] Patch with `carry_forward: false` on a policy that currently has `max_carry_forward` set →
      response has `max_carry_forward: null`, regardless of what was sent in the patch body
- [x] Two policies for the same type, same corp-specificity tier, overlapping dates → second
      create returns `422` ("Another policy already covers this effective period")
- [x] A corp-specific policy and an all-corps policy over the *same* dates for the same type →
      both creates succeed
- [x] Resolution precedence: with both a corp-specific and an all-corps active policy for the
      same type/date, `GET .../policy?corp_master_id=<that corp>` returns the corp-specific one;
      omitting the query param (or passing a different corp) returns the all-corps one
- [x] Patching a **future-dated** policy (`effctv_dt` in the future) mutates the same row —
      `GET .../policies` still shows exactly one row for it
- [x] Patching an **already-effective** policy (`effctv_dt <= today`) produces two rows: the old
      one now `trmntn_dt`-closed, a new one with the patched values — assert both are present via
      `GET .../policies` and the old row's data is unchanged (history preserved)
- [x] `PATCH .../status` flips `is_active` without touching `effctv_dt`/`trmntn_dt`
- [x] Cross-tenant: tenant B cannot `GET`/`PATCH` tenant A's policy by id (`404`, not a
      cross-tenant leak)

### Audit

- [x] A successful create/update/status-change writes exactly one `leave_policy_audits` row with
      the right `action`
- [x] A rejected (422) create/update writes **zero** audit rows
- [x] `leave_policy_audits` rows are never updated after insert — no code path in `service.py`
      should `UPDATE` this table; assert by re-reading a row's `created_at` after a later,
      unrelated mutation and confirming it hasn't changed

### Encryption

- [x] One encrypted round-trip test per route family (types, policies), following
      `test_encryption.py`'s pattern — encrypt a request, confirm the response is the
      `{iv, ct}` shape when hit without decrypting, then confirm the `client` fixture's transparent
      decrypt path returns the expected plaintext object

## Acceptance criteria

- [x] `uv run pytest app/tests/modules/test_leave.py -v` — all pass
- [x] `uv run pytest` (full suite) — no regressions in other modules
- [x] Every checklist item above has a corresponding test function

Completed: 2026-08-17
