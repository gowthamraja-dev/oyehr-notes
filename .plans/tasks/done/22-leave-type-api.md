---
task: 22
title: Leave Type API — CRUD backend module
status: done
depends_on: [21]
---

## As-built deviations from the spec below

- **Duplicate `code` → `409 Conflict`, not `422`.** The spec below said 422; the actual
  `IntegrityError`-catch convention already used for unique-constraint violations elsewhere in
  this codebase (`app/modules/admin_organizations/service.py:230`, for subdomain conflicts) is
  `Conflict` (409). Followed that instead for consistency — a duplicate leave type code is
  "resource already exists," which 409 expresses more precisely than 422 anyway.
- **Router registered in `app/api/router.py`, not `app/main.py`.** That's where every other
  module's router is actually mounted (`api_router.include_router(...)`); `app/main.py` only
  imports the top-level `api_router`. The spec's file list was wrong about this.
- **Added `trmntn_dt >= effctv_dt` validation**, which this file's own Validation section called
  for but the initial field list omitted a corresponding schema/service check. Implemented as a
  Pydantic `model_validator` on `LeaveTypeIn` (both fields present at create) and a service-layer
  check in `update_leave_type` against the merged (patch + existing) values, following the same
  `data.get(field, current_value)` pattern `shifts/service.py:274-280` uses — validate before any
  `setattr`, so a rejected patch never leaves the ORM object mutated in memory.

# 22 — Leave Type API — CRUD backend module

## Scope

Backend module for `leave_type_masters` only. Policy CRUD (`leave_policy_details`) is
[[23-leave-policy-api]], which depends on this task existing first (a policy always belongs to
a leave type). Follow the `backend/app/modules/shifts/` shape (`router.py` / `schemas.py` /
`service.py`) — the most recently built module in this repo and the pattern to imitate, not the
prompt's suggested `/api/admin/leave` base path (see note below).

**Deviation from the prompt file on purpose:** the prompt suggests base path `/api/admin/leave`.
This repo's actual convention — every existing module (`shifts`, `employees`, `organizations`,
...) and `docs/leave-and-attendance/leave/api-and-pages.md` §3 — uses `/api/v1/<module>`. Use
`/api/v1/leave`, prefix `/leave`, router mounted alongside the other `app/modules/*/router.py`
routers in `app/main.py`.

## Files

- `backend/app/modules/leave/__init__.py` — new, empty (matches `shifts/__init__.py`)
- `backend/app/modules/leave/schemas.py` — new: `LeaveTypeIn`, `LeaveTypePatch`, `LeaveTypeOut`
- `backend/app/modules/leave/service.py` — new: `list_leave_types`, `create_leave_type`,
  `update_leave_type`, `archive_leave_type`
- `backend/app/modules/leave/router.py` — new, `router = APIRouter(prefix="/leave", tags=["leave"], route_class=EncryptedRoute)`
- `backend/app/main.py` — register the new router next to the `shifts` router include
- `backend/app/tests/modules/test_leave.py` — started here, extended by [[23-leave-policy-api]]
  and given full coverage in [[24-leave-tests]]

## Endpoints

All admin-only: `if not principal.is_admin: raise HTTPException(403)`, same pattern as
`backend/app/modules/shifts/service.py:66-68`. Every query filtered by
`principal.tenant_id` (no RLS — CLAUDE.md's tenancy rule).

| Method | Path | Request | Response |
| --- | --- | --- | --- |
| GET | `/leave/types` | `?active_only=true\|false` (default `false`) | `list[LeaveTypeOut]`, ordered by `display_order, name` |
| POST | `/leave/types` | `LeaveTypeIn` | `LeaveTypeOut`, `201` |
| PATCH | `/leave/types/{id}` | `LeaveTypePatch` | `LeaveTypeOut` |
| DELETE | `/leave/types/{id}` | — | `204`. **Not a physical delete** — sets `archive=true, archived_by_id, archived_at, is_active=false` (CLAUDE.md / prompt §21: never delete). Reject with `409` if any `leave_policy_details` row references this type and is not itself archived — force explicit policy archival first so a type can't vanish out from under a live policy |

### `LeaveTypeIn` (create)

Required: `name`, `code`, `effctv_dt`. Everything else optional with the model's defaults.

```
name: str
code: str
is_paid: bool = True
unit: Literal["Day"] = "Day"          # DB allows "Hour" but API rejects it in v1 — gaps.md #14
allow_half_day: bool = False
requires_approval: bool = True
requires_document: bool = False
doc_required_after_days: int | None = None
max_consecutive_days: int | None = None
min_notice_days: int = 0
allow_negative_balance: bool = False
gender_applicable: Literal["Male", "Female", "Other"] | None = None
applicable_after_days: int = 0
exclude_week_offs: bool = True
exclude_holidays: bool = True
display_order: int = 0
color_code: str | None = None
effctv_dt: date
```

### `LeaveTypePatch`

Same fields, all optional, `None` means "don't touch" (standard partial-update semantics — do
not use `None` to mean "clear the value" for any field here; there is no field on this table
where clearing to `NULL` is a meaningful admin action other than the nullable ones already
optional at create).

### `LeaveTypeOut`

All model columns plus a computed `policy_summary: str | None` — the short string the leave-type
list renders (prompt §7: `"21 days · Monthly"`, `"12 days · Yearly"`). Derive it from the type's
*resolved default policy* (the `corp_master_id IS NULL` row with the latest `effctv_dt <= today`
and `is_active = true`; `None` if no such row exists) as:
`f"{max_balance:g} days · {accrual_frequency}"` if `max_balance` is set, else just
`accrual_frequency`, else `None` if there is no active policy at all (empty-state trigger, prompt
§30). This is the one piece of policy-resolution logic this task needs before
[[23-leave-policy-api]] exists — implement it as a small private helper in `service.py` that
queries `leave_policy_details` directly; [[23-leave-policy-api]] will introduce the fuller
`resolve_leave_policy` and this helper should be redefined to call it once that lands (a one-line
follow-up, not a blocker).

## Validation

- `name` required, non-empty
- `code` required, non-empty, **unique per tenant** — `uq_leave_type_masters_cdp_code` gives a DB
  integrity error on violation; catch it and return `422` with a clean message
  (`"Leave type code '{code}' already exists"`), never leak the raw Postgres constraint-violation
  text (prompt §29)
- `min_notice_days`, `doc_required_after_days`, `max_consecutive_days`, `applicable_after_days` —
  reject negative values with `422`
- `effctv_dt` required on create; on patch, if `trmntn_dt` is also being set (or already set),
  enforce `trmntn_dt >= effctv_dt`

## Acceptance criteria

- [x] `GET /api/v1/leave/types` returns `[]` on a fresh tenant, populated list after creates,
      filtered by `active_only`
- [x] `POST /api/v1/leave/types` creates a row scoped to `principal.tenant_id`, sets
      `created_by_id`, rejects duplicate `code` within the same tenant with `409` (see deviation
      note above)
- [x] Same `code` in **two different tenants** both succeed (tenant-scoped uniqueness, not global)
- [x] `PATCH` updates only the supplied fields, sets `updated_by_id`
- [x] `DELETE` archives (soft) — row still exists in DB, `is_active=false`, and is excluded from
      `?active_only=true`
- [x] `DELETE` on a type with a live (non-archived) policy returns `409`, not a silent cascade
- [x] All endpoints reject non-admin callers with `403` and unauthenticated calls with `401`
- [x] Cross-tenant isolation: a second tenant's leave types never appear in the first tenant's list
- [x] Encrypted round-trip test (router uses `EncryptedRoute`) per `test_encryption.py`'s pattern

All 18 tests in `test_leave.py` pass; full suite run confirms 2 pre-existing unrelated failures
in `test_engagement_email.py` (verified via `git stash` — fail identically without this branch's
changes), no regressions introduced.

Completed: 2026-08-17
