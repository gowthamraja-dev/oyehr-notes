---
task: 113
title: Remove the mousemove event listener from the activity tracker
status: done
depends_on: []
---

# 113 — Remove the mousemove event listener from the activity tracker

## Scope

`hrms/frontend/src/lib/activity-tracker.ts` treats `mousemove` as one of the six
DOM events (`mousemove`, `mousedown`, `keydown`, `wheel`, `touchstart`, `pointerdown`)
that count as "user is here" activity for the idle-logout timer
(`hrms/frontend/src/hooks/use-idle-timer.ts`). Remove `mousemove` from that list —
raw cursor movement (without a click/keypress/scroll/touch) should no longer reset
the idle timer or keep the session alive.

Does NOT cover: any of the other five activity events, the idle-timer/warning-modal
logic itself, or token refresh (`use-token-refresh.ts`) — those are unrelated and
must not be touched.

## Files

- `hrms/frontend/src/lib/activity-tracker.ts`:
  - Remove `"mousemove"` from the `ACTIVITY_EVENTS` tuple (currently
    `["mousemove", "mousedown", "keydown", "wheel", "touchstart", "pointerdown"]`).
  - Remove the now-dead mousemove-specific throttling in `handleEvent()`
    (`MOUSEMOVE_THROTTLE_MS`, `lastMousemoveAt`, and the `if (event.type ===
    "mousemove") { ... }` branch) — with mousemove no longer registered, this code
    path is unreachable.
  - Update the file's top-of-file doc comment if it references mousemove
    specifically (it currently doesn't name individual events, so likely no change
    needed there — just verify).

## Acceptance criteria

- [x] `ACTIVITY_EVENTS` in `activity-tracker.ts` no longer includes `"mousemove"`.
- [x] `MOUSEMOVE_THROTTLE_MS` / `lastMousemoveAt` and the mousemove branch in
      `handleEvent()` are removed (no dead code left behind).
- [ ] Moving the mouse alone (no click/keypress/scroll/touch) no longer resets the
      idle-logout timer — verified manually by watching the idle-warning modal
      appear on schedule despite continuous mouse movement. NOT verified in a
      browser this session (no dev server/browser available) — code change makes
      this true by construction (mousemove is no longer in `ACTIVITY_EVENTS`), but
      a manual UI check is still recommended before shipping.
- [x] `mousedown`, `keydown`, `wheel`, `touchstart`, `pointerdown` still count as
      activity, unchanged.
- [x] Frontend build passes — verified via `npx tsc --noEmit` (clean, no errors);
      `npm run build` was not run this session.
