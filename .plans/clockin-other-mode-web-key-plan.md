# Clock-in "No Check" mode + per-site web clock-in — plan

Schema (approved 13-Oct-26, rev 2 — the contract): `.plans/clockin-other-mode-web-key-schema.dbml`
Clone: **top-level `hrms/`**, branch `feature/gowtham_ClockInNoCheck` off `main` (which already has the task 214–216 web-punch work).
Tasks: 229 (models + migration) → 230 (backend) → 231 (admin web) and 232 (employee web).

## Scope
1. The app's check mode gains a fourth option, **No Check** (`NoCheck`), offered once app clock-in
   is on. An app punch at a NoCheck site is accepted with no Wi-Fi or location check and
   recorded as `Unverified`.
2. Both policy keys stay: `can_punch_from_app` and `web_punch_allowed`. Each site gets:
   - **Allow web clock-in** (`web_punch_enabled`, default false);
   - a **web check mode** (`web_punch_check_mode`: `Geofence` (default) | `NoCheck`). It is
     independent of the app's mode and never Wi-Fi, because a browser can't read the network name.

   ```
   web_punch_allowed = loc is not None AND loc.mobile_punch_enabled AND loc.web_punch_enabled
   ```
3. When `web_punch_allowed` is false, the web **hides** the clock button (header pill and My
   Attendance card) instead of showing a disabled one.

**Out of scope:**
- the mobile app (`employeeapp/`). Its keys are unchanged. At a NoCheck site the server
  ignores whatever evidence it sends.
- turning a site on at create time. The create path stays locked, as in task 215.
- a NoCheck-specific `verification_status`. `Unverified` is reused.

## Flow

| Site | `can_punch_from_app` | `web_punch_allowed` | App punch | Web punch |
|---|---|---|---|---|
| no shift / no work location / app clock-in OFF | false | false | refused (as today) | **refused** (new: today accepted as Unverified) |
| app ON, web box off | per app mode (as today) | false | per app mode | refused |
| app ON, web box on, web mode `Geofence` | per app mode | **true** | per app mode | checked on geofence + accuracy (`max_location_accuracy_mtrs` / radius) |
| app ON, web box on, web mode `NoCheck` | per app mode | **true** | per app mode | accepted, `Unverified` |
| app mode `NoCheck` | true, `requires_wifi = requires_location = false` | (as above) | accepted, `Unverified` | (as above) |

The app's mode and the web's mode are independent. For example, the app on `WifiAndGeofence`
and the web on `Geofence` is valid.

## Backend (task 230)
- `services/punch_verification_service.py` (229 already added `CHECK_NONE`, `WEB_CHECK_MODES` and
  `web_check_mode(loc)`, which falls back to Geofence):
  - `web_punch_allowed(loc) -> bool`: the single source of the formula above.
  - `verify_punch`, web:
    - not allowed → `Refused` / `web_punch_not_allowed`, with the cause in the evidence;
    - `web_check_mode == NoCheck` → `Unverified`;
    - `Geofence` → the same geofence + accuracy checks the app runs.

    The evidence records `check_mode` (the mode the punch was judged by) and `punch_source`.
  - `verify_punch`, app with mode `NoCheck` → skip every check and return `Unverified`
    (`is_within_geofence` is still computed when coordinates exist).
- `modules/attendance/service.py`:
  - `get_punch_policy`:
    - sets `web_punch_allowed` from the helper on every branch;
    - gains `web_check_mode` (display/support; null when web isn't allowed);
    - for app `NoCheck`, returns `can_punch_from_app=true` with both `requires_*` false and no
      network check.
  - `_refusal_message("web_punch_not_allowed")` → "Clocking in from the browser isn't switched
    on for your location. Please use the mobile app, or contact HR."
  - `_assert_site_ready_for_app_punch`: app `NoCheck` needs nothing.
  - New `_assert_site_ready_for_web_punch(loc)`: when the result is web enabled with mode
    `Geofence`, it needs coordinates and a radius → otherwise 422 "This location needs
    coordinates, an allowed distance before web clock-in can be switched on." It runs after
    assignment whenever a PATCH touches `web_punch_enabled`, `web_punch_check_mode`, `lttd`,
    `lgtd` or `geo_fence_radius_mtrs` and the result is web on + Geofence.
  - INFO log when `web_punch_enabled` / `web_punch_check_mode` change (stdlib `logging`, `%s` style).
- `modules/attendance/schemas.py`:
  - the app mode Literal gains `NoCheck`;
  - `web_punch_check_mode: Literal["Geofence","NoCheck"] | None` goes on `WorkLocationIn` and
    `WorkLocationPatch`, and `web_punch_enabled: bool | None` on `WorkLocationPatch` only;
  - `WorkLocationOut` gains both;
  - `PunchPolicyOut.web_punch_allowed` default → `False`, plus `web_check_mode: str | None`.
- No RBAC change: work-location writes are already `UPDATE ATTENDANCE`.

## Frontend
- **231 (admin, Work Locations):**
  - the app "What to check" list gets No Check;
  - a new **Web clock-in** block, edit only, with the "Allow web clock-in" checkbox and a web
    mode radio: "Location only" / "No Check". It is usable only while app clock-in is switched on;
  - geofence inputs show when either the app or the web uses the geofence;
  - the list's "On · no network" warning is limited to Wi-Fi app modes;
  - add a Web column.
- **232 (employee):**
  - `canShowWebClock(policy)` = loading → false, failed → true, else `web_punch_allowed`;
  - the pill and `ClockCard` render no button when it is false.

## Tests (`backend/app/tests/modules/test_attendance.py`)
- Policy: every row of the flow table.
- Punches:
  - app NoCheck, web NoCheck;
  - web Geofence inside the fence, outside it, and with coarse accuracy;
  - web at a disabled site, with the box off, and with app clock-in OFF;
  - clock-out mirrors clock-in.
- Admin:
  - enabling an app NoCheck site bare;
  - web on + Geofence without coordinates → 422; web on + NoCheck without coordinates → 200;
  - `web_punch_check_mode="Wifi"` → 422;
  - another tenant's location → 404.

## Open decisions
None. Decided at schema approval:
- value `NoCheck` with label "No Check";
- the web box only takes effect while app clock-in is ON;
- the web mode defaults to `Geofence`.
