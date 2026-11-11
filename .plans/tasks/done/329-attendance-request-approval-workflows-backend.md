---
task: 329
title: Regularization, work from home and shift change approvals run on the approvals pipeline
status: done
depends_on: []
---

# 329 — Regularization, work from home and shift change approvals run on the approvals pipeline

UI: the existing My approvals UI is kept (see task 331); the mockup in `.design/` is reference only. Part of the "one My approvals page" plan (329-333).

## Scope
Today these three request types are NOT on the approvals pipeline. They are rows in
`attendance_request_details` (`request_type` = `Regularization` | `WFH` | `ShiftChange`), decided only by
`POST /attendance/requests/{id}/approve|reject` (single step: reporting manager or admin) or, for
regularization only, by the older Workflow Builder `ATTENDANCE_REQUEST` chain
(`workflow_engine_service.start_instance`, `attendance/service.py` ~1882). WFH and shift change never start any workflow.

Make each follow **the workflow the organisation's Admin set up**, the same way leave and expense claims do:
- Three pipeline workflows, modelled line by line on `backend/app/modules/leave/approval_pipeline.py`
  (`context.register(ApprovalWorkflow(...))`): codes `ATTENDANCE_REGULARIZATION_APPROVAL`,
  `ATTENDANCE_WFH_APPROVAL`, `ATTENDANCE_SHIFT_CHANGE_APPROVAL`; `ref_table = "attendance_request_details"`.
  New module `backend/app/modules/attendance/approval_pipeline.py` (one file, three registrations, shared helpers).
- `build_facts` reads the row server-side: requester (`requester_employee_id`, `corp_id`, `department_master_id`),
  plus per type: Regularization `from_date`, `requested_in_at`, `requested_out_at`; WFH `from_date`, `to_date`,
  `duration_days`; ShiftChange `from_date`, `current_shift_master_id`, `requested_shift_master_id`.
- `describe` returns (title, details) for the approver: names only, never ids. Title is one of
  "Regularization request" / "Work from home request" / "Shift change request". Details include the **reason**
  (`reason`) as its own entry so the page can show it in Review and in the eye preview.
- `after_move`: a move to Approved runs the **existing** apply code, unchanged (regularization apply +
  `_assert_day_open_for_regularization`, the WFH work-location write, shift change via `apply_shift_to_day`);
  a move to Rejected runs the existing reject path; cancel moves the run to Cancelled. Never a second writer.
- `decide_via` routes inbox decisions through the same service functions the attendance routes use, so the
  payroll-lock check, audit rows (`AttendanceAuditLog`), in-app notifications and result shapes stay identical.
- **No workflow set → refuse to submit.** `submit_regularization`, the WFH submit and the shift change submit check
  for a live published version of their workflow code (same helper leave uses). None: raise `Conflict` with HTTP 409
  and body `{"code": "APPROVAL_WORKFLOW_NOT_SET", "request_type": "...", "message": "Your organisation hasn't set up approval for <type> requests yet. Ask your Admin to set it up."}`. Nothing is created.
  (Decision taken with the owner: block with a message.)
- **Rollout must not break existing organisations.** Today every org can submit (reporting manager approves).
  Add `scripts/seed_attendance_approval_pipeline.py` (`--cdp <id>` | `--all`, dry run unless `--apply`, same style as
  `seed_leave_approval_pipeline.py`) that publishes a default one-step version (employee's reporting manager) for each
  of the three codes for organisations that have none. Run it on dev/prod with the deploy. New organisations start
  with nothing set, so they see the "not set" state until their Admin acts.
- **In-flight requests**: a Pending row with no pipeline run keeps working through the existing approve/reject
  routes. A Pending row created before deploy is adopted into a run like `adopt_open_requests` does for leave,
  or left on the legacy path; pick one, record it in this file. Old Workflow Builder `ATTENDANCE_REQUEST` runs are
  not migrated and keep finishing on the old engine; stop starting new ones for regularization.
- Existing routes `GET /attendance/requests`, `approve`, `reject` stay (RBAC `APPROVE ATTENDANCE` unchanged); when a
  run exists they delegate to the pipeline decision so there is one rule for "who may decide now".
- `GET /approvals/inbox` already lists tasks by workflow code: the three new types appear with no router change.
  `GET /approvals/workflows` lists them with `live` true/false (the frontend uses this for "workflow not set").

## Files
- `backend/app/modules/attendance/approval_pipeline.py` (new)
- `backend/app/modules/attendance/service.py` (submit guards + hooking `start`, decide delegation)
- `backend/app/modules/approvals/service.py` (`workflows()` includes the new codes; nothing else expected)
- `backend/scripts/seed_attendance_approval_pipeline.py` (new)
- `backend/app/tests/modules/test_attendance_approvals.py` (new)
- `docs/workflow-engine.md` and the Approvals section of the root `CLAUDE.md` (one paragraph each)

## Acceptance criteria
- [x] Workflow live: submit creates a run; the first-step approver sees it in `GET /approvals/inbox` with the right title and details (reason included); another tenant's user never does.
- [x] Approve at the last step applies the day exactly as before (regularized punches / WFH work location / new shift); Reject leaves the day untouched; both write the same audit rows and notifications as today.
- [x] Two-step workflow: only the current step's approver can decide; later step opens after the first approves.
- [x] No workflow live: each of the three submits returns 409 `APPROVAL_WORKFLOW_NOT_SET` and creates no row.
- [ ] Seed script dry-run lists what it would publish; `--apply` is re-runnable and skips orgs that already have a version.
- [x] A Pending request from before the change can still be approved and rejected.
- [x] Payroll-locked day: approval is refused with the same message as today.
- [x] Tests cover happy path, 401/403, tenant scoping, validation, not-set 409, in-flight legacy; `uv run pytest app/tests/modules/test_attendance_approvals.py` green.

## Progress (2026-11-06)
Built and tested; **not moved to done**: two criteria are still open (below) and the owner hasn't reviewed it.
- Code: `backend/app/modules/attendance/approval_pipeline.py` and `approval_seed.py` (new); submit guards + run start and cancel in
  `attendance/service.py` and `shifts/change_requests.py`; approve/reject branch onto the run (`_apply_approval` is the old approve tail,
  unchanged); `approvals/service.py` (`workflows()` lists unset types as not live; `decide` returns `DecideOut.effect`);
  `scripts/seed_attendance_approval_pipeline.py`; docs in `docs/workflow-engine.md` and `CLAUDE.md`.
- Tests: `app/tests/modules/test_attendance_approvals.py`, 24 passing; the WFH and My Shifts suites still pass (111 together). Nine
  other tests in `test_attendance.py` / `test_attendance_regularize_range.py` fail identically on a clean HEAD (biometric directions,
  time of day, missing reference data), so they are not from this change.
- Test database note: `hrms-test-pg` has no nhforms tables (`form_masters`) and no seeded `role_masters`, so the existing
  `test_leave_approval_pipeline.py` fails on it. The new tests stand in for the decision form and create their own role rows instead.
- Decision on in-flight requests: **left on the legacy path** (no run is created for a Pending request raised before this; they keep
  the reporting-manager / admin approval via the unchanged routes). Old Workflow Builder `ATTENDANCE_REQUEST` runs keep finishing on
  the old engine; new regularizations no longer start one while the pipeline workflow applies.
- Not supported on these workflows: RETURN (correction) and the `in_form` Approval Decision form (clear 409 message).
- Still open:
  - [ ] Seed script `--apply` is re-runnable and skips organisations that already have a version (logic is guarded by
    `approval_seed.existing`; only the dry run has been executed, against the local test DB).
  - [ ] (Task 333 adds a second script that must follow it) Run the seed script with `--all --apply` on dev/prod together with the deploy (otherwise every organisation is "not set" and
    employees can't submit these requests).
- Heads-up for 330/331/332: `GET /approvals/workflows` is gated `READ SETTING`, so an employee can't call it; task 332's "check before
  the form opens" needs a small ungated read (or the 409 alone).

Completed: 2026-11-10
