---
task: 112
title: Extend SESSION_TIMEOUT_OPTIONS with 1 min / 4 hr / 8 hr, backend validation, short warning for 1 min
status: done
depends_on: []
---

# 112 — Extend SESSION_TIMEOUT_OPTIONS with 1 min / 4 hr / 8 hr, backend validation, short warning for 1 min

## Scope

Extends the Organization Settings → Authentication panel's session-timeout dropdown
(previously covered end-to-end by [[111]]) with three new options and a matching
backend allow-list, plus a UX fix for the idle-logout warning popup on the shortest
option:

- Add `"1 minute"`, `"4 hours"`, `"8 hours"` to the frontend's
  `SESSION_TIMEOUT_OPTIONS`, alongside the existing 5/10/15/30/45/60-minute options.
  Default stays **30 minutes**.
- Backend validates `session_timeout_minutes` against an explicit allow-list
  `(1, 5, 10, 15, 30, 45, 60, 240, 480)` — matching the frontend options — instead of
  accepting any `int`, so a raw API call can't persist a value the UI doesn't offer.
- The idle-logout "Still there?" warning popup shows for **15 seconds** when the
  configured timeout is exactly 1 minute (instead of the default 60s warning, which
  wouldn't fit inside — or would overrun — a 1-minute session).

Does NOT cover: the `access_token_minutes` JWT-ceiling setting itself (already 480 by
default, so the new 8-hour option isn't clamped — see `organizations/service.py:get_session_timeout_minutes`),
or the 2FA/login flow.

## Files

- `hrms/backend/app/modules/organizations/schemas.py` — added
  `SESSION_TIMEOUT_MINUTES_OPTIONS` constant and a `field_validator` on
  `AuthPolicySettings.session_timeout_minutes`.
- `hrms/backend/app/modules/organizations/service.py` — updated the
  `get_session_timeout_minutes` docstring (the 8-hour option now sits exactly at the
  `access_token_minutes` ceiling, no longer "never binding").
- `hrms/backend/app/tests/modules/test_organizations.py` — added
  `test_auth_policy_session_timeout_accepts_all_options` and
  `test_auth_policy_session_timeout_rejects_unlisted_value`.
- `hrms/frontend/src/dashboards/hrAdmin/OrgSettings.tsx` — extended
  `SESSION_TIMEOUT_OPTIONS`; replaced the old `parseInt(sessionTimeout, 10)` /
  hardcoded `` `${minutes} minutes` `` round-trip (which broke on "4 hours"/"8 hours"/
  "1 minute") with `sessionTimeoutToMinutes` / `minutesToSessionTimeoutLabel` helpers
  that convert through the options array itself.
- `hrms/frontend/src/contexts/auth-context.tsx` — passes `warningMs: 15_000` to
  `useIdleTimer` when `session_timeout_minutes === 1`, otherwise leaves it at the
  hook's 60s default.

## Acceptance criteria

- [x] `SESSION_TIMEOUT_OPTIONS` (frontend) includes 1 min / 5/10/15/30/45/60 min / 4 hr / 8 hr;
      default remains "30 minutes".
- [x] Backend rejects any `session_timeout_minutes` not in `(1, 5, 10, 15, 30, 45, 60, 240, 480)`
      with a 422.
- [x] Save/load round-trip is correct for every option, including the hour-based ones
      (240/480 minutes save and reload as "4 hours"/"8 hours", not misparsed).
- [x] `useIdleTimer`'s warning window is 15s when the org's session timeout is 1 minute,
      and unchanged (60s default) for every other option.
- [x] `uv run pytest app/tests/modules/test_organizations.py -k auth_policy` passes (7/7).
- [x] `npx tsc --noEmit` in `hrms/frontend/` reports no errors.

Completed: 2026-09-18
