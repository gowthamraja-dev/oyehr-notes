# My Shifts (employee self-service) — plan

Schema (approved 2026-10-29): [`my-shifts-schema.dbml`](my-shifts-schema.dbml). Mobile mockup: [`my-shifts-mockup.jpeg`](my-shifts-mockup.jpeg).
Clone: `workspace-2/hrms`.

## Scope
Backend APIs for the employee app's **My Shifts** module — the Home card ("Today's Shift", "This Week"), the **Calendar**,
**My Shifts** (assigned list) and **Requests** tabs, the **Request Shift Change** form and **Request Details**.

Out of scope: the mobile UI itself (`employeeapp/`), an HR-managed allow-list of requestable shifts, per-tenant notice windows,
multi-day shift change requests, web UI for approving shift changes (the manager inbox only has to not misrender them).

## Flow
1. Employee opens the form → `GET /shifts/me/available?date=` gives the current shift and the requestable ones.
2. `POST /shifts/me/change-requests` → a Pending `attendance_request_details` row (`request_type = 'ShiftChange'`), approver = reporting
   manager (same `_resolve_approver` as WFH), audit row `ShiftChangeSubmitted`, in-app notification to the approver.
3. Approver approves/rejects through the existing `POST /attendance/requests/{id}/approve|reject` (so the manager inbox, workflow-engine
   multi-stage path and APPROVE ATTENDANCE gate all keep working). Approval writes the new shift for the one day through the existing
   day planner and flips the status in the same transaction.
4. Employee sees it under Requests, opens Details, may cancel while Pending.

## Backend
| Piece | Where | Notes |
| --- | --- | --- |
| Model + migration | `app/models/attendance_request_detail.py`, `alembic/versions/` | +`requested_shift_master_id`, +`current_shift_master_id`, CHECK `ck_attendance_request_details_shift_change_shifts`. Hand-written, existence-guarded for hrms-dev |
| Calendar | `modules/shifts` (task 302) | `GET /shifts/me/calendar?from&to` via `calendar_resolver_service` |
| Available shifts | `modules/shifts` (task 303) | `GET /shifts/me/available?date` |
| Submit / list / detail / cancel | `modules/shifts/change_requests.py` (task 305) | `POST/GET /shifts/me/change-requests`, `GET .../{id}`, `POST .../{id}/cancel`. Reuses attendance helpers (`_resolve_approver`, `_request_status_id`, audit log, `in_app`) |
| Approve / reject | `modules/attendance/service.py` (task 306) | `ShiftChange` branch in `approve_request`; `apply_shift_to_day` in `modules/shifts/service.py` beside `apply_work_location_to_days` (**no second writer** — goes through `_plan_and_apply_employee_days`) |
| Inbox / lists | `modules/attendance/service.py` (task 306) | `RequestOut` + `_audit_action` + manager inbox learn `ShiftChange` |

Gates: `/shifts/me/*` are self-service, ungated, on the encrypted `/shifts` router, registered **before** `/me/{target_date}`.
Approving uses the existing APPROVE ATTENDANCE gate. Every query filters `principal.tenant_id` and the caller's `employee_master_id`;
shift ids from the payload are looked up with the tenant filter.

Rules (decided): today and future dates only, today refused once the employee has punched in; any live shift of the tenant covering the
date except the current one; one Pending ShiftChange per employee + date; reason required, ≤ 500 chars; approval refused with a reason when
the day is locked / a Public holiday / a week-off / approved leave / outside employment.

## Tests
`app/tests/modules/test_my_shifts.py` — happy path, 401/403, tenant scoping (foreign shift id, foreign request id, another employee's
request), validation errors, encrypted round-trip, approve/reject/cancel state machine, approval actually moves the shift, locked/holiday/
week-off/leave refusals, ShiftChange not appearing as a regularization.

## Tasks
| # | Task | depends_on |
| --- | --- | --- |
| 302 | Calendar API | — |
| 303 | Available shifts API | — |
| 304 | Models + migration for ShiftChange | — |
| 305 | Submit / list / detail / cancel APIs | 303, 304 |
| 306 | Approve / reject ShiftChange + inbox | 304, 305 |
| 307 | Docs, mobile-integration skill, CLAUDE.md | 302, 303, 305, 306 |

## Open decisions
None outstanding; the five schema questions were answered 2026-10-29.
