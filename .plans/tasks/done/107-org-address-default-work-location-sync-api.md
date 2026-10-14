---
task: 107
title: Sync organization address into a default work location (backend)
status: done
depends_on: []
---

# 107 — Sync organization address into a default work location (backend)

## Scope

**The trigger:** `PUT /api/v1/organizations/address` (`backend/app/modules/organizations/router.py:96-101`
→ `service.save_address`, `backend/app/modules/organizations/service.py:489-516`) upserts the
CDP's single `address_details` row (`addressable_type='CareDeliveryProgramMaster'`). Today that
address is display-only. This task makes a complete org address also keep exactly one
`work_location_masters` row in sync — the tenant's **default work location** — so
"empty work locations" stops being a dead end: filling in the org's address (which the
frontend, per `OrgSettings.tsx:529-538` `isAddressValid()`, already *requires* — line 1,
country, state, city, pincode — before the whole Company Profile panel can save) is what
populates it.

**In scope:**
1. A new `is_org_default` boolean column on `work_location_masters` + migration.
2. A sync function in `organizations/service.py` that creates-or-updates that default
   location (and its own `address_details` row) whenever `save_address` runs, using the
   CDP's own address fields.
3. Exposing `is_org_default` on `WorkLocationOut`/`WorkLocationDetailOut` (read-only).
4. Blocking archive of the org-default location from the generic work-location archive
   endpoint (409), since an org should never be left with a dangling default.
5. Tests in `test_organizations.py` (sync behavior) and `test_attendance.py`/`test_authz.py`
   (archive guard).

**Explicitly NOT in scope** (leave for task 108 or later):
- Any frontend change — task 108 depends on this one and covers all UI.
- A backfill for tenants that already had a complete address before this feature shipped
  (deliberately dropped — the live sync on every `PUT /organizations/address` is the only
  path; a tenant that already has a complete address gets its default location the next time
  anyone opens Company Profile → Address and hits Save, which the "empty work locations"
  empty-state in task 108 already nudges them toward).
- Letting the org address form require lat/lng — `isAddressValid()` already doesn't require
  coordinates and this task doesn't change that; `lttd`/`lgtd` on the default location are
  simply whatever the org address currently has (nullable, exactly like any other location).
- A UI/API path to change which location is "the" default, or to have more than one — this
  task always keeps at most one `is_org_default=true` row per CDP, system-managed.
- Enforcing address completeness at the API layer (rejecting an incomplete `PUT /address`).
  The org address endpoint keeps accepting partial saves as it does today (other panels like
  contacts/CIN/GSTIN share the same "Save"); this task only makes the *default-location sync*
  conditional on completeness (see below), it never makes `PUT /address` itself fail.

## Design decisions (read before implementing)

**Where the sync function lives:** in `organizations/service.py`, NOT imported from
`attendance/service.py`. The attendance module's own docstring
(`backend/app/modules/attendance/service.py:23-25`) states the established precedent for this
codebase explicitly: "`_require_caller_employee` is duplicated here rather than imported from
`app.modules.shifts.service`... this module has no service-layer dependency on shifts." Follow
the same rule here — `organizations` gets its own small, local version of the
create-location / upsert-address logic (`WorkLocationMaster`, `CorpMaster`, `AddressDetail`
are just models, freely importable anywhere; it's *service* function cross-imports this repo
avoids). `organizations/service.py` has no `logging` import yet — add
`import logging` / `logger = logging.getLogger(__name__)` at module level along with this
change, per the repo's logging convention.

**Corp resolution:** `work_location_masters.corp_master_id` is `Mapped[int]` — **non-null**
(`backend/app/models/work_location_master.py:26`) — every location needs a real
`corp_masters` row. A CDP is 1-to-many with corps (`corp_masters.care_delivery_program_master_id`,
`backend/app/models/corp_master.py:25-26`), and while `admin_organizations/service.py:226-234`
always creates exactly one corp at org-creation time, nothing guarantees that stays true (it
can be archived, or more can be added later) — `leave/service.py:list_corps` (line 612) is a
plain `WHERE ... AND is_active` with no fallback and can legitimately return `[]`. So: resolve
the corp as **the CDP's oldest active corp** (`ORDER BY id ASC LIMIT 1`). If there is none,
**skip the sync silently** (log a warning, do not raise) — the org address save must still
succeed; it just doesn't get a default location yet until a corp exists. This is a genuine
edge case worth a code comment, not a hard failure.

**Completeness gate:** only sync when the org address actually has `address_line1`,
`city_master_id`, and `pin_code` set (the same three of the five fields
`OrgSettings.tsx`'s `isAddressValid()` checks that map onto `AddressIn`/`AddressOut` at all —
it also checks country/state, which aren't stored as IDs on `AddressDetail`, only resolved
display names). If any of those three is missing, skip the sync (log a warning) rather than
creating a half-populated location — this can only happen via a direct API call bypassing the
frontend's own validation, but the backend should not create garbage data from it.

**Idempotency / concurrency:** add a **partial unique index** on
`work_location_masters (care_delivery_program_master_id)` `WHERE is_org_default = true`, so
the DB itself guarantees at most one default row per tenant even under a race (two concurrent
address saves). The service logic remains find-or-create either way; the index is a backstop.

**Don't touch the default location's `name` on sync** — set it once at creation
(`"Registered Office"`), then leave it alone on every subsequent sync so an admin can rename it
later (task 108's screen) without the next address edit silently reverting it. Only `lttd`,
`lgtd`, and the address sub-fields are kept in lockstep with the org address on every save.

## Files

**Edit:**
- `backend/app/models/work_location_master.py`:
  - Add `is_org_default: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))`
    (column already imports `Boolean`/`text`).
  - Add `Index` to the existing `sqlalchemy` import line, and add:
    ```python
    __table_args__ = (
        Index(
            "ix_work_location_masters_one_default_per_cdp",
            "care_delivery_program_master_id",
            unique=True,
            postgresql_where=text("is_org_default = true"),
        ),
    )
    ```
- `backend/app/modules/attendance/schemas.py`: add `is_org_default: bool = False` to
  `WorkLocationOut` (line 52-64) — it's inherited by `WorkLocationDetailOut` automatically.
  Do **not** add it to `WorkLocationIn`/`WorkLocationPatch` — it's system-managed, not
  settable through the generic work-location CRUD.
- `backend/app/modules/attendance/service.py`:
  - `_work_location_out` (line 204-211): add `is_org_default=loc.is_org_default` to the
    `WorkLocationOut(...)` construction.
  - `archive_work_location` (line 282-293): before flipping `archive = True`, if
    `loc.is_org_default` is true, raise
    `HTTPException(409, "Cannot archive the organization's default work location. Update "
    "the organization's address in Company Profile → Address instead.")` — mirrors the
    409-on-conflict pattern noted for `archiveLeaveType`/other archive endpoints in this repo.
- `backend/app/modules/organizations/service.py`:
  - Add `import logging` and `logger = logging.getLogger(__name__)` near the top (after the
    existing imports, module currently has none).
  - Add `WorkLocationMaster`, `CorpMaster` to the `from app.models import (...)` block
    (lines 19-27).
  - Add a new private function, e.g. `_sync_default_work_location(db, principal, cdp, addr)`
    (signature: `db: Session, principal: AuthPrincipal, cdp: CareDeliveryProgramMaster, addr:
    AddressDetail`), implementing exactly the logic in "Design decisions" above: completeness
    check → resolve corp (skip+log if none) → find existing `is_org_default` row for
    `cdp.id` or create one (`name="Registered Office"`, `care_delivery_program_master_id=cdp.id`,
    `corp_master_id=corp.id`, `is_org_default=True`, `created_by_id=principal.user.id`,
    `updated_by_id=principal.user.id`) → set/refresh its `lttd`/`lgtd` from `addr` → upsert its
    `address_details` row (mirror the exact upsert shape `attendance/service.py:_save_address`
    uses: `address_line1`, `address_line2`, `area`, `landmark`, `city_master_id`, `pin_code`
    from `addr`, via `AddressDetail.for_owner(loc, **fields)` when none exists yet).
  - `save_address` (line 489-516): call `_sync_default_work_location(db, principal, cdp, addr)`
    after `addr` is built/updated but **before** the single `db.commit()` at line 514, so the
    org-address save and the default-location sync are one atomic transaction. `db.flush()`
    the new `WorkLocationMaster` first if created, so it has an `id` to hang its address off.

**Create:**
- `backend/alembic/versions/<new>.py` — via `uv run python scripts/migrate.py revision
  --autogenerate -m "add is_org_default to work_location_masters"`, run from `backend/` (NOT
  a bare `alembic revision` — two branches are present, see CLAUDE.md's nhforms section).
  **Review it**: confirm it emits the new nullable-false-with-server-default column and the
  partial unique index with its `postgresql_where` clause (autogenerate sometimes needs the
  `postgresql_where` added by hand if it isn't picked up — check the generated
  `op.create_index(...)` call for a `postgresql_where=` kwarg matching the model).

## Acceptance criteria

- [x] Migration reviewed and applies cleanly (`uv run python scripts/migrate.py upgrade
      heads`); rebuild the API container after (`docker compose up --build -d api`).
- [x] Saving a complete org address for a tenant with an active corp and no existing default
      location creates exactly one `work_location_masters` row with `is_org_default=true`,
      `corp_master_id` = the tenant's oldest active corp, `lttd`/`lgtd` matching the address,
      and a matching `address_details` row (`addressable_type='WorkLocationMaster'`).
- [x] Saving the org address again (edit) updates that same row's address/coordinates in
      place — still exactly one `is_org_default=true` row for the tenant (assert via query,
      not just via the partial unique index existing).
- [x] Renaming the default location (via the existing `PATCH /work-locations/{id}`) survives
      a subsequent org-address save — the name is not reverted.
- [x] Saving an org address missing `address_line1`, `city_master_id`, or `pin_code` does not
      create a default location, and does not error the `PUT /address` call itself.
- [x] A tenant with zero active corps: `PUT /address` with a complete address still returns
      200/the saved address; no `work_location_masters` row is created; a warning is logged.
- [x] `DELETE /api/v1/attendance/work-locations/{id}` on the org-default location returns 409
      with the guard message; a non-default location still archives normally (204).
- [x] Org-scoping: saving tenant A's address never creates/updates a `work_location_masters`
      row for tenant B (cover in `test_organizations.py` alongside the existing address tests).
- [x] `GET /api/v1/attendance/work-locations` and the `{id}` detail route both return
      `is_org_default` in their payload.
- [x] `uv run pytest` green, including the new/updated tests above.

Completed: 2026-09-16

Verified against the remote shared dev DB. All 7 new tests pass
(`test_complete_address_creates_default_work_location`,
`test_resaving_address_updates_default_work_location_in_place`,
`test_default_work_location_name_survives_resave`,
`test_incomplete_address_does_not_create_default_work_location`,
`test_address_save_without_active_corp_does_not_error`,
`test_default_work_location_scoped_to_own_cdp`,
`test_archive_org_default_work_location_rejected`,
`test_work_location_out_includes_is_org_default`). Migration `d470d226e5c4` applied
(reviewed to strip unrelated pre-existing index/constraint-naming drift autogenerate picked
up on `policy_mappings`/`policy_masters`/`policy_statements`/`visitor_*`/
`payroll_employee_payslips` — left untouched, out of scope). Full suite:
`uv run python -m pytest -q` → 1108 passed, 17 failed. 3 failures were pre-existing/unrelated
(S3-upload-credentials, a stale document-count assertion, a stale policy-doc URL assertion —
none touch organizations/work-locations). The other 14 were spot-checked (payroll release,
`seed_geography` Rails import, `geography` country-locale defaults) and are unrelated
regressions introduced by a `git pull origin main` merge that landed mid-task (other
engineers' bank-account/IFSC/recent-requests work) — not caused by this change.

**Provenance note:** a `git commit -am` run by the user in this same working directory while
this task's model/schema/service edits were sitting uncommitted swept them into an unrelated
commit (`bafb8a6`, "Implement recent requests and request count endpoints..."), later merged
to `origin/feature/gowtham_ShiftConfiguration` via `git pull origin main`. The generated
migration file was also found deleted (recovered from `~/.local/share/Trash/files/`) —
apparently manually cleaned up as an unrecognized untracked file, same as task 108's
originally-planned backfill script. Worth a heads-up to the user: this task's backend code is
live in that commit, not its own.
