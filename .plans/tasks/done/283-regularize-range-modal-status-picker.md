---
task: 283
title: Regularize range modal — day status picker (Present / Half day / WFH)
status: done
depends_on: [281]
---

# 283 — Regularize range modal — day status picker (Present / Half day / WFH)

## Scope
Add the 281 outcomes to the existing single-employee `RegularizeRangeModal.tsx` (opened from the employee Attendance tab). Backend is 281. The multi-employee modal reuses this
control (284), so build it as a small shared piece rather than inline.

- A **Mark as** control: `Present` · `Half day` · `Work from home`. `Half day` reveals a `First half` / `Second half` choice (default first) and hides the Custom-times option
  (half day is shift-derived). `Present` and `Work from home` keep the existing "Present for scheduled shift / Custom times" choice.
- Send `day_status` / `half` on preview and apply; changing any of them re-previews (debounced, signal-aborted, same lane) and resets ticks to the server defaults, like the mode does.
- New row messages/codes from the server render as today (`DAY_OPEN`, `NO_REMOTE_SITE`, `WFH_LOCKED`); a Work-from-home preview where every candidate is `NO_REMOTE_SITE` should show
  the server message once at the top rather than on every row. "Will become" column text: `Half day (first half) · 09:00–13:30`, `Work from home · <remote site name>` is not
  available client-side — show `Work from home` only.
- Primary button label follows the status ("Mark 8 days as half day" / "…work from home" / "Regularize N days").
- Result screen: `status` / `payable_day_fraction` already come back per day — show them.
- `lib/api.ts`: extend `RegularizeRangeTimes` (`day_status`, `half`) and `RegularizeRangeCode`; no new endpoint.

### Conventions
Tailwind only; shimmer skeleton for the loading body (existing); dates via `DateField`, dd-MMM-yy; `secureFetch`; modal chrome `px-5 py-4`; spacing per the `hrms-spacing` skill for page-level
pieces (a modal follows the modal convention).

## Files
`frontend/src/dashboards/shared/RegularizeRangeModal.tsx`, new `frontend/src/dashboards/shared/RegularizeStatusPicker.tsx`, `frontend/src/lib/api.ts`.

## Acceptance criteria
- [x] Three statuses selectable; Half day shows First/Second half and hides Custom times; Present/WFH keep Shift/Custom
- [x] Preview and apply requests carry `day_status` / `half`; switching re-previews and resets ticks
- [x] New codes show their server message; WFH with no remote site does not repeat the message on every row
- [x] Button label and result screen reflect the chosen status
- [x] `npx tsc --noEmit` clean; `eslint` adds no errors over the base
- [ ] Manual smoke check against a local stack (one half day, one WFH day with a remote site, one WFH with none) — or recorded as skipped by decision, as in 271

## As built (2026-10-27)
New `RegularizeStatusPicker.tsx` (state type `RangeOutcome`, helpers `outcomeFields` / `outcomeKey` / `outcomeLabel` / `outcomeAction`); the table, result list and form constants were
moved out of `RegularizeRangeModal.tsx` into `RegularizeRangeParts.tsx` (shared with 284). `NO_REMOTE_SITE` rows show "No remote site" and the modal shows the server sentence once on top.
Verified: `npx tsc --noEmit` clean; eslint on the touched files adds nothing. **Not verified:** anything needing the running app (no dev server was started, per the global rule) —
the manual smoke box below is left unchecked, as in 271.

Completed: 2026-10-27
