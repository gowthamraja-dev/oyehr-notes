---
task: 44
title: Employee self-service — apply, preview, cancel, balances, history
status: done
depends_on: [43]
---

# 44 — Employee self-service — apply, preview, cancel, balances, history

## Discussion

The **self** predicate arrives in `leave/service.py` for the first time — every route built so
far (`22`/`23`) is admin-only via `_require_admin`. Per `README.md` §3.3, self means "the caller
may only read/write their own `employee_master_id`, resolved via `users.id → employee_masters.
user_id`." Add a `_require_self_employee(db, principal) -> EmployeeMaster` helper (mirrors
`_require_caller_employee` already in `attendance/service.py` — check that file's version before
writing a second one; if it's generic enough, consider whether it belongs in a shared helper
instead of being copied, but don't over-engineer a one-caller abstraction if the attendance
version is attendance-specific).

Also **open `GET /leave/types` to the self predicate** — today it's admin-only
(`api-and-pages.md` §3, explicitly flagged as needing this exact change once a self-service
screen exists). Employees need the active-types list to populate the apply form's dropdown.
Keep the admin-only variant's behavior (e.g. seeing inactive types) distinct from the
self-facing one if the query params differ — simplest is: same route, `active_only` query param
already exists, self callers just get a 200 instead of a 403 when `active_only=true`... but
that means a self caller could still pass `active_only=false` and see archived types. Gate it:
self callers are forced to `active_only=true` server-side regardless of the query param they
send; admin keeps the existing behavior.

### Endpoints — `backend/app/modules/leave/router.py` (all under existing `EncryptedRoute`)

Per `api-and-pages.md` §3.3 and the sampled contracts in §4.8–§4.13/§4.13 (already read in this
planning pass — implement those exact shapes, don't re-derive):

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/requests/preview` | Dry-run — runs every gate from [[43-leave-ledger-service]], writes nothing, returns day rows + balance impact + `violations` (empty list = clean). Returns `200` even when blocked — only `POST /requests` itself returns `422` |
| POST | `/requests` | Apply. Runs all gates; on `requires_approval=false` immediately transitions to `Approved` and writes the ledger row in the same transaction (gate 11, `ledger.md` §6). Writes a `leave_request_audits` row, `action="CREATED"` |
| GET | `/me/requests` | `?status=&from=&to=` — own history only |
| GET | `/requests/{id}` | Detail — self predicate: 404 (not 403) if the request isn't the caller's own, matching the tenant-scoping convention elsewhere in this codebase (don't leak existence via a 403) |
| POST | `/requests/{id}/cancel` | See cancellation rules below. Writes `leave_request_audits`, `action="CANCELLED"` |
| GET | `/me/balances` | Per-type balance cards — shape in `api-and-pages.md` §4.13 exactly (`entitled`, `accrued`, `used`, `ledger_balance`, `pending_committed`, `available_balance`, `is_paid`) |
| POST | `/requests/{id}/attachment` | Plain `APIRouter` (not `EncryptedRoute` — multipart), same pattern as the image-upload router in `organizations/router.py`. Uses `image_service.upload_image` with `imageable_type="LeaveRequestDetail"` — add that entry to `image_service.py`'s `_FOLDER` map |

**`accrued`/`entitled` in `/me/balances`:** `entitled` is the resolved policy's `max_balance`.
`accrued` is "what has actually been credited so far" — since no accrual job exists yet
([[42]]'s discussion), in v1 `accrued` equals `ledger_balance + used` computed from ledger rows
present (whatever HR has manually credited via [[45-leave-manager-approval-api]]'s adjustment
endpoint), not a projected/expected accrual. Document this as the honest v1 behavior in a code
comment — don't fabricate a number the ledger can't back up.

### Cancellation (`employee-self-service.md` §3.3, `ledger.md` §4)

| Case | Effect |
| --- | --- |
| `status = Pending` | → `Cancelled`. No ledger row |
| `Approved`, before `from_date` | → `Cancelled`; `Reversal` row for the full `Availed` quantity |
| `Approved`, mid-leave (`today` between `from_date`/`to_date`) | → `Cancelled`; `Reversal` for `Σ day_fraction` of days with `leave_date > today` only |
| `Approved`, fully in the past | Rejected with `422` unless `allow_retro_leave_cancellation` — no CDP-knob storage exists yet ([[42]]'s scope note), so **hardcode this off** (always rejected) and leave a comment pointing at `config-knobs.md` §1.4 for where the real knob lands once `tenant_params.py` exists |
| `Rejected` / already `Cancelled` | `422` — nothing to cancel |

A cancellation that writes a `Reversal` row goes through `write_ledger_entry` inside the same
advisory lock as the original approval would have used — same `(tenant, employee, type,
leave_year)` key.

### Approver resolution (used here and re-used by [[45]])

Implement `resolve_approver(db, employee) -> tuple[int, int]` (returns `approver_user_id`,
`approver_employee_master_id`) per `employee-self-service.md` §5's table exactly: walk
`reporting_manager_id → employee_masters.user_id`; `None` manager → no fallback storage exists
yet (`fallback_approver_user_id` is an unbuilt knob per `config-knobs.md` — reject with a clear
`422` message rather than silently picking someone); manager is the applicant themselves →
reject; manager's `user_id` is `NULL` → reject. Store the *employee_master_id* too even though
`leave_request_details` per the original SQL sketch only has `approver_user_id` — add an
`approver_employee_master_id` column to the model added in [[42]] before this task starts
consuming it, resolving `gaps.md` #27 the same way `attendance_request_details` already does
(that table has both columns; this brings leave into parity rather than accepting the lossy
`users → employee_masters` join at read time).

> If [[42]] already shipped without this column, add it here as a follow-up migration rather
> than skipping the fix — check `leave_request_detail.py` before writing this task's code.

## Files

- `backend/app/modules/leave/router.py`, `schemas.py`, `service.py` — new endpoints
- `backend/app/services/image_service.py` — add `"LeaveRequestDetail": "leave-request"` (or
  similar) to `_FOLDER`
- `backend/app/tests/modules/test_leave.py` — extended

## Tests (in addition to [[43]]'s)

- Full apply → preview matches what apply actually creates (same day rows, same `total_days`).
- `requires_approval=false` type: apply immediately yields `status=Approved` with one `Availed`
  ledger row, no separate approve call needed.
- Every 401/403/404/cross-tenant case for each new route, `test_shifts.py`-style parametrized.
- Cancellation: all four cases in the table above, asserting the correct ledger effect (or lack
  of one) and the correct `leave_request_audits` row.
- `GET /leave/types` as a self caller always gets `active_only` behavior regardless of query
  param; as admin, unchanged.
- Encrypted round-trip test for the new encrypted routes; attachment upload tested with plain
  `fetch`-equivalent (multipart) per `test_encryption.py`'s exclusion of multipart routes.

## Acceptance criteria

- [x] An employee can preview, apply, view their own history, view one request's detail, cancel
      an eligible request, and see their balances — end to end, no admin action required except
      for a manager elsewhere to approve/reject ([[45]]). Covered end-to-end in
      `test_preview_matches_apply_day_rows_and_total` plus the dedicated history/detail/
      balances/cancellation tests.
- [x] No employee can read or act on another employee's request (404, not empty-list, not 403 —
      matches this codebase's existing tenant-scoping idiom of 404 for "not yours/not found").
      `test_request_detail_and_cancel_404_for_someone_elses_request` and
      `test_my_requests_excludes_other_cdp`.
- [x] `POST /requests` never writes a ledger row directly for a `Pending` result — only the
      `requires_approval=false` auto-approve path does, in the same transaction. Asserted in
      `test_preview_matches_apply_day_rows_and_total` (zero ledger rows for a Pending result) and
      `test_apply_auto_approves_when_requires_approval_false` (exactly one `Availed` row).
- [x] All acceptance criteria from [[43]] remain green after this task's changes — full
      `app/tests/` suite run: 380 passed, 21 failed, and every one of the 21 failures is one of
      three pre-existing clusters confirmed unrelated via `git stash` (18 in
      `test_admin_organizations.py` — stray committed data in the shared dev DB from outside
      this task; 2 in `test_engagement_email.py`; 1 `test_leave.py::
      test_audit_written_on_success_and_not_on_rejection` — the last two already flagged as
      pre-existing during [[43]]). Zero regressions introduced by this task.

Additional work done beyond the original spec, discovered while implementing:
- Added `approver_employee_master_id` to `LeaveRequestDetail` (migration `87d16637e3a9`) per this
  task's own instruction, resolving gaps.md #27.
- Changed `resolve_approver` (built in [[43]]) to return `tuple[int, int]` instead of `int`, and
  removed its now-unreachable `fallback_approver_user_id` branch per this task's exact wording
  ("no fallback storage exists yet ... reject"). Updated [[43]]'s test accordingly.
- Renamed `ledger_service._lock_ledger` to public `lock_ledger` — this task's apply-time balance
  gate needs to hold the lock itself before the balance read/decision, not just rely on
  `write_ledger_entry` taking it internally.
- Added `holiday_detail_id` to [[43]]'s `LeaveDayRow` dataclass (default `None`, non-breaking)
  so the preview endpoint can resolve `holiday_name` per api-and-pages.md §4.8's sample.

Completed: 2026-08-18
