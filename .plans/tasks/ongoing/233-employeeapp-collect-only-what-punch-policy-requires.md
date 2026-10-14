---
task: 233
title: Employee app — collect only what the punch policy requires (No Check punches instantly)
status: ongoing
depends_on: [230]
---

# 233 — Employee app: collect only what the punch policy requires

Repo: **`employeeapp/`** (React Native, its own git; currently on `gowtham-dev`; check `git -C employeeapp status -sb`
and branch off before starting). Backend contract from task 230 (top-level `hrms/`, branch
`feature/gowtham_ClockInNoCheck`). The punch endpoints and keys are unchanged. This is an optimisation, not a fix:
the app already works at a No Check site.

## Why
`Attendance.js:handleAttendanceAction` (~line 131) always runs three steps before every punch:
1. `ensureLocationPermission()`, which can show the Android permission prompt;
2. `getCurrentWifiName()` / `getCurrentWifiBssid()`;
3. `getCurrentCoords()` inside `AttendanceViewModel.handleAttendanceAction`. This can wait up to
   `GEOLOCATION_TIMEOUT_MS` = 15 s for a fresh fix (`utils/location.js`).

At a site whose app check mode is **No Check** the server checks none of it and records the punch as
`Unverified`. The punch-policy response already says so: `GET /attendance/me/punch-policy` returns
`can_punch_from_app: true, requires_wifi: false, requires_location: false, check_mode: "NoCheck"`.
The app fetches that policy (`getPunchPolicyData`, held in `punchPolicy` state) but only reads
`can_punch_from_app` (`AttendanceViewModel.canPunchFromApp`). At a No Check site that costs the
employee a permission prompt and up to 15 s per punch, for nothing.

## Scope
1. `AttendanceViewModel.js`: add `evidenceNeeded(policy)`, returning `{ wifi, location }`:
   - `policy` null (the policy request failed) → `{ wifi: true, location: true }`. This is today's
     behaviour: collect everything and let the server judge. Same principle as `canPunchFromApp`.
   - `policy.requires_wifi || policy.requires_location` → `{ wifi: true, location: true }`. Unchanged
     for every checking mode (Wifi, Geofence, WifiAndGeofence):
     - on Android, reading the SSID needs fine-location permission anyway;
     - the server records position at Wi-Fi-only sites, and observed SSIDs at Geofence sites, as
       audit evidence. Collecting only the strict minimum would lose that.
   - otherwise (No Check) → `{ wifi: false, location: false }`.
2. `AttendanceViewModel.handleAttendanceAction(state, wifi_ssid, wifi_bssid, { location })`: when
   `location` is false, skip `getCurrentCoords()` and pass `null` coords. `buildPunchPayload`
   already maps null to `lttd/lgtd/accuracy_mtrs/location_error: null`. `location_error` must
   stay **null**, not `'denied'`, because nothing was asked.
3. `Attendance.js:handleAttendanceAction`: compute `const need = AttendanceViewModel.evidenceNeeded(punchPolicy)`.
   - Only call `ensureLocationPermission()` and the Wi-Fi reads when `need.wifi || need.location`.
   - Pass `need.location` through.
4. **Stale policy:** the policy is loaded on screen focus. If HR changes the mode between that load and
   the punch, a No Check skip could reach a site that now checks, and the server refuses with a
   readable 403 ("Couldn't read your Wi-Fi network…"). In the `catch`, refresh the policy
   (`getPunchPolicyData()`) after showing the error, so the employee's retry collects the right evidence.
   No automatic retry.
5. **Docs:** `.claude/skills/hrms-mobile-api-integration/SKILL.md` §10.1 (~line 450) is out of date. It
   says the geofence "is advisory/reporting only — it does not block the clock-in", which stopped being
   true when app-punch verification shipped (sites with app clock-in on refuse failed checks with 403).
   Rewrite §10.1 to cover:
   - call `GET /attendance/me/punch-policy` before drawing the button;
   - `can_punch_from_app` (hide the button when false, but show it if the request fails);
   - `requires_wifi` / `requires_location` (what to collect);
   - `check_mode` (Wifi | Geofence | WifiAndGeofence | **NoCheck**; display only);
   - the 403 refusal with a readable `detail`, and `verification_status` (`Verified` | `Unverified`)
     on the response;
   - that `web_punch_allowed` / `web_check_mode` are for the web client and the app ignores them.

   Keep it in the skill's existing voice. Also update the skill's front-matter description if it
   still says "geofence is advisory not enforced".

**Not in scope:**
- any backend change;
- reading `web_*` keys;
- iOS Wi-Fi entitlement (still missing, see `.plans/mobile-attendance-api-audit.md`; on iOS
  `hasLocationPermission()` returns true without asking, so step 3 only removes the Wi-Fi reads
  and the location wait there).

## Files
- `employeeapp/src/screens/ClockScreen/components/AttendanceScreen/AttendanceViewModel.js`
- `employeeapp/src/screens/ClockScreen/components/AttendanceScreen/Attendance.js`
- `.claude/skills/hrms-mobile-api-integration/SKILL.md` (§10.1, front-matter description)

## Acceptance criteria
- [ ] Where the policy says `can_punch_from_app: false` (no shift, no work location, app clock-in off, Wi-Fi site with no network), the clock in/out button is not shown at all. It shows again on refocus once allowed.
- [ ] At a No Check site (policy `requires_wifi = requires_location = false`): no location permission prompt, no Wi-Fi read, no location wait. The punch is sent at once with null evidence and `location_error: null`, and the response shows `verification_status: "Unverified"`.
- [ ] At Wifi, Geofence and WifiAndGeofence sites, behaviour is unchanged: permission, then Wi-Fi, then location, as today.
- [ ] With the policy request failing (`punchPolicy` null), the app collects everything as today.
- [ ] After a 403 refusal, the policy is refetched (verify with a log or the network inspector).
- [ ] `npm run lint` adds nothing new. `npm test` passes (only `__tests__/App.test.tsx` exists). Smoke-tested on an Android device or emulator against a backend running task 230, at a No Check site and at one checking site.
- [x] SKILL.md §10.1 describes punch-policy, verification and No Check, and no longer says the geofence never blocks.

## Progress (13-Oct-26)
Code is done, uncommitted, on employeeapp branch `feature/gowtham_PunchEvidenceByPolicy` (cut from `gowtham-dev`).
- `AttendanceViewModel.evidenceNeeded(policy)` skips collection only when the policy says `can_punch_from_app: true` and both `requires_*` false. A null policy, or `can_punch_from_app: false`, collects everything.
- `handleAttendanceAction(..., { location })` sends null coords when skipped. `Attendance.js` gates the permission prompt and the Wi-Fi reads, and refetches the policy after a failed punch.
- ESLint findings on the changed folder are identical to `gowtham-dev` (4 that already existed).
- `npm test` **cannot run, on `gowtham-dev` too**: `jest.config.js` uses the preset `@react-native/jest-preset`, which isn't installed. Not fixed here (it needs a new devDependency).
- Skill §10.1 has been rewritten, punch-policy added to the §10 endpoint table, and the front-matter "geofence is advisory" removed.
- **Added 13-Oct-26 (at the user's request): hide, don't disable.** When `can_punch_from_app` is false, `Attendance.js` no longer renders the punch button at all. That covers clock-in and clock-out, which are the same button. Previously it showed dimmed (`clockButtonDisabled`, now removed from `AttendanceStyles.js`). This matches the web (task 232). A failed policy request still shows the button. No flash on first load, because the screen shows its shimmer until the policy has loaded. The Attendance screen holds the only clock button in the app. Lint is unchanged.
- **Still open:** the device/emulator smoke test. A phone and `emulator-5554` are attached, but the test needs a work location on shared hrms-dev set to No Check and a real punch, which writes real attendance rows. Waiting for the user's go-ahead.
