---
task: 15
title: Bulk shift assignment endpoint (transactional, all-or-nothing)
status: done
depends_on: [14]
---

# 15 — Bulk shift assignment endpoint

## Scope

Backend + tests only — `POST /api/v1/shifts/assignments/bulk`, per the design doc's §9. **No
frontend consumer in this task set.** Task 16's Manager Portal rework only exercises the
single-cell create/change/cancel flow from task 14; this endpoint is forward-looking
infrastructure for a future "publish the week in one go" UI, matching the design doc's own framing
("useful for the weekly roster UI") without inventing that UI now.

Per the design doc: **all-or-nothing is safer for a weekly publish operation** — validate every
row before writing any; on any failure, nothing persists.

## Files

### `backend/app/modules/shifts/schemas.py` — add

```python
class BulkShiftAssignmentIn(BaseModel):
    assignments: list[ShiftAssignmentIn] = Field(min_length=1)


class BulkShiftAssignmentOut(BaseModel):
    assignments: list[ShiftAssignmentOut]
```

### `backend/app/modules/shifts/service.py` — add

```python
def bulk_assign_shifts(db: Session, principal: AuthPrincipal, payload: BulkShiftAssignmentIn) -> BulkShiftAssignmentOut:
    seen: set[tuple[int, date]] = set()
    for item in payload.assignments:
        key = (item.employee_master_id, item.assignment_date)
        if key in seen:
            raise HTTPException(400, detail=f"Duplicate employee/date in one bulk request: {key}")
        seen.add(key)

    # Validate every row before writing any — no partial success.
    validated: list[tuple[ShiftAssignmentIn, EmployeeMaster, ShiftMaster]] = []
    for item in payload.assignments:
        emp = _require_employee(db, principal, item.employee_master_id)
        _require_manager_or_admin(db, principal, emp)
        if not emp.is_active:
            raise HTTPException(422, detail=f"Employee {item.employee_master_id} is not active")
        shift = _require_active_shift(db, principal, item.shift_master_id)
        validated.append((item, emp, shift))

    results: list[EmployeeShiftAssignment] = []
    for item, emp, shift in validated:
        existing = db.scalar(
            select(EmployeeShiftAssignment).where(
                EmployeeShiftAssignment.employee_master_id == item.employee_master_id,
                EmployeeShiftAssignment.assignment_date == item.assignment_date,
            )
        )
        if existing is not None and existing.status == "ASSIGNED":
            raise Conflict(
                f"A shift is already assigned for employee {item.employee_master_id} on {item.assignment_date}."
            )
        if existing is not None:  # CANCELLED — reactivate in place
            old_id = existing.shift_master_id
            existing.shift_master_id = item.shift_master_id
            existing.status = "ASSIGNED"
            existing.note = item.note
            existing.updated_by_id = principal.user.id
            _write_assignment_audit(db, principal, existing, "ASSIGNED", old_id, shift.id)
            results.append(existing)
        else:
            row = EmployeeShiftAssignment(
                care_delivery_program_master_id=principal.tenant_id,
                employee_master_id=item.employee_master_id,
                assignment_date=item.assignment_date,
                shift_master_id=item.shift_master_id,
                note=item.note,
                created_by_id=principal.user.id,
            )
            db.add(row)
            db.flush()  # assign row.id before the audit FK needs it
            _write_assignment_audit(db, principal, row, "ASSIGNED", None, shift.id)
            results.append(row)

    db.commit()
    for row in results:
        db.refresh(row)
    return BulkShiftAssignmentOut(assignments=[_assignment_out(r) for r in results])
```

Note the pre-loop validation pass raises (and thus rolls back the request, since nothing has been
added to the session yet) before any row is touched — this is what makes it all-or-nothing without
needing an explicit `SAVEPOINT`: a single `db.commit()` at the end, matching this module's existing
`replace_week_offs` pattern of one commit covering a multi-row write.

### `backend/app/modules/shifts/router.py` — add

```python
@router.post("/assignments/bulk", response_model=BulkShiftAssignmentOut, status_code=201)
def bulk_assign_shifts(
    payload: BulkShiftAssignmentIn, principal: CurrentPrincipal, db: DbSession,
) -> BulkShiftAssignmentOut:
    return service.bulk_assign_shifts(db, principal, payload)
```

### `backend/app/tests/modules/test_shifts.py` — add

- Valid bulk request assigning 3 rows across 2 employees → `201`, all 3 rows created, one audit
  row each.
- A bulk request where one row targets a non-report employee (manager caller) → `403`, and a
  direct DB count confirms **none** of the batch's rows were persisted (not even the valid ones).
- A bulk request with two entries sharing the same `(employee_master_id, assignment_date)` →
  `400`, nothing persisted.
- A bulk request with one archived/inactive shift among otherwise-valid rows → `422`, nothing
  persisted.
- A bulk request that targets an employee+date which already has a `CANCELLED` row → reactivates
  that row in place (row count for that employee+date stays at 1, not 2).
- Unauthenticated → `401`.

## Acceptance criteria

- [x] `POST /api/v1/shifts/assignments/bulk` validates every row before writing any; any single
      row's validation failure leaves the database completely unchanged (verified via row-count
      assertions in tests, not just the HTTP status).
- [x] A successful bulk request creates/reactivates every row and writes one audit row per row.
- [x] Duplicate employee+date pairs within one request are rejected with `400` before any DB
      write.
- [x] All new tests pass (6 new); full `test_shifts.py` suite passes (55/55).
- [x] No frontend files touched, and nothing in `frontend/` calls this endpoint yet — confirmed via
      `grep -r "assignments/bulk" frontend/src` returning nothing.
- [x] Full backend suite: 220 passed, 2 failed — same pre-existing, unrelated
      `test_engagement_email.py` failures noted in tasks 12-14 (untouched by this task).

Completed: 2026-08-17
