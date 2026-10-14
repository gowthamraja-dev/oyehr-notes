---
task: 211
title: Audit mobile attendance API spec against backend and employeeapp
status: done
depends_on: []
---

# 211 — Audit mobile attendance API spec against backend and employeeapp

## Scope
Check, claim by claim, whether `.plans/hrms-mobile-attendance-api.md` (copied from
`~/Downloads/hrms-mobile-attendance-api.md` on 12-Oct-26) is actually implemented. Two sides:

1. **Backend** — read-only, in `workspace-2/hrms/` on `main` (the feature landed in
   PR #152 `feature/mobile-attendance-verification`, commit `4a2a423c` added punch-policy).
   Confirm `git -C workspace-2/hrms status -sb` shows a clean `main` that has pulled
   the latest changes first. The top-level `hrms/` is on `bugfix/gowtham_FreshDbMigrations`.
   Don't use it for this.
2. **Mobile client** — `employeeapp/` (branch `soumi-dev`), mainly
   `src/screens/ClockScreen/components/AttendanceScreen/`.

**Output:** a gap report at `.plans/mobile-attendance-api-audit.md`. It has one row per check
with the columns *spec claim · status (✅ done / ⚠️ partial / ❌ missing / 📄 doc wrong) ·
evidence (`file:line` or test name) · fix owner (backend / app / doc)*.

**NOT in scope:** fixing anything. Each gap becomes its own new task file (212+), and the doc
corrections go back to whoever wrote the spec. No punching against hrms-dev, because
§8 of the spec says that switches a real site on and signs you out of the web.

## Checklist — backend (`workspace-2/hrms/backend/`)

Endpoints and contract:
- [x] `POST /attendance/me/clock-in` and `/me/clock-out` take the same body. Fields:
      `punch_source` (default `"Web"`), `wifi_ssid` ≤120, `wifi_bssid` ≤64, `lttd`, `lgtd`,
      `accuracy_mtrs` ≥0, `location_error` ∈ {denied, timeout, unavailable, null}. All are optional
      in the schema (`modules/attendance/schemas.py`).
- [x] The 200 response has `punch_id, punch_at, direction, attendance_date, state,
      verification_status, is_within_geofence, shift{name,start_time,end_time,time_zone},
      late_by_minutes`.
- [x] An app punch that returns 200 is always `"Verified"`. An app punch at a site that isn't
      set up gets a 403 and is never recorded quietly.
- [x] SSID match is case-sensitive and not trimmed. BSSID is stored but never compared.
- [x] The accuracy check works: a coarse fix (accuracy larger than the allowed max) is refused
      even if its centre is inside the fence.
- [x] Missing evidence counts as unknown, and unknown is refused at an enabled site.
- [x] Each of the **nine 403 messages** in spec §3 exists, word for word, in
      `services/punch_verification_service.py`. List each message with its `file:line`.
- [x] A refused punch writes no punch row. It does write an audit-log row and stores the
      reported SSID against the site (the "312 failures on NanoHealth-5G" view).
- [x] 409 on a second clock-in, and the message includes the time. 401 when the session has
      been replaced (one live session per user).
- [x] `GET /attendance/me/today` returns `state` (not_started/clocked_in/clocked_out), first in,
      last out, seconds worked and lateness.
- [x] `GET /attendance/me/punch-policy` (router.py:264) returns every field in §6. Check the
      four `reason` codes. Check that `message` matches the refusal sentence and that a test
      asserts this. Check that SSIDs never appear in the response and that a test greps for
      them. Check that `web_punch_allowed` is the inverse of app-enabled.
- [x] Admin endpoints used in §8: `PATCH /attendance/work-locations/{id}`
      (`mobile_punch_enabled`). Enabling a site with no approved network must return 422.
      `POST/GET …/networks` and `POST …/networks/{id}/approve`. Check RBAC gates and CDP scoping.
- [x] Encryption: the spec says `EncryptedRoute` is **opt-in**, so a request without
      `X-Enc-Key` gets plain JSON. Check `app/api/encryption.py`, because CLAUDE.md implies it
      is mandatory.
- [x] Login: `subdomain` is optional, with 409 when the login matches more than one org.
      `login_id` accepts email, mobile or employee id. The OTP challenge token is refused
      everywhere except verify-otp.
- [x] `scripts/seed_punch_sandbox.py` exists. It is not in `backend/scripts/` today, so
      §8 may be stale.
- [x] Run `uv sync && uv run pytest app/tests/modules/test_attendance.py -k "punch or verif or
      policy"` against a throwaway Postgres (see memory: hrms-tests-on-throwaway-postgres).
      Record the pass/fail counts.

## Checklist — mobile (`employeeapp/`)

- [x] `punch_source: 'Mobile'` is hard-coded (`AttendanceService.js:16`). The same body goes
      to clock-in and clock-out.
- [x] `accuracy_mtrs` and `location_error` are sent. Wi-Fi and location are read **in parallel**.
      The location fix is fresh (not cached) with a 10 s timeout.
- [x] Android: Wi-Fi info comes from `ConnectivityManager`/`NetworkCapabilities`. The
      `<unknown ssid>` and `02:00:00:00:00:00` sentinels are sent as `null`. Surrounding quotes
      are stripped. `NEARBY_WIFI_DEVICES` is declared for API 33+.
- [x] iOS: `NEHotspotNetwork.fetchCurrent` and the Access WiFi Information entitlement are in
      place. Reduced accuracy (`CLLocationAccuracyReduced`) is caught before the request, with
      a "turn on Precise Location" prompt.
- [x] The app shows a 403 `detail` word for word and re-enables the button. A 409 refreshes from
      `/me/today`. A 401 clears the token and goes to login. Refused punches are never queued
      for retry, and evidence is never cached.
- [x] `/me/punch-policy` is called when the screen opens. The app hides the button and shows
      `message` when the answer is no. It asks for permissions only when `requires_*` is true.
      If the call fails, it still shows the button.
- [x] Permissions are requested on the attendance screen with an explanation, not at first launch.

## Spec inconsistencies to confirm (record as 📄 rows)
- The header says "everything except `GET /me/punch-policy` is built". §6 says it was built
  09-Oct-26.
- §3 says an app punch never sees `Unverified`. §7 item 8 expects `200, Unverified` when
  app punching is switched off.
- §6 has a `no_shift` reason that has no matching row in the §3 refusal table. The §3
  "no work location" wording also differs from `no_work_location` ("shift carries no work
  location").
- §8 says `alembic upgrade head` fails on an empty DB. Task 210 (PR #154) fixed fresh-DB
  migrations, so this is probably stale.
- The `hrms-mobile-api-integration` skill says "geofence is advisory, not enforced". This spec
  says it is enforced, so the skill may need updating.

## Files
- Creates `.plans/mobile-attendance-api-audit.md` (the gap report)
- Reads `workspace-2/hrms/backend/app/{services/punch_verification_service.py,
  modules/attendance/{router,schemas,service}.py, models/work_location_master.py,
  api/encryption.py, tests/modules/test_attendance.py}`
- Reads `employeeapp/src/screens/ClockScreen/**`, `employeeapp/android/app/src/main/AndroidManifest.xml`,
  and `employeeapp/ios/**/*.entitlements` and `Info.plist`

## Acceptance criteria
- [x] Every checklist item above has a row in the gap report with a status and evidence.
- [x] The backend test run is recorded (command plus pass/fail counts, including any failures
      already known to be unrelated).
- [x] Each ❌/⚠️ gap has its own new task file in `ongoing/` (212+). If there are none, the
      report says so.
- [x] The report ends with a one-paragraph verdict: is the backend ready for the app, and what
      does the app still lack.

Completed: 2026-10-12
