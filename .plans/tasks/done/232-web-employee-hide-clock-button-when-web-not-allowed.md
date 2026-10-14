---
task: 232
title: Web employee — hide the clock button when web_punch_allowed is false
status: done
depends_on: [230]
---

# 232 — Web employee: hide the clock button when `web_punch_allowed` is false

Clone: **top-level `hrms/`**, same branch. Plan: `.plans/clockin-other-mode-web-key-plan.md`.

## Scope
Task 214 made the web **disable** the clock button, with a reason, whenever the policy blocks it.
The new rule is to **hide** it. After 230 the server computes `web_punch_allowed` fully: it is
false for no shift, no work location, app clock-in OFF, or the "Allow web clock-in" box off.
The web's own check mode (`Geofence` | `NoCheck`) is enforced by the server at punch time, so
the web no longer needs to look at `reason`. At a Geofence web site the browser's location is
already sent with every punch (`getPunchLocation`). A refusal (out of range or imprecise) shows
the server's message as today.

1. `frontend/src/lib/attendanceClock.ts`
   - Replace `webPunchBlockReason` with `canShowWebClock(policy: PunchPolicy | null | undefined): boolean`:
     - `undefined` (loading) → false, so no button flashes in;
     - `null` (the request failed) → true, so the server still decides and a flaky network
       never reads as "attendance off";
     - otherwise → `policy.web_punch_allowed`.
   - Update `WEB_PUNCH_BLOCKED_MESSAGE` to the new backend sentence, word for word: "Clocking in
     from the browser isn't switched on for your location. Please use the mobile app, or
     contact HR." It is now only used as the fallback toast text when a punch is refused.
   - Rewrite the docstring: it describes task 214's disable rule.
2. `frontend/src/dashboards/shell.tsx`, `AttendanceClockPill` (~43–131): when
   `!canShowWebClock(policy)`, render `null`. The pill is the button, so the header simply has
   no clock. Remove the `aria-disabled` / blocked tooltip plumbing.
3. `frontend/src/dashboards/Employee/MyAttendance.tsx`, `ClockCard` (~95–250): when
   `!canShowWebClock(policy)`:
   - don't render the Clock in/out button or the grey `blockReason` note;
   - keep the status line and the "worked today" timer, which are information, not an action.

   `hasNoShift` keeps disabling as it does today when the button is shown.
4. Clock-out is hidden under the same rule. An employee who clocked in elsewhere clocks out
   from the app. State this in the PR description.
5. `usePunchPolicy` keeps refetching on focus and visibility change. HR can flip the switch at
   any time.

## Files
- `frontend/src/lib/attendanceClock.ts`
- `frontend/src/dashboards/shell.tsx`
- `frontend/src/dashboards/Employee/MyAttendance.tsx`

## Acceptance criteria
- [ ] With the policy `web_punch_allowed=false`, there is no header pill and the card has no button and no grey note. The timer still shows.
- [ ] With the policy `web_punch_allowed=true` (NoCheck or Geofence site with the box on), the button shows. Clock in and out work, and a Geofence refusal shows the server's message.
- [ ] While the policy loads, no button flashes in. If the policy request fails (simulate it), the button shows.
- [x] `grep -rn webPunchBlockReason frontend/src` finds nothing.
- [x] `npx tsc --noEmit` is clean and lint adds nothing new. (Not smoke-tested in a browser — see below.)

Implemented 13-Oct-26, uncommitted on `feature/gowtham_ClockInNoCheck` (top-level `hrms/`). `tsc` is clean, and ESLint's findings on the four changed files are identical to `main`'s (4 that already existed).
- `canShowWebClock(policy)` in `lib/attendanceClock.ts` replaces `webPunchBlockReason`.
- **Deviation:** `WEB_PUNCH_BLOCKED_MESSAGE` was removed rather than reworded. After this change nothing used it: `clockIn`/`clockOut` already show the server's 403 `detail`, which carries the new sentence from task 230.
- `PunchPolicy` gained `web_check_mode`.
- Header pill: renders nothing when `!showClock`. The blocked `aria-disabled`/tooltip plumbing from task 214 is removed.
- `ClockCard`: the button and the grey note are gone when hidden. The timer stays, and the `mb-4` under "worked today" only applies when something follows it.
- The unticked behaviour checks above were **not** browser-verified. As with 231, a test needs `:3000` restarted against `:8000`.

Completed: 2026-10-13
