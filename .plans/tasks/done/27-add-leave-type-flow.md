---
task: 27
title: Add leave type modal + create-flow wiring
status: done
depends_on: [25, 26]
---

## As-built notes

- Exported `Toggle` and `todayIso` from `Leave.tsx` for reuse in the new modal rather than
  duplicating a second toggle-switch implementation — the only deviation from a literal reading
  of "new file, no changes to Leave.tsx besides wiring the button."
- Replaced [[26-leave-policy-frontend]]'s `window.prompt()` stopgap entirely: `handleAddLeaveType`
  is gone, replaced by `addModalOpen` state and `handleLeaveTypeCreated`.
- Manual QA completed in an actual browser end-to-end: Add → duplicate code ("ERN", already used
  by the "Earned" type from task 26's testing) surfaced inline under the Code field
  ("Leave type code 'ERN' already exists") → corrected to "SICK" → submit → modal closed, new
  "Sick Leave" type auto-selected in the list, empty policy state shown ("No leave policy
  configured", no fake policy created), toast fired, list count updated to "2 configured".
  `npx tsc --noEmit` / `npx eslint` clean on both files throughout.

# 27 — Add leave type modal + create-flow wiring

## Scope

The "Add leave type" flow (prompt §31), split out from [[26-leave-policy-frontend]] because it's
a self-contained modal + a small piece of post-create navigation, not part of the main
list/form screen itself.

## Files

- `frontend/src/dashboards/hrAdmin/CreateLeaveTypeModal.tsx` — new
- `frontend/src/dashboards/hrAdmin/Leave.tsx` — wire the "Add leave type" button (added in
  [[26-leave-policy-frontend]]'s `LeaveTypeList`) to open this modal

## Modal pattern

Follow `frontend/src/dashboards/shared/EmployeeFormModal.tsx`'s structure — fixed overlay
(`fixed inset-0 z-50 flex items-center justify-center bg-black/40`), centered panel,
`role="alertdialog" aria-modal="true"`. Internal padding follows the existing modal convention
(`px-5 py-4` header/body/footer) — this is the one place in the leave feature that does **not**
follow the `10px` page-spacing rule, since modal internals are a documented exception
(`hrms-spacing` skill).

## Fields (prompt §31 — minimum set)

```
Leave type name       → name (required)
Code                  → code (required)
Paid / Unpaid         → is_paid (toggle, default true)
Unit                  → "Day" only in v1, no control needed — don't render a selector for a
                          single fixed value
Allow half day        → allow_half_day (toggle, default false)
Requires approval     → requires_approval (toggle, default true)
Active                → not exposed here — a brand-new type is always created active; use the
                          policy-form's leave-type edit affordance (from
                          [[26-leave-policy-frontend]]) to deactivate later
Effective from        → effctv_dt (date, required, defaults to today)
```

Validation mirrors the backend ([[22-leave-type-api]]): `name`/`code` non-empty, submit disabled
until both are filled. Surface the backend's `422` message directly on duplicate `code`
(`"Leave type code '...' already exists"`) as a field-level error under the Code input, not a
generic toast.

## Post-create flow (prompt §31, exact sequence)

```
Admin fills form, submits
  → createLeaveType(input)                                  [25]
  → close modal
  → select the new type in LeaveTypeList (setSelectedLeaveTypeId)
  → getLeaveTypePolicy(newType.id) resolves policy: null
  → policy form renders the empty state — "No leave policy configured"
  → admin explicitly clicks [Create policy] and fills it in
  → Save
```

**Do not auto-create a policy row with arbitrary defaults** after the type is created — prompt
§31 explicitly forbids this ("Do not automatically create a fake policy containing arbitrary
defaults unless there is an explicit business default"). No such business default exists here.

## Acceptance criteria

- [x] Modal follows the existing modal visual/padding convention, not the page's `10px` rule
- [x] Submitting creates the leave type, closes the modal, selects it, and shows the empty
      policy state — never a pre-filled fake policy
- [x] Duplicate-code error surfaces inline on the Code field, not as a generic failure toast
- [x] Cancel/close discards the form with no side effects
- [x] Manually verified in-browser end-to-end (create → empty state → create policy → save →
      appears correctly in the list with its `policy_summary`), per CLAUDE.md's UI-testing rule
      — no automated frontend test runner exists in this repo to cover this instead

Completed: 2026-08-18
