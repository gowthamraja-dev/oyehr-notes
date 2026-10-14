---
task: 106
title: "Dashboard: open-requests count API + recent-request-history (max 5) API"
status: done
depends_on: []
---

# 106 — Dashboard: open-requests count API + recent-request-history (max 5) API

## Origin

`.design/Employee Mobile App.dc.html` and `.design/Employee Portal.dc.html` both mock a Home/
dashboard "My open requests" panel (mobile: lines ~127-137, 710, 720-725; portal: lines
~151-161, 713, 731-737) fed today by hardcoded `s.myLeaves` / `s.expenses` / `s.tickets` arrays
filtered client-side to `status==='Pending'`, plus a stat tile `{ label:'Open requests', value:
'2' }`. This task replaces that mock with two real backend endpoints: one that returns the
**count** of the caller's open requests (for the stat tile), and one that returns the caller's
most **recent request history, capped at 5** (for the panel/modal list). Frontend wiring of
`EmployeeHome.tsx` to these endpoints is explicitly out of scope — see below.

## Current state (confirmed by reading the code)

- `app/modules/home/` already exists and is the dashboard aggregation module — `GET
  /api/v1/home/summary` (`router.py`, `service.py`) backs the real `EmployeeHome.tsx`
  (`frontend/src/dashboards/Employee/EmployeeHome.tsx`). It is on an `EncryptedRoute` router
  already; no router-level change needed for that.
- `HomeStatsOut.open_requests_count` (`modules/home/schemas.py`) is wired to
  `get_my_reimbursement_summary(db, principal).pending_count` — **which is always 0**, because
  `modules/reimbursements/service.py` is fully stubbed ("No reimbursement/expense-claim tables
  were found in the initial schema audit"). The stat tile is silently wrong today; this task
  fixes it as a side effect of building the real aggregate.
- Of the four request kinds the design mockups show (Leave, Reimbursement/expense claim,
  Attendance regularization, Helpdesk ticket), only **two have real backing tables**:
  - Leave: `LeaveRequestDetail` (`models/leave_request_detail.py`), self-service list already
    exists at `modules/leave/service.py:list_my_requests` (statuses: `Pending|Approved|Rejected|
    Cancelled`, tenant + `employee_master_id` scoped, `archive.is_(False)`).
  - Attendance regularization: `AttendanceRequestDetail` (`models/attendance_request_detail.py`,
    `request_type='Regularization'` only today), self-service list already exists at
    `modules/attendance/service.py:list_my_requests` (same status vocabulary).
  - Reimbursement (`modules/reimbursements/`) and Helpdesk ticket (mocked in the design, no
    `app/modules/helpdesk` or backing model exists at all) have **no real table**. Per this
    module's own established convention ("honest None/0 for anything with no backing module
    yet" — `service.py` docstring), these two contribute a hardcoded `0` / no rows to the new
    endpoints, not a fabricated number. Do not build a helpdesk table or a reimbursement table
    as a side effect of this task.

## Scope

Add two endpoints to the existing `home` module (not a new module — this is dashboard
aggregation, same job as `/home/summary`):

### 1. `GET /api/v1/home/requests/count` → counts for the stat tile

`modules/home/schemas.py`:
```python
class RequestsCountOut(BaseModel):
    total_open: int                 # sum of the four below
    leave_pending: int              # real
    regularization_pending: int     # real
    reimbursement_pending: int      # always 0 today — no backing table (see above)
    helpdesk_open: int              # always 0 today — no backing table (see above)
```

`modules/home/service.py`:
```python
def get_my_requests_count(db: Session, principal: AuthPrincipal) -> RequestsCountOut:
    employee = _resolve_caller_employee(db, principal)
    if employee is None:
        return RequestsCountOut(total_open=0, leave_pending=0, regularization_pending=0,
                                 reimbursement_pending=0, helpdesk_open=0)

    leave_pending = db.scalar(
        select(func.count()).select_from(LeaveRequestDetail).where(
            LeaveRequestDetail.care_delivery_program_master_id == principal.tenant_id,
            LeaveRequestDetail.employee_master_id == employee.id,
            LeaveRequestDetail.archive.is_(False),
            LeaveRequestDetail.status == "Pending",
        )
    ) or 0
    regularization_pending = db.scalar(
        select(func.count()).select_from(AttendanceRequestDetail).where(
            AttendanceRequestDetail.care_delivery_program_master_id == principal.tenant_id,
            AttendanceRequestDetail.employee_master_id == employee.id,
            AttendanceRequestDetail.archive.is_(False),
            AttendanceRequestDetail.status == "Pending",
        )
    ) or 0
    return RequestsCountOut(
        total_open=leave_pending + regularization_pending,
        leave_pending=leave_pending, regularization_pending=regularization_pending,
        reimbursement_pending=0, helpdesk_open=0,
    )
```

**Also fix the existing gap**: change `get_home_summary` to set
`stats.open_requests_count = get_my_requests_count(db, principal).total_open` instead of the
current `reimbursements.pending_count` (which is always 0). Keep computing `reimbursements` for
whatever else in that function still needs it, if anything — check before removing the call.

### 2. `GET /api/v1/home/requests/recent?limit=5` → history for the panel/modal

Default `limit=5` (the task's "max-5"), accept an optional override but cap it (e.g. `le=20`) —
don't let the dashboard request an unbounded page. Returns most-recent-first across **all**
statuses (not just Pending) — this is "history", matching the design's separate "Request
history" list (mobile line 217, portal line 266), not the "open requests only" filter. If the
"dashboard modal" turns out to mean open-only when this is actually built against the design,
that's a one-line filter change, not a redesign — flag it to the user at execution time rather
than guessing further here.

`modules/home/schemas.py`:
```python
class RecentRequestOut(BaseModel):
    request_type: Literal["Leave", "Regularization"]  # extend when Reimbursement/Helpdesk get tables
    id: int
    title: str          # leave type name, or "Attendance regularization"
    meta: str            # e.g. "12 Jul – 14 Jul · 3 day(s)", or "12 Jul · Punch correction"
    status: Literal["Pending", "Approved", "Rejected", "Cancelled"]
    applied_at: datetime
    actioned_at: datetime | None
```

`modules/home/service.py`:
```python
def get_my_recent_requests(db: Session, principal: AuthPrincipal, limit: int = 5) -> list[RecentRequestOut]:
    employee = _resolve_caller_employee(db, principal)
    if employee is None:
        return []

    leave_types = {lt.id: lt for lt in db.scalars(
        select(LeaveTypeMaster).where(LeaveTypeMaster.care_delivery_program_master_id == principal.tenant_id)
    ).all()}
    leave_rows = db.scalars(
        select(LeaveRequestDetail).where(
            LeaveRequestDetail.care_delivery_program_master_id == principal.tenant_id,
            LeaveRequestDetail.employee_master_id == employee.id,
            LeaveRequestDetail.archive.is_(False),
        ).order_by(LeaveRequestDetail.applied_at.desc()).limit(limit)
    ).all()
    reg_rows = db.scalars(
        select(AttendanceRequestDetail).where(
            AttendanceRequestDetail.care_delivery_program_master_id == principal.tenant_id,
            AttendanceRequestDetail.employee_master_id == employee.id,
            AttendanceRequestDetail.archive.is_(False),
        ).order_by(AttendanceRequestDetail.applied_at.desc()).limit(limit)
    ).all()

    merged = [
        RecentRequestOut(
            request_type="Leave", id=r.id,
            title=leave_types[r.leave_type_master_id].name if r.leave_type_master_id in leave_types else "Leave",
            meta=f"{r.from_date:%d %b} – {r.to_date:%d %b} · {r.total_days} day(s)",
            status=r.status, applied_at=r.applied_at, actioned_at=r.actioned_at,
        ) for r in leave_rows
    ] + [
        RecentRequestOut(
            request_type="Regularization", id=r.id, title="Attendance regularization",
            meta=f"{r.from_date:%d %b} · Punch correction",
            status=r.status, applied_at=r.applied_at, actioned_at=r.actioned_at,
        ) for r in reg_rows
    ]
    merged.sort(key=lambda x: x.applied_at, reverse=True)
    return merged[:limit]
```

Taking `limit` rows from *each* source before merging is a correctness requirement, not an
optimization — the true top-`limit` of the union can only be wrong if fewer than `limit` rows
were pulled from a source that actually contributed to the top `limit`; pulling `limit` from
each source is always sufficient (standard k-way top-N merge).

`modules/home/router.py`:
```python
@router.get("/requests/count", response_model=RequestsCountOut)
def get_my_requests_count(principal: CurrentPrincipal, db: DbSession) -> RequestsCountOut:
    return service.get_my_requests_count(db, principal)


@router.get("/requests/recent", response_model=list[RecentRequestOut])
def get_my_recent_requests(
    principal: CurrentPrincipal, db: DbSession, limit: int = Query(5, ge=1, le=20),
) -> list[RecentRequestOut]:
    return service.get_my_recent_requests(db, principal, limit)
```

Both routes inherit `EncryptedRoute` from the existing `router = APIRouter(prefix="/home", ...,
route_class=EncryptedRoute)` — no change there. Both are self-service (caller's own data only,
scoped by `principal.tenant_id` + the resolved employee row) — **not** RBAC-gated, matching
every other endpoint in this module.

## Explicitly out of scope

- Reimbursement and Helpdesk backing tables/models/migrations — not this task. They contribute
  `0` / no rows honestly, per existing module convention.
- Wiring `frontend/src/dashboards/Employee/EmployeeHome.tsx` (or the mobile app, which does not
  exist as a real Next.js/React surface yet — `.design/Employee Mobile App.dc.html` is a
  throwaway Claude Design canvas, not live code) to these endpoints — a follow-up task once this
  API lands.
- Manager/admin-facing "all employees' open requests" views — this is the self-service `/me`-
  shaped surface only, same as the rest of `home`.

## Files

- `hrms/backend/app/modules/home/schemas.py` — add `RequestsCountOut`, `RecentRequestOut`.
- `hrms/backend/app/modules/home/service.py` — add `get_my_requests_count`,
  `get_my_recent_requests`; update `get_home_summary` to use the former for
  `stats.open_requests_count`.
- `hrms/backend/app/modules/home/router.py` — add the two `GET` routes; import `Query`,
  `LeaveRequestDetail`, `LeaveTypeMaster`, `AttendanceRequestDetail`, `func` as needed in
  `service.py`.
- `hrms/backend/app/tests/modules/test_home.py` — new tests (see below).

## Acceptance criteria

- [ ] `GET /api/v1/home/requests/count` returns real `leave_pending` + `regularization_pending`
      counts for the caller's own tenant + employee row, `0` for reimbursement/helpdesk, and
      `total_open` = the sum.
- [ ] `GET /api/v1/home/requests/recent` returns at most `limit` (default 5) items, merged across
      Leave + Regularization, sorted by `applied_at` descending.
- [ ] `GET /api/v1/home/summary`'s `stats.open_requests_count` now equals the count endpoint's
      `total_open` (regression test against the current always-0-via-reimbursements behavior).
- [ ] Both new endpoints return 401 with no bearer token.
- [ ] Org-scoping test: a Pending leave/regularization request belonging to a different CDP (or
      a different employee in the same CDP) never appears in the caller's count or recent list.
- [ ] Caller with no `EmployeeMaster` row in the current tenant gets `0`/`[]`, not a 500.
- [ ] `limit` query param is respected and rejects values outside `[1, 20]` with a 422.
- [ ] `uv run pytest app/tests/modules/test_home.py` passes.

Completed: 2026-09-16
