---
task: 231
title: Web admin — No Check app mode and a Web clock-in block (switch + Location only / No Check) on Work Locations
status: done
depends_on: [230]
---

# 231 — Web admin: No Check app mode and a Web clock-in block on Work Locations

Clone: **top-level `hrms/`**, branch `feature/gowtham_ClockInNoCheck`. Paths are under
`frontend/src/dashboards/hrAdmin/WorkLocations_components/`. Plan: `.plans/clockin-other-mode-web-key-plan.md`.

## Scope
Backend contract (from 230):
- `mobile_punch_check_mode` accepts `"NoCheck"`;
- `web_punch_check_mode: "Geofence" | "NoCheck"` is accepted on create and PATCH;
- `web_punch_enabled: boolean` is PATCH only;
- turning web on with `Geofence` needs coordinates and a radius → 422;
- `WorkLocation` responses carry both fields.

The web mode is independent of the app mode.

1. `frontend/src/lib/api.ts`:
   - `PunchCheckMode` gets `| "NoCheck"`;
   - add `export type WebPunchCheckMode = "Geofence" | "NoCheck"`;
   - `WorkLocation` (~1669) gets `web_punch_enabled: boolean` and `web_punch_check_mode: WebPunchCheckMode`;
   - the input types get `web_punch_check_mode?` (create and update) and `web_punch_enabled?` (update).
2. `components/LocationFormModal.tsx`:
   - The app `CHECK_MODES` gets a 4th entry, last: `{ value: "NoCheck", label: "No Check",
     hint: "Punches are accepted without a Wi-Fi or location check and marked Unverified." }`.
   - Make the visibility explicit:
     - `wifiChecked = appMode === "Wifi" || appMode === "WifiAndGeofence"` (network panel);
     - `geofenceNeeded = appMode is Geofence/WifiAndGeofence || (webEnabled && webMode === "Geofence")`
       (coordinates and radius inputs).

     Today both are written as `!==`, so NoCheck would wrongly show both.
   - Add a **Web clock-in** block under the app block, edit only (like "Switched on"):
     - an **"Allow web clock-in"** checkbox, enabled only while app clock-in is switched on.
       Otherwise it is disabled, with the hint "Switch on app clock-in first.";
     - a web mode radio with two options:
       - "Location only": "The browser's location must be inside the allowed distance. Desktop
         locations can be imprecise.";
       - "No Check": "Browser punches are accepted without a check and marked Unverified."
     - Default: Location only. Sent as `web_punch_check_mode` on create as well, as a setting.
   - FormState gets `webPunchEnabled` and `webCheckMode`, loaded from the location, with dirty
     tracking as for the existing fields.
   - Rewrite the app clock-in blurb (~493). It currently says "Switching this on also stops
     browser clock-in for this location". The new copy: browser clock-in is controlled by the
     Web clock-in block below.
3. `index.tsx`:
   - `AppClockInPill` shows "On · no network" only when the app mode is a Wi-Fi mode.
   - Show "No Check" in the pill so HR can spot unchecked sites.
   - Add a **Web** column. Off / "On · Location" / "On · No Check", where On means
     `mobile_punch_enabled && web_punch_enabled`.
4. Follow `hrms-spacing` (page and list), the modal internals convention, and Tailwind only.

## Files
- `frontend/src/lib/api.ts`
- `WorkLocations_components/components/LocationFormModal.tsx`
- `WorkLocations_components/index.tsx`

## Acceptance criteria
- [ ] App No Check can be selected and saved, and reopening shows it. The network panel and geofence inputs hide unless the web uses Geofence.
- [ ] Turning app clock-in on for an app-NoCheck site with no coordinates or networks saves.
- [ ] "Allow web clock-in" is usable only with app clock-in on. Both the web switch and the web mode save and reload.
- [ ] Web on + Location only without coordinates shows the server's 422 in the modal error area. With No Check it saves.
- [ ] In the list, Geofence/NoCheck app sites don't show "On · no network", and the Web column reflects the rule.
- [x] `npx tsc --noEmit` is clean and lint adds nothing new. (Not smoke-tested in a browser — see below.)

Implemented 13-Oct-26, uncommitted on `feature/gowtham_ClockInNoCheck` (top-level `hrms/`). `tsc` is clean, and ESLint is clean on the four changed files (as on `main`).
- Beyond the spec: the "Allow web clock-in" checkbox keeps its saved value while app clock-in is off (disabled, with a hint) rather than clearing it, so switching the app back on restores it. The App clock-in pill also shows "On · No Check" (amber). The list skeleton went to 8 columns to match the new Web column.
- The unticked behaviour checks above were **not** browser-verified. The user chose to skip the smoke test rather than restart `:3000` against `:8000`.

Completed: 2026-10-13
