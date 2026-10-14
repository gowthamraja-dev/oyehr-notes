---
task: 214
title: Web employee clock button respects punch-policy
status: done
depends_on: [211]
---

# 214 — Web employee clock button respects punch-policy

## Scope
At a site where app clock-in is switched on, the backend refuses browser punches with 403
"Clocking in from the browser is switched off for your location. Please use the mobile app."
The web UI never asks beforehand, so the button stays live and the employee only finds out
after clicking. Fix this in `workspace-2/hrms/frontend/src/`.

1. Add `getPunchPolicy(token)` to `lib/api.ts`. It calls `GET /api/v1/attendance/me/punch-policy`
   through `secureFetch` (the attendance router is `EncryptedRoute`). Add a `PunchPolicy` type
   with these fields: `can_punch_from_app`, `reason`, `message`, `requires_wifi`,
   `requires_location`, `lttd`, `lgtd`, `geo_fence_radius_mtrs`, `max_location_accuracy_mtrs`,
   `work_location_name`, `web_punch_allowed`.
2. Two places call it: the header pill `AttendanceClockPill` (`dashboards/shell.tsx:43-131`) and
   `ClockCard` (`dashboards/Employee/MyAttendance.tsx:154-198`). Each calls it on mount and on
   window focus or visibility change. HR can switch a site on at any time, so don't cache it
   for the session.
3. When `web_punch_allowed === false`, replace the button with a muted note: "Clocking in from
   the browser is switched off for your location. Please use the mobile app." The text must
   match the backend sentence (`service.py:846-847`). If the policy call **fails**, show the
   button anyway and let the server decide.
4. **Added 12-Oct-26 (user decision): disabled when app clock-in is OFF.** If the employee's
   assigned shift has no work location, or that location doesn't have app clock-in enabled
   (policy `reason` is `no_shift`, `no_work_location` or `site_not_enabled`), the web clock
   button is **disabled**, with the policy `message` as the reason. Together with item 3
   (disabled when `web_punch_allowed === false`, i.e. app clock-in ON), the browser button can
   never be used while the policy loads. The user chose this knowingly. The backend is
   unchanged and would still accept an Unverified web punch at an OFF site.
   Clock-**out** follows the same rule. If the policy request fails, the button stays enabled.
5. Add `verification_status` and `is_within_geofence` to the `ClockAction` type (`lib/api.ts:~2335`).
6. Have `clockIn`/`clockOut` (`lib/api.ts:2355,2373`) also send `accuracy_mtrs` (`pos.coords.accuracy`)
   and `location_error` (`"denied"`/`"timeout"`/`"unavailable"` from the GeolocationPositionError
   code). This gives web punches the same audit evidence. Raise the timeout in `lib/geolocation.ts:4`
   from 5 s to 10 s, as the spec does for mobile.
7. For other non-OK statuses, show `_detailMessage(...)` instead of the generic "Failed to clock in".

## Files
- `frontend/src/lib/api.ts`, `frontend/src/lib/geolocation.ts`
- `frontend/src/dashboards/shell.tsx`, `frontend/src/dashboards/Employee/MyAttendance.tsx`

## Acceptance criteria
- [ ] At an enabled site, both the pill and the card show the note instead of a button, and no request is sent.
- [ ] At a site that isn't enabled (and with no shift or no work location), the button is disabled and shows the policy message.
- [ ] When the policy request fails (simulate it), the button still shows.
- [ ] `npm run build` and lint pass, and both screens are smoke-tested in a browser.

Implemented in workspace-2/hrms commit `f4262c3` on `feature/gowtham_WebPunchPolicy` (pushed; PR to `main`). `tsc` clean, lint adds nothing new. The unticked checks above were **not** browser-verified. Moved to done at the user's request.

Completed: 2026-10-12
