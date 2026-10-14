---
name: hrms-activity-logging
description: >
  Any new deletion/restoration, ownership/role/assignment-change, or login/logout
  action in HRMS must also write a row to `user_activity_details` via
  `app.services.activity_log_service.log_activity` (or `log_login`/`log_logout`).
  This is IN ADDITION TO the automatic per-request row the activity-logging
  middleware already writes for every authenticated call — the manual call
  captures detail (which record, not just which URL) the middleware can't see.
  Use whenever adding a new soft-delete/archive action, a new "assign X to Y"/
  ownership-transfer action, or touching auth login/logout.
---

# HRMS activity logging — every delete/restore/ownership action gets a manual `log_activity` call too

Confirmed with the user: HRMS replicates nh_server_app's `user_activity_details`
table and behavior — same table name, same event coverage (record changes,
deletion/restoration, access, ownership actions), rebuilt on HRMS's own stack
(SQLAlchemy/Alembic/PostgreSQL/FastAPI). Two layers write to it, both required:

1. **`app.middleware.activity_logging`** — already wired into every request
   automatically (`hrms/backend/app/main.py`). Writes one row per authenticated request with
   `action_type` = HTTP method, `action_path` = the URL path. Nothing to do here for
   a new endpoint — this layer covers it for free.
2. **Manual `log_activity` calls** — added by hand at the specific service functions
   that perform a delete/restore/ownership-change action, to capture detail the
   middleware can't see from the URL alone (e.g. *which* record, not just which
   endpoint was hit). This is the layer that needs a new line of code per new
   action — **this skill is about layer 2.**

## The rule

**Any new function that soft-deletes a row (see `hrms-soft-delete`), reactivates one,
or changes who owns/is-assigned-to a record → call `log_activity` right where the
change happens, in the same transaction (before `db.commit()`), so the log entry only
persists if the action itself actually succeeds.**

```python
from app.services.activity_log_service import log_activity

def archive_something(db: Session, principal: AuthPrincipal, thing_id: int) -> None:
    thing = _get_thing(db, principal, thing_id)
    thing.archive = True
    thing.archived_by_id = principal.user.id
    thing.archived_at = _now()
    log_activity(
        db, user_id=principal.user.id, tenant_id=principal.tenant_id,
        role_master_id=principal.role_master_id,
        action_type="DELETE", action_path=f"/things/{thing_id}",
    )
    db.commit()
```

`action_type` is the HTTP verb this action corresponds to (`"DELETE"` for an
archive/remove, `"PUT"`/`"PATCH"` for a restore/reactivate or an ownership change,
`"POST"` for creating a new assignment) — not a semantic label. `action_path` is the
concrete resource path, including the id, e.g. `f"/shifts/{shift_id}"` — this is what
lets a later `WHERE action_path LIKE '/shifts/%'` query find every shift deletion. Keep
it a plain, best-effort call: `log_activity` never raises (it catches and logs its own
failures) so it's safe to call unconditionally without wrapping it yourself.

## Login/logout

Use the two dedicated helpers instead of `log_activity` directly — they set
`login_time`/`logout_time` on the row, which `log_activity` doesn't:

```python
from app.services.activity_log_service import log_login, log_logout

log_login(db, user_id=user.id, tenant_id=cdp_id, role_master_id=membership.role_master_id)
log_logout(db, user_id=principal.user.id, tenant_id=principal.tenant_id, role_master_id=principal.role_master_id)
```

Already wired at every place a session actually starts or ends:
`auth/service.py: login` (non-2FA success), `auth/service.py: verify_otp` (2FA
success), `auth/router.py: logout`.

## Already-wired call sites (reference examples)

Deletion/restoration: `shifts/service.py: archive_shift`,
`hr_attributes/service.py: delete_value` / `create_attributes_bulk` (the `to_archive`
loop) / `set_employee_attribute_mapping`, `leave/service.py: archive_leave_type`,
`attendance/service.py: archive_work_location` / `archive_holiday`,
`devices/router.py: remove_device` / `unmap_enrollment`,
`payroll/service.py: update_salary_structure` (the `is_active` branch of its generic
patch loop).

Ownership/assignment changes: `roles/service.py: assign_members` (grant) /
`remove_member` (revoke), `employees/service.py: assign_reporting_mapping` (manager
assignment).

When adding a new module with its own delete/archive/reassign action, follow the same
one-line-per-call-site pattern at the exact point the row is mutated — don't invent a
new shared "wrap every service function" mechanism; there is no ORM event hook or
decorator doing this automatically anywhere in this codebase, by design (matches how
every pre-existing audit table here — `AttendanceAuditLog`, `PayrollInitiationTracking`,
etc. — is also written via an explicit, manually-placed `db.add(...)`/helper call).

## Pre-merge checklist for any new delete/restore/ownership-change action

- [ ] `log_activity` (or `log_login`/`log_logout`) is called in the same function that
      performs the change, before `db.commit()`.
- [ ] `action_type` is the HTTP verb this action corresponds to; `action_path` names
      the specific resource, including its id.
- [ ] A bulk operation (archiving/reassigning several rows in a loop) logs once per
      affected row inside the loop, not once for the whole batch — unless the affected
      rows genuinely have no individual identity worth recording separately.
- [ ] Tests use the real `db_session`/`client` fixtures (the middleware itself is
      disabled in tests via `settings.enable_activity_logging = False` in
      `conftest.py` — only the manual `log_activity` call sites are exercised by
      the test suite, and they use the same transactional session as everything
      else, so no special setup is needed to assert a row was written).
