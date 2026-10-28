---
task: 271
title: Regularize range modal on the employee attendance tab
status: done
depends_on: [270]
---

# 271 — Regularize range modal on the employee attendance tab

## Scope
The HR-facing UI for the range endpoints from 270: a **Regularize range** button that opens a modal where HR picks dates, sees what will happen to each day, and
applies it in one click. Backend is 270; docs are 272.

Entry point: `frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx`, next to the existing single-day Regularize hint (`MissingClockOutHint`). Show the button only when the
caller can regularize on behalf (same condition the existing HR single-day flow uses — find it by grepping `regularize` in `frontend/src/`; a reporting manager must not see it).

### Modal layout
```
Regularize attendance — <name> (<emp id>)                                    ✕
From [DateField]  To [DateField]   (max 62 days)
Mark as  (•) Present for scheduled shift     ( ) Custom times  In [HH:MM] Out [HH:MM]
☑ Select all candidates (N)                                      Showing M days
table: ☑ | Date (Mon 01-Oct-26) | Now | Will become | Note
Reason [select]   Note* [text]
(only when a ticked row needs_override)  Reason to override* [text]
Summary line: "12 will be regularized · 1 locked (override) · 18 skipped · 2 blocked"
[Cancel] [Regularize 13 days]
```
Row states from the preview `action`: `regularize` → pre-ticked checkbox; `skip` → unticked, disabled, `message` shown (week-off, holiday, leave, already present);
`blocked` → ✕, disabled, `message` shown (no shift, future date, payroll closed, pending request, joining/relieving). A locked day (`needs_override`) is tickable and shows a 🔒 chip.

### Behaviour
- Preview (`POST .../regularize-range/preview`) fires when both dates are valid, or the mode / custom times change — debounced, with an `AbortSignal` (see task 181's `secureFetch` signal support).
  Reason / note edits do not re-run it. Changing the range or mode resets ticks to the server's defaults.
- "Select all candidates" toggles every `regularize` row. The primary button label and disabled state follow the ticked count; disabled until `note` is non-blank, and until
  `override_reason` is filled when any ticked row `needs_override`.
- Apply (`POST .../regularize-range`) sends the explicit ticked `dates` list. On `200`, the table turns into a result list (applied / skipped / failed per date, `message` on
  failures) with a **Done** button; failed rows can be re-ticked and retried. Refresh the attendance tab's data when the modal closes after any `applied > 0`.
- Whole-request errors (403/404/422) show the server `detail` inline; no native `alert`/`confirm`. No destructive step here, so `useConfirm` is not needed.

### Conventions to follow
Tailwind only (no `.module.css`); modal chrome `px-5 py-4` static, only the scrollable body swaps to a skeleton while the preview loads — compose it from `Shimmer*`
primitives in `components/ui/Shimmer.tsx` (`ShimmerTable` with the real column count, no plain "Loading…"); dates through `DateField` and displayed dd-MMM-yy; calls via
`secureFetch` with the bearer token. Match the existing modals' patterns (`ShareCredentialsModal.tsx` / `EditAdminModal.tsx`).

## Progress (2026-10-27) — implemented and committed (workspace-2, `f82f328`); browser smoke test skipped by decision
Committed on `feature/gowtham_regularize_range`; a later commit (`f82f328`) reworked the modal layout. The manual smoke check was deliberately skipped, so the UI-behaviour boxes below stay unchecked.
Built: `RegularizeRangeModal.tsx` (new), `previewRegularizeRange` (latestOnly lane `attendance.regularize_range.preview`) + `regularizeRange` and their types in `lib/api.ts`, the
"Regularize range" button + modal mount in `EmployeeAttendanceTab.tsx` (new props `employeeName`, `onRangeRegularized`; the tab itself checks APPROVE + UPDATE on ATTENDANCE, hooks called
unconditionally), `employeeName` passed from `EmployeeProfileView.tsx` and the HR Manager drawer in `hrManager/Attendance.tsx` (which also refreshes the register via `refreshRegister`
without closing the drawer). Preview state is keyed by the request (`previewKey`) so a stale answer is never shown and the effect sets no state synchronously.
Verified: `npx tsc --noEmit` clean for the whole project (needed `npm install --no-save jsqr@1.4.0`: the dependency was declared but missing from this clone's `node_modules`);
`eslint` on the touched files shows no errors beyond the ones already on the base (Attendance.tsx x3, EmployeeAttendanceTab.tsx x1, EmployeeProfileView.tsx x4 — set-state-in-effect /
conditional hooks that existed before).
Not verified: anything that needs the running app — see the unchecked boxes below. Deviation from the sketch: the modal also has a "Review again" action on the result screen
(re-previews so applied days read "already present" and failed days can be retried) and shows proposed times in the browser's time zone, like the single-day modal.

## Files
`frontend/src/dashboards/shared/EmployeeAttendanceTab.tsx`, new `frontend/src/dashboards/shared/RegularizeRangeModal.tsx`, API types/helpers next to the existing attendance API client
(find where `regularize` / `/attendance/employees/` calls live).

## Acceptance criteria
- [ ] Button visible to org-wide HR only; hidden for a reporting manager and for the employee's own view
- [ ] Opening the modal with a month shows the per-day table with correct pre-ticked candidates, disabled skip rows and blocked rows with their messages
- [ ] Switching "Present for scheduled shift" ↔ "Custom times" re-previews; custom times validated (both required, `HH:MM`)
- [ ] Override-reason field appears only when a ticked row is locked, and blocks submit until filled
- [ ] Apply sends only ticked dates; result list shows per-date outcome; partial failure keeps the modal open with failed rows retryable
- [ ] Attendance tab reflects the new statuses after closing
- [ ] Preview loading uses a shimmer table matching the real column layout; modal usable at narrow widths (table scrolls inside the body, no page-level horizontal scroll)
- [x] `tsc --noEmit` clean; `eslint` adds no errors over the base (see Progress). `npm run build` not run (needs `.env.dev`)
- [ ] Manual smoke check against a local stack (month with absent, missing clock-out, week-off, no-shift and locked days)
