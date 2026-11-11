---
task: 332
title: Employees are told to ask their Admin when a request type has no workflow
status: done
depends_on: [329]
---

# 332 — Employees are told to ask their Admin when a request type has no workflow

## Scope
Task 329 makes submit return 409 `APPROVAL_WORKFLOW_NOT_SET` when the organisation hasn't set a workflow for the type.
Show that cleanly where employees submit, instead of a generic failure.

- Web: regularization (`dashboards/Employee/RegularizationModal.tsx` and the attendance "Request regularization" entry
  points), work from home request, shift change request (My Shifts). Catch `ApiError` with that code and show, inside the
  modal (not only a toast): "Your organisation hasn't set up approval for <type> requests yet. Ask your Admin to set it up."
  Keep the form's entered values.
- Better: check before the employee fills the form. `GET /approvals/workflows` is readable by every user; when the type is
  not `live`, disable the entry button with the same message as a tooltip/inline note. Do the check once per page load.
- Mobile (`employeeapp/`): same message for the three submit calls; follow `hrms-mobile-api-integration` for the error shape
  (plain, unencrypted error body). Note the app release dependency in this file.
- Copy comes from `dashboards/shared/approvalLabels.ts` (task 331) so wording stays in one place.

## Files
`frontend/src/dashboards/Employee/RegularizationModal.tsx`, the WFH and shift change request modals, `frontend/src/lib/api.ts`
(error code constant), `employeeapp/` submit screens, `.claude/skills/hrms-mobile-api-integration` (document the 409).

## Acceptance criteria
- [ ] With a type unset, an employee can't submit it and sees the Admin message; nothing is created.
- [ ] With it set, submit works as before.
- [ ] Other 409s (e.g. duplicate request) still show their own messages.
- [ ] Mobile shows the same message; the skill doc lists `APPROVAL_WORKFLOW_NOT_SET`.

## Progress (2026-11-06)
Built; backend tested; web type-checked and linted. **Not moved to done**: the forms haven't been looked at in a browser, and there is no
mobile app in this checkout to change.

- Pre-check endpoint (new, differs from the plan): `GET /attendance/me/request-approval-setup` (`attendance/approval_pipeline.setup_status`,
  router + schemas in `attendance/`), self-service and ungated, returns `{items: [{request_type, set_up, message}]}` for Regularization, WFH
  and ShiftChange. Used instead of `GET /approvals/workflows`, which needs READ SETTING and so isn't readable by employees (the heads-up
  from 329). With approval workflows off every kind is `set_up: true`. The message is the one the 409 carries.
- Web: `lib/useRequestApprovalSetup.ts` (new hook; unreadable or still loading means nothing is blocked, the server still decides).
  `MyAttendance.tsx`: Request regularization, Request work from home, the per-day Regularize icon and Request shift change are disabled with
  the message as their tooltip, plus an amber note under the buttons on the tab they belong to (a tooltip isn't read on a phone).
  `RegularizationModal`, `WfhRequestModal` (its existing blocker) and `ShiftChangeRequests` form each show the message and can't submit.
- The 409 itself: `lib/api.ts` `_detailMessage` (and `shiftErrorDetail`) now read `detail.message` for coded refusals, and
  `submitRegularization` / `submitWfhRequest` use it, so the message appears inside the form (values are kept) instead of a generic
  failure. Plain-string 4xx messages (duplicate, window, locked day...) are unchanged.
- Mobile: `employeeapp/` doesn't exist in this checkout (the root `CLAUDE.md` lists it, but no such folder), so nothing could be
  changed there. The integration guide `.claude/skills/hrms-mobile-api-integration/SKILL.md` now documents the endpoint, the coded
  `detail` object shape and `409 APPROVAL_WORKFLOW_NOT_SET`. **The app release dependency is open**: the app must call the setup endpoint
  and show `message` (or at least show the 409's `detail.message`) before this goes live, or its users get a generic failure.
- Tests: `test_attendance_approvals.py` has two new tests (setup endpoint: 401, per-type state, message equals the 409's, off = all
  available); attendance approval and routing tests: 40 passing. Lint: `ruff` clean on touched backend files; `tsc` clean;
  eslint reports two findings in `MyAttendance.tsx` (an unused `me`, a `set-state-in-effect`) that are identical on HEAD.

Acceptance (the last two need a browser or the app):
- [x] With a type unset the server refuses the submit and creates nothing (329 tests); the pre-check endpoint reports it with the Admin message.
- [x] With it set the endpoint says so and submit works as before (tests).
- [x] Other 409s and 4xx keep their own plain messages (string `detail` path unchanged in `_detailMessage`).
- [ ] Web: buttons off with the message, forms show it and can't submit, a submit that still reaches the server shows it inside the form (look at it as an employee with a type unset).
- [ ] Mobile shows the same message (app not in this checkout); the guide lists `APPROVAL_WORKFLOW_NOT_SET` (done).

Completed: 2026-11-10
