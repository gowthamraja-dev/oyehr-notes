# Mobile attendance API: implementation audit (task 211)

Spec under audit: `.plans/hrms-mobile-attendance-api.md` (copied from `~/Downloads` on 12-Oct-26).
Audited on 12-Oct-26 against:

- the backend and web frontend in `workspace-2/hrms` on `main` @ `95b21b2`, clean tree. PR #152 (`4c8bb81`) and punch-policy (`4a2a423`) are both included. The top-level `hrms/` has the same commit and an identical `frontend/src`.
- the mobile app in `employeeapp/` on branch `soumi-dev`.

Status key: ✅ done · ⚠️ partial · ❌ missing · 📄 the doc is wrong.
Backend paths are relative to `workspace-2/hrms/backend/`. Web paths are relative to `workspace-2/hrms/frontend/src/`. App paths are relative to `employeeapp/`.

## Verdict

**Backend: ready for the app.** All four §3/§6 endpoints exist with the documented contract. Wi-Fi and geofence checks are enforced, and all nine refusal sentences are in the code. Attendance tests pass (157/159; the two failures are fixture gaps in an empty database, see below). What's left is five small correctness bugs (task 212) and missing test coverage (213). None of them blocks a mobile build.

**Web frontend: the HR-admin side mostly exists.** HR can toggle app clock-in per site, edit the geofence and accuracy limit, add and approve networks, and see unrecognised SSIDs. The **employee side ignores punch-policy**: at an app-only site the browser clock button stays live and the employee only learns about the block from a 403 after clicking. Verification status and refused attempts are not shown anywhere. Tasks 214–216.

**Mobile app: wired up, but not shippable on iOS.** There is no Access WiFi Information entitlement, so every iOS punch sends `wifi_ssid: null` and is refused. Reduced (non-Precise) location is not detected, and there is no BSSID on iOS (task 217). The shared JS flow also differs from the spec: reads run serially, the timeout is 15 s, there is no 409 refresh, the policy message is never shown, and permissions are requested without checking `requires_*` (task 218).

**The spec itself has several wrong or stale statements.** The most important: §7 item 8 is wrong (an app punch at a switched-off site gets a **403**, not 200 Unverified). The §8 sandbox scripts aren't in any repo. The `hrms-mobile-api-integration` skill still says the geofence is "advisory". Task 219.

## Test run

A throwaway `postgres:18` (removed afterwards) was migrated with `scripts/migrate.py upgrade heads` from an empty database, which **worked**. It was seeded with parameter rows, one user, and the leave, attendance and attendance-request status masters.

`uv run pytest app/tests/modules/test_attendance.py` gave **157 passed, 2 failed**. Both failures are environmental: `test_create_work_location_with_state_seeds_holiday_calendar` and `test_updating_work_location_address_does_not_overwrite_existing_calendar` need Telangana rows in `state_masters`/`city_masters`. All punch, verification, policy and network tests pass.

## Backend

| Spec claim | Status | Evidence | Fix owner | Note |
|---|---|---|---|---|
| Same body for clock-in and clock-out; field limits; all fields optional | ✅ | `app/modules/attendance/schemas.py:178-207` | — | `punch_source` is `Literal["Web","Mobile"]`, default `"Web"` |
| 200 response fields | ✅ | `schemas.py:253-273`, `service.py:969-979,1074-1084` | — | |
| App punch that returns 200 is always Verified; a site that isn't set up gets a 403 | ✅ | `services/punch_verification_service.py:158-172`; tests `test_app_punch_at_a_site_that_never_opted_in_is_refused`, `test_app_punch_with_no_work_location_is_refused` | — | |
| "Omit `punch_source` and every punch is refused" | 📄 | `punch_verification_service.py:165-179`; `test_web_punch_at_a_site_that_never_opted_in_is_unverified_not_refused` | doc | Only true at an **enabled** site. Elsewhere the punch defaults to Web and gets 200 Unverified |
| SSID is case-sensitive; BSSID stored, not compared | ✅ | `punch_verification_service.py:79,199-202,136` | test (213) | Both sides are `.strip()`ped, which is harmless. No test covers case-sensitivity |
| Coarse accuracy is refused inside the fence | ✅ | `punch_verification_service.py:94-99,222-227`; `test_app_punch_with_coarse_accuracy_is_refused` | — | Threshold is `max_location_accuracy_mtrs`, falling back to the radius |
| Missing evidence = unknown = refused | ⚠️ | `punch_verification_service.py:224` | backend (212) | A missing SSID or missing coordinates is refused. **A missing `accuracy_mtrs` passes as Verified** |
| The nine 403 sentences | ✅ | `modules/attendance/service.py:842-873` (`_refusal_message`) | doc | All exact, except §3 row 5. The code says "Your location isn't precise enough to confirm. **Move near a window and try again.**" and the spec drops that last sentence |
| Refusal writes no punch row, writes an audit row, stores the SSID against the site | ✅ | `service.py:785-839`; `test_app_punch_wrong_wifi_is_refused_and_writes_no_punch`, `test_observation_records_an_unrecognised_network_even_when_refused` | test (213) | SSID observation is recorded only at enabled sites (`punch_verification_service.py:256`). **No test asserts the `ClockInRefused` audit row** |
| 409 on a second clock-in, with the time | ⚠️ | `service.py:890` | backend (212) | The time is **UTC** `punch_at:%H:%M`, so an IST user sees 03:34 for a 09:04 punch. Clock-out has its own 409, "No active clock-in found.", which the spec doesn't list |
| 401 when the session is replaced | ✅ | `api/deps.py:237-238`; `auth/service.py:800,855,1012` | test (213) | Covered only indirectly by tests |
| `/me/today` fields | ✅ | `schemas.py:276-289`, `service.py:1087-1144` | — | The seconds field is named `worked_seconds_so_far` |
| `/me/punch-policy` fields | ✅ | `router.py:264`, `schemas.py:210-250`, `service.py:1152-1217` | — | Self-service and ungated |
| Four reason codes; `message` = the refusal sentence; a test asserts it | ⚠️ | `service.py:916` vs `:1174`; `test_policy_reason_matches_what_a_punch_would_actually_say` | backend (212) | `no_shift` is a **400** at clock-in, with no full stop: "…— contact HR". The policy has a full stop: "…— contact HR.". The parity test covers only `site_not_configured` |
| SSIDs never in the policy response; a test greps for them | ✅ | `test_policy_never_reveals_the_approved_network_names` | — | |
| `web_punch_allowed` | ✅ | `service.py:1201-1216` | doc | It is the inverse of `mobile_punch_enabled`, not of `can_punch_from_app` |
| Web punch at an enabled site → 403 "…use the mobile app." | ✅ | `test_web_punch_is_refused_at_an_enabled_site` | — | |
| `PATCH /work-locations/{id}`: enabling without networks → 422 | ✅ | `service.py:340-341,2191-2221`; `test_enabling_without_coordinates_or_networks_is_refused` | backend (212) | The guard runs only when the flag is set to true. Clearing coordinates or radius on an **already enabled** site is not blocked, and punches there then fail with the misleading "Couldn't confirm your location" |
| Networks list, add and approve | ⚠️ | `router.py:131-171`, `service.py:2224-2319` | backend (212) | **Approve sets `is_active=True` but leaves `archive=True`** (`service.py:2311`). A removed network then shows as approved but never matches (`punch_verification_service.py:76`) |
| RBAC gates and CDP scoping on the admin routes | ✅ | `router.py:62-63`, `require_grid_permission` in the service; `test_networks_do_not_leak_across_tenants` | test (213) | The network routes have no `test_authz` coverage |
| Encryption is opt-in | ✅ | `api/encryption.py:3-8,26-29` | doc (219) | Conflicts with the mobile skill's "don't ship without encryption". Policy and network routes have no encrypted round-trip test (213) |
| Login: optional subdomain/409, login_id variants, challenge token refused | ✅ | `auth/schemas.py:13-21`, `auth/service.py:198-256`, `deps.py:53,219-220` | doc | `expires_in` is **600**, not 300 |
| `scripts/seed_punch_sandbox.py` and the `.ps1` scripts | ❌ | Not in either clone or in `git log --all` | doc (219) | They exist only on the spec author's machine (`C:\Drive\Nanohealth`) |

## Web frontend (front-end changes the spec mentions or implies)

| Web item | Status | Evidence | Backend endpoint | Note |
|---|---|---|---|---|
| Employee clock button uses `GET /me/punch-policy` (`web_punch_allowed`) | ❌ | No `punch-policy` anywhere in `frontend/src`. Header pill `dashboards/shell.tsx:43-131`; ClockCard `dashboards/Employee/MyAttendance.tsx:154-198` | ✅ `router.py:264` | Task 214. The employee only finds out from the 403 after clicking |
| 403 `detail` shown word for word | ✅ | `lib/api.ts:2351-2386` → toast / `actionError` banner | ✅ | Other non-OK statuses become a generic "Failed to clock in" |
| Web sends `punch_source: "Web"` | ✅ | `lib/api.ts:2355,2373` | ✅ | Does not send `accuracy_mtrs` or `location_error`. `lib/geolocation.ts:4` times out at 5 s. The `ClockAction` type has no `verification_status` (214) |
| HR toggle for app clock-in, and the 422 | ⚠️ | `dashboards/hrAdmin/WorkLocations_components/components/LocationFormModal.tsx:430-448`, PATCH :245-279 | ✅ | The checkbox is tickable in **create** mode, but `WorkLocationIn` (`schemas.py:26-36`) has neither `mobile_punch_enabled` nor `max_location_accuracy_mtrs`, so both are silently dropped. The list (`WorkLocations_components/index.tsx:88-95`) has no App clock-in or network-count column (215) |
| Approved networks: add, list, approve seen SSIDs | ⚠️ | `WorkLocations_components/components/NetworkPanel.tsx` (in the edit modal) | ✅ `router.py:131-171` | Failing SSIDs are visible only inside one location's edit modal. `last_seen_at` isn't shown. The skeleton is a hand-rolled `animate-pulse` instead of Shimmer. Remove has no `useConfirm()` (215) |
| Geofence config: lat/long, radius, accuracy limit | ✅ | `LocationFormModal.tsx:380-428` | ✅ | The accuracy limit is ignored on create (same schema gap) (212/215) |
| `verification_status` / `is_within_geofence` shown anywhere | ❌ | `TodayPunch.verification_status` is typed (`lib/api.ts:1864-1871`), but the popover in `dashboards/hrManager/Attendance.tsx:1027-1029,1143-1146` doesn't render it | ✅ today-punches returns it; ❌ register/daily-log/export don't | Task 216 |
| View of refused punch attempts | ❌ | — | ❌ no read endpoint over `attendance_audit_log` | Task 216 |
| 401 after a login elsewhere → back to login | ✅ | `lib/api.ts:331,540` | — | |

## Mobile app (`employeeapp/`)

| Spec item | Status | Evidence | Note |
|---|---|---|---|
| `punch_source: 'Mobile'`; same body both directions | ✅ | `src/screens/ClockScreen/components/AttendanceScreen/AttendanceService.js:14-34` | Shared `buildPunchPayload` |
| `accuracy_mtrs` and `location_error` sent | ✅ | `AttendanceService.js:21-22`, `src/utils/location.js:103-120` | |
| Fresh fix, 10 s timeout | ⚠️/❌ | `location.js:8` (15000), `:14,42,85` (`maximumAge: 10000`) | Task 218 |
| Wi-Fi and location read in parallel | ❌ | `Attendance.js:137-139` → `AttendanceViewModel.js:97` → `location.js:97` | Fully serial (218) |
| Android: `<unknown ssid>` and `02:00:…` sent as null; quotes stripped | ✅ | `AttendanceViewModel.js:17,29`; `react-native-wifi-reborn` strips the quotes | |
| Android: BSSID read with no Wi-Fi | ⚠️ | lib `RNWifiModule.java:456-458` calls `toUpperCase()` on a value that may be null | Possible native NPE on mobile data only. Check on a device (217) |
| Android: `NEARBY_WIFI_DEVICES` | ⚠️ | `android/app/src/main/AndroidManifest.xml:8`; `location.js:27-34` | Declared, never requested at runtime (217) |
| Android: `ConnectivityManager`, not the deprecated `getConnectionInfo` | ❌ | lib `RNWifiModule.java:456,726` | Optional (217) |
| iOS: Access WiFi Information entitlement | ❌ | No `*.entitlements` file and no `CODE_SIGN_ENTITLEMENTS` in `ios/NanoDemo.xcodeproj` | **Blocker: every iOS punch is refused (217)** |
| iOS: BSSID | ❌ | The library has no iOS `getBSSID` | Always null (217) |
| iOS: Precise Location off caught before the request | ❌ | `location.js:23-24`; `@react-native-community/geolocation` has no `accuracyAuthorization` | Needs native code (217) |
| 403 `detail` shown word for word; button re-enabled | ✅ (fragile) | `Attendance.js:152-159`; `src/utils/ErrorUtils.js:38-56` | Filtered to ≤150 characters and a keyword blocklist. All nine messages pass today (218) |
| 409 → refresh `/me/today` | ❌ | `Attendance.js:148-156` | (218) |
| 401 → clear the token and go to login | ⚠️ | `src/api/NetworkManager.js:152-160`; `src/auth/AuthManager.js` | Tries `/auth/refresh` first, and shows an error dialog during the redirect (218) |
| No retry queue; evidence not cached | ✅ | | |
| `/me/today` and `/me/punch-policy` called on screen focus | ✅ | `Attendance.js:51-83` | |
| Button hidden and `message` shown when `can_punch_from_app` is false | ⚠️ | `Attendance.js:109,193-196` | Only greyed out. `message` is never shown (218) |
| Permissions asked only when `requires_*` is true | ⚠️ | `requires_*` is never read | (218) |
| Policy call fails → button still shown | ✅ | `AttendanceViewModel.js:71-81` | |
| Permissions explained before the prompt; recovery through Settings | ❌ | No `rationale`, no `Linking.openSettings` | (218) |
| Client-side geofence pre-warning (optional) | ❌ | Policy coordinates unused | Optional (218) |

## Spec corrections (task 219)

1. §7 item 8: an app punch at a site with app punching switched off gets **403 `site_not_enabled`**, not 200 Unverified. §3 is right.
2. §3 "omit `punch_source` → refused" is only true at enabled sites.
3. The §3 "Fix too coarse" message is truncated (see the backend table).
4. The header says punch-policy isn't built. It was built on 09-Oct.
5. §6 `no_shift` is a **400** at clock-in, not a 403, and has no row in the §3 table. §3 "Other statuses" also misses 400 (no shift), 423 (locked day), and the object-shaped 403 `detail` (`{code, message}`, account inactive).
6. The §7 item 3 substring "not on your office Wi-Fi" never appears. The real text is "You don't appear to be on your office Wi-Fi".
7. The OTP `expires_in` is 600, not 300.
8. §8: `alembic upgrade head` on an empty database is fixed by PR #154, but use `scripts/migrate.py upgrade heads`. `seed_punch_sandbox.py` and the `.ps1` scripts aren't in the repo. The sandbox admin also needs an ATTENDANCE grid, because attendance refuses roles with no grid.
9. `hrms-mobile-api-integration` skill: the "geofence is advisory" text is wrong. It needs the new clock body, punch-policy and the nine refusals. Encryption "mandatory" vs "skip it" needs a decision.

## Follow-up tasks
Scope decision (12-Oct-26): **only the web changes are being done.** The backend, mobile-app and
spec/skill findings above are recorded for reference only, with no tasks. Task numbers 212, 213 and
217–219 in the tables above refer to tasks that were drafted and then dropped.

- **214**: web employee clock button respects punch-policy
- **215**: web Work Locations admin: create path (accuracy saved through a follow-up PATCH), list columns, NetworkPanel polish
- **216**: web verification badge in the HR attendance popover (the refused-attempts view is dropped because it needs a backend endpoint)
