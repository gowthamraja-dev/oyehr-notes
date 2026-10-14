---
task: 14
title: Per-date shift assignment API — roster query, create/change/cancel, scoping, audit
status: done
depends_on: [13]
---

# 14 — Per-date shift assignment API

## Scope

Builds the single-assignment CRUD + roster-query API on top of task 13's
`employee_shift_assignments`/`shift_assignment_audits` tables, inside the existing
`backend/app/modules/shifts/` module (new `# ── Shift assignments (per-date roster) ──`
sections in `schemas.py`/`service.py`/`router.py` — no new module). Bulk assignment is task 15.
Frontend wiring is task 16.

Reuses these existing helpers from `shifts/service.py` unchanged: `_require_admin`,
`_require_employee`, `_require_caller_employee`, `_require_manager_or_admin`, `_get_shift`,
`NotFound`/`PermissionDenied`/`Conflict` from `app.core.exceptions`. Scoping matches the existing
employee-shift-assignment endpoints exactly: **admin unrestricted CDP-wide; manager restricted to
direct reports** (`_require_manager_or_admin` — a manager acting on a non-report gets 403, never
an empty/filtered-out result).

### Error model

Reuse this repo's existing convention — `HTTPException`/`app.core.exceptions` subclasses,
rendered as plain `{"detail": "..."}` (see `_detailMessage` in `frontend/src/lib/api.ts`, which
already reads `.detail` off every error response). **Do not** adopt the design doc's
`{"error": {"code": ..., "message": ..., "field": ...}}` envelope — introducing a second,
inconsistent error shape app-wide is worse than dropping that part of the design doc. Status-code
mapping (404/409/422/403) is adopted; the nested `code` field is not.

## Files

### `backend/app/modules/shifts/schemas.py` — add

```python
class ShiftAssignmentIn(BaseModel):
    employee_master_id: int
    assignment_date: date
    shift_master_id: int
    note: str | None = Field(default=None, max_length=500)


class ShiftAssignmentPatch(BaseModel):
    shift_master_id: int | None = None
    note: str | None = None


class ShiftAssignmentOut(BaseModel):
    id: int
    employee_master_id: int
    assignment_date: date
    shift_master_id: int
    status: str
    note: str | None = None


class EmployeeRosterOut(BaseModel):
    employee_master_id: int
    emp_id: str | None = None
    name: str
    department: str | None = None
    role: str | None = None
    assignments: list[ShiftAssignmentOut]


class ShiftRosterMetaOut(BaseModel):
    from_date: date
    to_date: date
    total_employees: int


class ShiftRosterOut(BaseModel):
    data: list[EmployeeRosterOut]
    meta: ShiftRosterMetaOut
```

### `backend/app/modules/shifts/service.py` — add

- `_assignment_out(row: EmployeeShiftAssignment) -> ShiftAssignmentOut` — straight field mapping.
- `_write_assignment_audit(db, principal, row, action, old_shift_master_id, new_shift_master_id)`
  — appends one `ShiftAssignmentAudit` (no commit — caller commits once):
  ```python
  def _write_assignment_audit(
      db: Session, principal: AuthPrincipal, row: EmployeeShiftAssignment, action: str,
      old_shift_master_id: int | None, new_shift_master_id: int | None,
  ) -> None:
      db.add(ShiftAssignmentAudit(
          care_delivery_program_master_id=principal.tenant_id,
          employee_shift_assignment_id=row.id,
          employee_master_id=row.employee_master_id,
          assignment_date=row.assignment_date,
          old_shift_master_id=old_shift_master_id,
          new_shift_master_id=new_shift_master_id,
          action=action,
          performed_by_id=principal.user.id,
      ))
  ```
- `_require_active_shift(db, principal, shift_id) -> ShiftMaster` — `_get_shift` plus an
  is-usable check (`_get_shift` only checks id+CDP scope, not `is_active`/`archive`):
  ```python
  def _require_active_shift(db: Session, principal: AuthPrincipal, shift_id: int) -> ShiftMaster:
      shift = _get_shift(db, principal, shift_id)
      if shift.archive or not shift.is_active:
          raise HTTPException(422, detail="Shift is not active")
      return shift
  ```
- `list_shift_assignments(db, principal, from_dt, to_dt, department=None, role=None, employee_master_id=None) -> ShiftRosterOut`:
  - Admin (`principal.is_admin`): employees = all `EmployeeMaster` rows joined through
    `CorpMaster` where `CorpMaster.care_delivery_program_master_id == principal.tenant_id` and
    `EmployeeMaster.is_active.is_(True)`.
  - Manager: employees = caller's direct reports (same query as `list_team_employee_shifts`,
    `EmployeeMaster.reporting_manager_id == caller.id`).
  - Apply optional filters on top: `department` → `EmployeeMaster.department == department`;
    `role` → `EmployeeMaster.designation == role`; `employee_master_id` → `EmployeeMaster.id ==
    employee_master_id`.
  - For that employee set, fetch `EmployeeShiftAssignment` rows where
    `assignment_date BETWEEN from_dt AND to_dt AND status == 'ASSIGNED'` (cancelled rows never
    appear in the roster — matches the design doc's `WHERE a.status = 'ASSIGNED'`).
  - Build one `EmployeeRosterOut` per employee (include employees with zero assignments in range —
    `assignments: []` — matching `list_team_employee_shifts`'s existing behavior of listing every
    report even with no shifts). `name` via the existing `_display_name` helper; `role` from
    `EmployeeMaster.designation`.
  - `meta.total_employees` = length of the employee list (not the assignment count).
- `create_shift_assignment(db, principal, payload: ShiftAssignmentIn) -> ShiftAssignmentOut`:
  1. `emp = _require_employee(db, principal, payload.employee_master_id)`;
     `_require_manager_or_admin(db, principal, emp)`.
  2. `if not emp.is_active: raise HTTPException(422, detail="Employee is not active")`.
  3. `shift = _require_active_shift(db, principal, payload.shift_master_id)`.
  4. Look up existing row for `(employee_master_id, assignment_date)`:
     - Exists and `status == "ASSIGNED"` → `raise Conflict("A shift is already assigned for this employee on this date.")`.
     - Exists and `status == "CANCELLED"` → **reactivate that row**: set
       `shift_master_id=payload.shift_master_id`, `status="ASSIGNED"`, `note=payload.note`,
       `updated_by_id=principal.user.id`; audit action `"ASSIGNED"`,
       `old_shift_master_id=None`, `new_shift_master_id=shift.id`.
     - Doesn't exist → insert a new `EmployeeShiftAssignment` row (`created_by_id=principal.user.id`);
       audit action `"ASSIGNED"`, `old_shift_master_id=None`, `new_shift_master_id=shift.id`.
  5. `db.commit()`, `db.refresh(row)`, return `_assignment_out(row)`.
- `update_shift_assignment(db, principal, assignment_id, payload: ShiftAssignmentPatch) -> ShiftAssignmentOut`
  (PUT — "change an existing assignment"):
  1. Load by id + CDP scope; `NotFound("Shift assignment not found")` if missing.
  2. `emp = _require_employee(db, principal, row.employee_master_id)`;
     `_require_manager_or_admin(db, principal, emp)`.
  3. `old_shift_master_id = row.shift_master_id` (capture before mutating).
  4. `data = payload.model_dump(exclude_unset=True)`; if `"shift_master_id"` present,
     `_require_active_shift(db, principal, data["shift_master_id"])`.
  5. Apply `data` fields onto `row`; if `row.status == "CANCELLED"`, this PUT reactivates it
     (`row.status = "ASSIGNED"`) — a manager changing a cancelled slot's shift is exactly how they
     re-fill it.
  6. `row.updated_by_id = principal.user.id`.
  7. Audit action `"CHANGED"` (or `"ASSIGNED"` if it was reactivated from `CANCELLED`),
     `old_shift_master_id`, `new_shift_master_id=row.shift_master_id`.
  8. Commit, refresh, return.
- `cancel_shift_assignment(db, principal, assignment_id) -> None` (DELETE — soft cancel):
  1. Load by id + CDP scope; `NotFound` if missing.
  2. `emp = _require_employee(...)`; `_require_manager_or_admin(...)`.
  3. If already `CANCELLED`: no-op (idempotent, no audit row).
  4. Else: `old_shift_master_id = row.shift_master_id`; `row.status = "CANCELLED"`;
     `row.updated_by_id = principal.user.id`; audit action `"CANCELLED"`,
     `new_shift_master_id=None`; commit.

### `backend/app/modules/shifts/router.py` — add

```python
# ── Shift assignments (per-date roster) ───────────────────────────────────────────

@router.get("/assignments", response_model=ShiftRosterOut)
def list_shift_assignments(
    principal: CurrentPrincipal,
    db: DbSession,
    from_dt: date = Query(..., alias="from"),
    to_dt: date = Query(..., alias="to"),
    department: str | None = Query(default=None),
    role: str | None = Query(default=None),
    employee_master_id: int | None = Query(default=None),
) -> ShiftRosterOut:
    return service.list_shift_assignments(db, principal, from_dt, to_dt, department, role, employee_master_id)


@router.post("/assignments", response_model=ShiftAssignmentOut, status_code=201)
def create_shift_assignment(
    payload: ShiftAssignmentIn, principal: CurrentPrincipal, db: DbSession,
) -> ShiftAssignmentOut:
    return service.create_shift_assignment(db, principal, payload)


@router.put("/assignments/{assignment_id}", response_model=ShiftAssignmentOut)
def update_shift_assignment(
    assignment_id: int, payload: ShiftAssignmentPatch, principal: CurrentPrincipal, db: DbSession,
) -> ShiftAssignmentOut:
    return service.update_shift_assignment(db, principal, assignment_id, payload)


@router.delete("/assignments/{assignment_id}", status_code=204)
def cancel_shift_assignment(assignment_id: int, principal: CurrentPrincipal, db: DbSession) -> None:
    service.cancel_shift_assignment(db, principal, assignment_id)
```

Note: this must be registered **before** the existing `/{shift_id}` PATCH/DELETE routes only if
FastAPI path-matching ambiguity is a concern — it isn't here, since `/assignments` is a fixed
literal segment, not a competing `{shift_id}` path param match at the same position. Order in the
file doesn't matter; place it in its own section for readability.

### `backend/app/tests/modules/test_shifts.py` — add a new section, reusing `admin_token`,
`_manager_token`, `_corp`, `_emp`, `_other_cdp` fixtures exactly as the existing employee-shift
tests do:

- Create assignment for an active employee/active shift → `201`, `status == "ASSIGNED"`.
- Create a second assignment for the same employee+date while the first is still `ASSIGNED` →
  `409`.
- Create for an inactive employee (`_emp(..., is_active=False)`) → `422`.
- Create with an archived/inactive shift → `422`.
- `PUT` changes the shift on an existing assignment → `200`, new `shift_master_id` persists; a
  `shift_assignment_audits` row exists with `action="CHANGED"` and the correct old/new ids.
- `DELETE` cancels → the roster `GET` for that date range no longer includes it; calling `DELETE`
  again on the same id is a no-op (still `204`, no second audit row).
- `POST` again for the same employee+date after a `DELETE` → reactivates the same row id (assert
  via a direct `db_session` count that no second `employee_shift_assignments` row was created).
- `GET /shifts/assignments?from=...&to=...` returns the right employees + assignments for the
  range; `department`/`employee_master_id` query params narrow the result set correctly.
- Manager can create/update/cancel for a direct report; the same calls for a non-report → `403`.
- Cross-CDP employee → `404`.
- All four endpoints unauthenticated → `401`.

## Acceptance criteria

- [x] `GET /api/v1/shifts/assignments`, `POST /api/v1/shifts/assignments`,
      `PUT /api/v1/shifts/assignments/{id}`, `DELETE /api/v1/shifts/assignments/{id}` all work per
      the behavior specified above.
- [x] Every write (`create`/`update`/`cancel`) inserts exactly one correct
      `shift_assignment_audits` row; no audit row is written for a no-op cancel-of-cancelled
      (verified via direct `db_session` audit-row-count assertions in tests).
- [x] Duplicate `(employee_master_id, assignment_date)` never violates the DB unique constraint —
      the assign→cancel→reassign cycle always updates the same row (verified: reactivated row
      keeps its original id, and a direct row-count query stays at 1).
- [x] Manager scoping matches the existing employee-shift-assignment endpoints exactly (direct
      reports only, 403 not empty-list for non-reports).
- [x] All new tests pass (16 new tests); full `test_shifts.py` suite passes (49/49).
- [x] `docker compose up --force-recreate -d api` starts with no import errors.
- [x] No frontend files touched.
- [x] Full backend suite: 214 passed, 2 failed — the same pre-existing, unrelated
      `test_engagement_email.py` failures noted in tasks 12 and 13 (untouched by this task).

Completed: 2026-08-17
