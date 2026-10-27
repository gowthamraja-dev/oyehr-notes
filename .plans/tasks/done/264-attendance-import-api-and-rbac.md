---
task: 264
title: Attendance import — API routes and ATTENDANCE_IMPORT permission
status: done
depends_on: [268]
---

# 264 — Attendance import — API routes and ATTENDANCE_IMPORT permission

## Scope
Mount the attendance handler's routers, finish the RBAC resource, and test the API. Frontend is 265. **Re-scoped by the v2 plan:** the routes now come from
`file_import.router_factory.build_routers(attendance_handler)` (task 268) instead of a hand-written attendance router; `stage` takes `options` as one JSON form field.

### Progress at the pause (2026-10-26)
- DONE: `ATTENDANCE_IMPORT` grid row (`roles/permissions.py`, docstring table), default grids (Admin, HR Admin `[READ, CREATE]`; HR Manager and Employee `[]`),
  `test_roles.py` page map (113 roles/authz tests green), data migration `c3a7e1d9f402` written (not yet applied to the local DB; re-parent onto the v2 revision in 267).
- DRAFTED on the v1 layout, to be absorbed by 268: `attendance_import/{schemas,router}.py`, registration in `app/api/router.py`; 28 API tests passed, 7 failed only
  because the `hr` test fixture patched `runner.run_batch` globally and the test helpers called it (fix: capture the real function at import time — `_RUN_BATCH`).
- Gate decision kept: every route uses `require_grid_permission` (a role with no saved grid is refused, like the attendance service gates), locked-day override and
  undo additionally need `sees_whole_org(…, "ATTENDANCE")`.

- Endpoints as in the plan's Flow section, produced by the router factory. JSON endpoints on an `EncryptedRoute` router; `parse` and `stage` (multipart) on a plain
  router, like `employee_import`. Prefix `/attendance-import`. READ gates: target-fields, batches list/detail/rows, parse. CREATE gates: stage, confirm,
  discard, resume, undo. `stage` with `override_locked=true` and `undo` also require `sees_whole_org(db, principal, "ATTENDANCE")` (403 otherwise).
- All reads/writes filter by `principal.tenant_id`; another tenant's batch id → 404.
- `GET /target-fields`: employee_id (required), date (required), in_time, out_time, status.
- Batch detail: status, counters, `progress` (validated rows / row_count while Validating; days_recomputed / days_total while Running/Undoing), options.
  Rows endpoint paginated (`limit` ≤ 500), filter `status`, includes `validation_errors`, `row_data`.
- `roles/permissions.py`: `ATTENDANCE_IMPORT`, "Import Attendance", (READ, CREATE), same icon style as EMPLOYEE_IMPORT, listed in the module docstring table.
  `roles/defaults.py`: HR Admin and HR Manager `[READ, CREATE]`, Employee `[]` (mirror the EMPLOYEE_IMPORT lines). Alembic data migration (hand-written,
  guarded) adding the cell to existing tenants' default-grid policies the way `e2a8c4f6b913_feed_permission_row` did.
- Register both routers in `app/api/router.py`.

## Files
`backend/app/modules/attendance_import/{router,schemas}.py`, `backend/app/api/router.py`, `backend/app/modules/roles/{permissions,defaults}.py`,
a new alembic revision, `backend/app/tests/modules/test_attendance_import.py` + cases in `test_authz.py`.

## Acceptance criteria
- [x] 401 without token; 403 for a role without the cell; 403 on override/undo without org-wide scope; 404 across tenants
- [x] Encrypted round-trip test for the JSON router (pattern: `test_encryption.py`)
- [x] Multipart endpoints work with plain fetch semantics (no encryption header)
- [x] Permission appears on the Roles & Permissions screen with the right label; defaults seeded for HR Admin/HR Manager
- [x] `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_authz.py` green

Completed: 2026-10-26
Note: routes now come from file_import.router_factory.build_routers(attendance_handler) (task 268); RBAC data migration c3a7e1d9f402 applied twice to the local DB (idempotent). Added 4 gate tests to test_authz.py. Gate decision kept: require_grid_permission on every route (a role with no saved grid is refused), locked-day override and undo additionally need sees_whole_org(…, "ATTENDANCE").
