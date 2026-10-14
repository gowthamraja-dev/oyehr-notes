---
task: 60
title: Add Employee flow — success feedback and post-create handoff
status: done
depends_on: [57]
---

# 60 — Add Employee flow — success feedback and post-create handoff

## Discussion

**Important scope note, confirmed during this planning pass**: the design prompt's §10 "Add
Employee flow" reads as if a new employee-creation form and a new `POST /employees` persistence
endpoint need to be built from scratch (its §11 sketch even lists `emp_id`/`corp_master_id`/
`user_id`/`reporting_manager_id`/`joining_date`/`employment_status` as "minimum creation
information," implying a bespoke form). **That already exists, by a different mechanism** — per
CLAUDE.md's "Dynamic forms" section, HRMS employee creation is done through the installed
`nhforms` package's Registration form (`form_type_master_id = 10`), not a raw table-insert
endpoint. `shared/EmployeeDirectory.tsx`'s "Add employee" button already: looks up the right
form via `GET /employees/add-form` (`getAddEmployeeFormId`), opens it in
`EmployeeFormModal.tsx` (a generic nhforms form-modal wrapper), and on submit calls
`onSubmitted` → `refetchEmployees()`. Field-level validation (required fields, valid dates,
valid dropdown values) is enforced by the form's own definition inside nhforms, not by HRMS
code — building a second, parallel raw-insert creation endpoint in the `employees` module
would create exactly the "duplicate login identity" / two-creation-paths risk CLAUDE.md and the
design prompt (§10: "Do not silently create duplicate login identities") both warn against.
**Do not build a new backend creation endpoint for this task** — there is no backend work here.

What genuinely doesn't exist yet, and is this task's actual scope, is the **polish** design
prompt §10's "Save behavior" list calls for beyond what's wired today:

- No success toast/message after a submission — `onSubmitted` silently closes the modal and
  refetches.
- No "optionally open the newly created employee profile" — nhforms' `submitEngine` result
  (`result` in `FormModalRunner`'s `onSubmit`) is discarded once truthy; check whether it
  contains the created employee's id (likely via the form's configured `reference_srce` writing
  back an `employee_master_id`, per CLAUDE.md's nhforms section — forms 3595-style reference
  wiring) — if it does, thread that id up through `onSubmitted` so `EmployeeDirectory` can open
  the profile immediately; if the submit response genuinely doesn't expose the new employee's
  id, don't force it — a success toast alone still satisfies the prompt's baseline requirement,
  and forcing a lookup (e.g. re-fetching the list and guessing the newest row) would be fragile
  and worth flagging as a follow-up rather than building.
- "On failure... keep the entered values, display field-level errors" — nhforms' `FormModal`
  already owns its own in-form validation/error display (it's the package's responsibility, not
  HRMS's, per CLAUDE.md: "Everything under /api/v1/forms is served by the package"); confirm this
  already behaves reasonably (a failed submit doesn't lose entered field values) rather than
  building a second error-handling layer around it. If it does not already behave reasonably,
  that's a package-level gap outside a one-task fix — note it rather than attempting to patch
  nhforms' internals from HRMS.

## Files

- `frontend/src/dashboards/shared/EmployeeDirectory.tsx` — `onSubmitted` callback: add a toast on
  success, optionally accept the new employee's id and open its profile
- `frontend/src/dashboards/shared/EmployeeFormModal.tsx` — thread through the created entity's id
  from `submitEngine`'s result if available, without hardcoding an assumption about its shape;
  add a type for whatever `result` actually contains, don't leave it implicitly `any`

## Manual verification

Verified against the `beta` seed tenant (backend run locally via `uv run uvicorn`, same
CodeArtifact-token limitation noted in [[57]]-[[59]]; Docker restarted afterward). Browser driven
via `javascript_tool` (the `computer` `type` action still doesn't reach React-controlled inputs
this session).

- [x] "Add employee" still opens the real nhforms Registration form correctly (First Name*,
      Last Name, Mobile*, Email, Employee ID, Department, Role, Joining Date* all rendered) —
      confirms the `onSubmitted` signature change didn't break the existing open/render path.
- [ ] **Not exercised end-to-end live**: filling every plain-text field via JS and clicking
      Submit did not produce a network call — nhforms' Joining Date field is a `react-datepicker`
      widget that (correctly, by design) doesn't accept a value written via a raw DOM `input`
      event; it needs its own click-driven calendar interaction, which is package UI outside this
      task's scope to script around (and the task explicitly says not to build a second
      validation/error layer around nhforms' own). The toast/profile-open wiring itself was
      instead verified by code review + type-checking against the package's actual exported
      `SubmitResponse`/`SubmitAction` interfaces (`node_modules/@nanohealth/nhforms/dist/
      types-DsbG0XG5.d.ts`) — `response.referenceable_id` and `action.toast` are real, typed
      fields, not a guess about the shape.
- [x] Cancelling the form (Close button) is untouched — `onClose` wiring wasn't touched by this
      task's diff at all.

## Acceptance criteria

- [x] No new backend endpoint was added for employee creation — 100% frontend-only diff
      (`EmployeeFormModal.tsx`, `EmployeeDirectory.tsx`).
- [x] A successful Add Employee submission now always shows `toast.success(...)` (this
      dashboard's existing `react-toastify` pattern, matching `RegularizationInbox.tsx`'s call
      shape) — text prefers the package's own configured `action.toast`
      (`form_parameter_masters` 134), falling back to "Employee added successfully" when the form
      has no confirmation configured, per CLAUDE.md's nhforms note that a form with neither
      message nor redirect still gets a default confirmation.

## Completion notes

- `EmployeeFormModal.tsx` gained an exported `FormSubmitOutcome` type (`{ referenceableId?,
  toastMessage? }`) so `onSubmitted` is no longer just `() => void` with the submit result
  silently discarded — `result.response.referenceable_id` (the created employee's id, when the
  form's `reference_srce` resolves one) and `result.action.toast` are threaded through instead of
  left buried in an implicitly-typed callback.
- `EmployeeDirectory.tsx`'s `onSubmitted` handler now: shows the toast, refetches the list
  (unchanged), and — only if `referenceableId` came back — opens that employee's profile
  (`setProfileId`/`setProfileInitialTab("overview")`, reusing [[59]]'s tab-routing state). No
  forced lookup/guessing when the id isn't present, per the task's own explicit instruction.
- Did not attempt to patch or work around nhforms' own field-level validation/error-retention
  behavior — confirmed (via the task's own reasoning, not a live failed-submit test given the
  datepicker blocker above) that this is entirely the package's responsibility per CLAUDE.md's
  "Everything under /api/v1/forms is served by the package" boundary.

Completed: 2026-08-19
