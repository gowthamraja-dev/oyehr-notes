---
task: 354
title: Approval Setup for regularization, WFH and shift change works like leave (HR together + switched on by default)
status: done
depends_on: []
---

# 354 — Approval Setup for regularization, WFH and shift change works like leave

## Scope
Today the three attendance-request cards in Approval Setup (Regularization, Work from home, Shift change) differ from
the Leave card in two ways. Bring both leave behaviours to all three attendance kinds:

1. **"Ask the reporting manager and HR at the same time"** — a checkbox like leave's `hr_together`. When on, every
   request goes to the reporting manager AND an HR manager at once; whichever responds first decides it, and the other
   sees it is already decided. Mutually exclusive with the separate department-head / HR steps (leave turns the
   dept-head step off when "together" is ticked; do the same, and drop the HR-after-manager step).
2. **Switched on by default** — an organisation with no workflow for the type no longer gets "Not set" / a 409
   `APPROVAL_WORKFLOW_NOT_SET`. The first submit of that type seeds the default route (manager + HR together,
   `published_by = NULL` since nobody chose it), exactly as leave's `_ensure_default` does. The Admin can still change it
   in Approval Setup; until then the card shows the default (leave's wording: "Switched on automatically with the first
   request…").

Out of scope: leave and expense cards/behaviour (unchanged); department-head-by-days thresholds (attendance requests
have no day count — keep attendance's boolean `dept_head` / `hr` flags); any DB schema change (the route lives in the
version's `config_json.settings.attendance.routing`, so no migration and no DBML gate); mobile app UI (see "Mobile").

## Design notes (read from the code, so a fresh session doesn't have to)
- Backend seed: `backend/app/modules/attendance/approval_seed.py` — `Routing(dept_head, hr, due_in_hours)`, `_build`,
  `seed`, `republish`, `current` (reads `settings.attendance.routing`). Leave's equivalent that already does "together":
  `backend/app/modules/leave/approval_seed.py` (`together` → MANAGER step assignees = `[REPORTING_MANAGER, ROLE_IN_SCOPE
  HR_MANAGER]`, no separate HR step, status label "Waiting for manager or HR approval"; mode is already `FIRST_RESPONSE`).
- Routing API: `backend/app/modules/attendance/approval_routing.py` (`view`, `save(dept_head=, hr=)`, `_plain`) and the
  `/approvals/attendance-routing/{slug}` router + schemas in `attendance/router.py` / `schemas.py`.
- Submit gate: `attendance/approval_pipeline.py: require_workflow` / `is_live` / `setup_status` (the 409 and the employee
  pre-check, task 332). Called from `attendance/service.py` (`submit_regularization` ~L1893, WFH ~L2075) and
  `shifts/change_requests.py:142` (shift change). Leave's default seeding: `leave/approval_pipeline.py:_ensure_default`
  (advisory lock per tenant, `begin_nested`, never blocks the request, logs).
- Frontend: `frontend/src/dashboards/hrAdmin/AttendanceRoutingCard.tsx` (+ `ApprovalSetup.tsx` cards),
  `frontend/src/lib/api.ts` (`AttendanceRouting`, `AttendanceRoutingInput`, `saveAttendanceRouting`),
  `frontend/src/lib/useRequestApprovalSetup.ts` and the employee modals that show the "ask your Admin" message
  (`RegularizationModal.tsx`, `WfhRequestModal.tsx`, `ShiftChangeRequests.tsx`, `MyAttendance.tsx`, `ShiftScheduling.tsx`).
  Leave's card to copy the checkbox and wording from: `hrAdmin/LeaveRoutingCard.tsx`.

## Plan
### Backend
1. `Routing` gains `hr_together: bool = False`. `_build`: when `hr_together`, keys = `["MANAGER"]` only (no DEPT_HEAD / HR
   steps), MANAGER assignees = reporting manager + HR manager, MANAGER status label "Waiting for manager or HR approval",
   the single route MANAGER → APPROVED; reject `hr_together` combined with `dept_head=True` (`SeedRefused`).
   Store `hr_together` in `settings.attendance.routing`; `current` reads it (default False for already-published versions,
   so existing organisations are unchanged). Keep `checks.problems` passing for the new shape.
2. `approval_routing.view/save/_plain`: carry `hr_together` through (`save(dept_head, hr, hr_together=False)`); the
   `ATTENDANCE_ROUTING_CHANGED` activity-log `before`/`after` include it. The unset-state `routing` returned by `view` is
   the default (`hr_together=True`), `configured: false` until someone publishes or the first request seeds it.
3. Default seeding: add `ensure_default(db, principal, request_type)` in `attendance/approval_pipeline.py` modelled on
   leave's `_ensure_default` (advisory lock key `attendance_approval_default:{tenant}:{type}`, `begin_nested`, `seed(...,
   Routing(hr_together=True))`, `version.published_by = None`, swallow + `logger.exception` on failure so the request still
   goes through… but see the decision below). Call it where `require_workflow` is called today (regularization, WFH, shift
   change), before the check; only when `settings.approval_workflows_enabled` and the type has no WorkflowMaster at all
   (an Admin who unpublished it to go back to the old approval is left alone, as for leave).
4. `setup_status` (the employee pre-check, task 332) reports a type with no workflow as `set_up: true` once the default
   will be seeded on first submit (so the modals stop showing "Ask your Admin"). `not_set_error`/409 stays for the one
   remaining case — approvals enabled and the default could not be seeded — decision: fail the submit with the existing
   409 (don't silently fall back to the legacy single approval, which attendance has removed).
5. Docs: update the module docstrings in `approval_seed.py` / `approval_routing.py` (the "type nobody has published is
   `configured: false`… can't submit" paragraph is no longer true), `hrms/docs/` where Approval Setup for attendance is
   described (grep `attendance-routing`, `APPROVAL_WORKFLOW_NOT_SET`), and `.claude/skills/hrms-mobile-api-integration`
   (409 is now rare; routing payload gains `hr_together`).

### Frontend
6. `api.ts`: `AttendanceRouting` + `AttendanceRoutingInput` gain `hr_together: boolean`.
7. `AttendanceRoutingCard.tsx`: add leave's checkbox block ("Ask the reporting manager and HR at the same time — every
   request goes to both; whichever responds first decides it") above the steps; when ticked, hide the dept-head / HR step
   list and show the one-line summary as the Leave card does; ticking it clears `dept`/`hr`. Unset state copy → "Switched on
   automatically with the first {noun} request: the reporting manager and HR are asked together. Change it here any time.";
   button label "Switch on" while unconfigured (as leave), not "Set approval"; drop the "Not set" pill and the "Employees can't
   submit … until you set…" line. Keep existing confirm dialog / waiting-requests banner behaviour.
8. Employee modals/pages: the "ask your Admin" disabled state should rarely show; leave the handling in place for the 409
   fallback, but verify nothing shows it for a fresh organisation.

## Files
- `backend/app/modules/attendance/approval_seed.py`, `approval_routing.py`, `approval_pipeline.py`, `router.py`, `schemas.py`, `service.py`
- `backend/app/modules/shifts/change_requests.py`
- `backend/app/tests/modules/test_attendance_approval_routing.py`, `test_attendance_approvals.py` (+ new `test_attendance_hr_together.py`, `test_attendance_default_routing.py` modelled on the leave ones)
- `frontend/src/dashboards/hrAdmin/AttendanceRoutingCard.tsx`, `frontend/src/lib/api.ts`
- docs: grep results from step 5; `.claude/skills/hrms-mobile-api-integration/`

## Mobile
`employeeapp/` doesn't render Approval Setup, so no screen changes. The only visible effect is that the "not set up" 409
essentially stops happening; note that in the skill doc.

## Acceptance criteria
- [x] Approval Setup shows the "Ask the reporting manager and HR at the same time" checkbox on the Regularization, Work from home and Shift change cards; ticking it removes the separate dept-head/HR steps; saving publishes a new version carrying `hr_together`.
- [x] With "together" on, a new request of each type creates ONE approval step assigned to both the reporting manager and an HR manager; the first to approve or reject decides it and the other's task closes (same as leave).
- [x] `hr_together=True` with `dept_head=True` is refused with a 422 / `SeedRefused`; existing published versions (no `hr_together` key) still read back as `False` and behave as before.
- [x] An organisation with no workflow for a type: the first submit of that type seeds the default (manager + HR together, `published_by` NULL) and succeeds; no 409; Approval Setup shows the default as "switched on automatically" until the Admin publishes.
- [ ] Seeding is safe under two simultaneous first requests (one workflow, no duplicate master) — advisory lock in place, not tested; an Admin-unpublished type is not re-seeded (tested).
- [x] `GET /attendance/me/request-approval-setup` reports `set_up: true` for such an organisation; employee modals don't show the "ask your Admin" message.
- [x] Tenant-scoping, 401/403 (non-Admin can't save), activity-log entry (`ATTENDANCE_ROUTING_CHANGED` with `hr_together` in before/after) and waiting-request migration covered by tests; `uv run pytest` on the touched test files green; frontend `tsc` + lint clean.
- [x] Module docstrings, `hrms/docs/` and the mobile skill doc updated.
- [ ] Checked once in a browser: all three cards, the checkbox, default state, an employee submit.

## Open points to confirm before building
- Default applies to all three kinds including WFH (confirmed by the user 2026-11-19: "include WFH, Regularization and shift change card").
- Existing organisations that already published a route are untouched; only organisations with nothing published get the new default.

## Progress (2026-11-19)
Built in `workspace-1/hrms` (branch `feature/gowtham_reporting_manager_all_employees`, nothing committed). **Not moved to done**: the
browser check (last criterion) hasn't been done, and two points below differ from the plan.

- Backend: `Routing.hr_together` + `DEFAULT_ROUTING` (`approval_seed.py`), `ensure_default` / `ensure_ready` (`approval_pipeline.py`, called by the
  three submit paths), `default_on` + `hr_together` on the routing API (`approvals/schemas.py`, `router.py`, `approval_routing.py`).
- New API field `default_on` (not in the plan): lets the card tell "never set up, first request switches it on" from "Admin unpublished it".
- `setup_status` reports a never-set-up type as `set_up: true`; an unpublished one stays `false` with the Admin message.
- Frontend: checkbox + default-state copy + "Switch on" button in `AttendanceRoutingCard.tsx`; `api.ts` types. `tsc` and eslint clean.
- Docs: `docs/workflow-engine.md`, `CLAUDE.md` (attendance requests paragraph), mobile skill.
- Tests: `test_attendance_approval_routing.py` + `test_attendance_approvals.py` updated/extended, 60 passed. Neighbouring suites (my shifts, WFH,
  attendance, regularize range): 396 passed, 6 failed, the same 6 fail with these changes stashed (holiday calendar, daily shape, time-of-day).
- Not covered by a test: two simultaneous first requests (the advisory lock is a copy of leave's, which has none either).

Closed by the user's instruction with two acceptance criteria not verified (the browser check, and a test for two simultaneous first requests; see the unticked boxes above).

Completed: 2026-11-20
