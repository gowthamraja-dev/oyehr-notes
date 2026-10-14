# Attendance API — mobile client implementation guide

**Audience:** Android / iOS engineers building the punch screen.
**Backend status:** live on dev. Everything below except `GET /me/punch-policy` is built, tested and verified over real HTTP.

Base URL (dev): `https://hrms-dev.nextenti.ai`
All paths below are relative to `/api/v1`.

---

## 1. Things to know before writing any code

**Payload encryption is optional — skip it.** The attendance router supports a hybrid RSA+AES envelope, but it is opt-in: it only engages when the request carries an `X-Enc-Key` header. Send plain JSON over HTTPS and everything works. (If you ever do want it: `GET /api/v1/public/crypto-key` returns an SPKI PEM; RSA-OAEP/SHA-256 wrap a per-request AES-256-GCM key into `X-Enc-Key`, send the body as `{iv, ct}` base64. Error responses always come back in plaintext regardless.)

**One live session per user.** The server stores the current session id on the user row and refuses any token that isn't it. Logging in on mobile signs the same person out of the web, and vice versa. A `401` means *the session was replaced or expired* — drop the token and return to the login screen. Don't retry.

**Tenant comes from the JWT**, not from the host. Only login needs to know the organization.

**The server is the only judge.** Nothing the app checks locally changes a verdict — the backend re-reads the site's configuration on every punch. Local checks are for giving the user a better message sooner, never for deciding.

---

## 2. Login

```
POST /auth/login
{ "login_id": "someone@nanohealth.in", "password": "...", "subdomain": "acme" }
```

`login_id` accepts email, mobile, or employee id. `subdomain` may be omitted to auto-resolve, but only when that login matches exactly one organization — otherwise you get `409`. Send it explicitly if the app knows it.

Two possible successes:

| Response | Meaning |
|---|---|
| `{ "otp_required": false, "access_token": "...", "tenant_id": 1, "subdomain": "acme", ... }` | Done — store the token. |
| `{ "otp_required": true, "challenge_token": "...", "expires_in": 300, "masked_email": "ad***@x.com" }` | Org has 2FA. Show a code entry screen, then `POST /auth/verify-otp` with `challenge_token` + code. |

The challenge token is rejected by every other endpoint, so don't store it as a session.

All later calls: `Authorization: Bearer <access_token>`.

---

## 3. Clocking in and out

```
POST /attendance/me/clock-in
POST /attendance/me/clock-out
```

Both take the **same body**. This is deliberate — an employee verified on the way in but not on the way out produces a half-day that's worse than no check at all.

```jsonc
{
  "punch_source": "Mobile",      // REQUIRED. Defaults to "Web" — omit it and every punch is refused.
  "wifi_ssid": "NanoHealth-Corp",
  "wifi_bssid": "a4:2b:8c:11:02:df",
  "lttd": 12.9716,
  "lgtd": 77.5946,
  "accuracy_mtrs": 12.0,
  "location_error": null          // "denied" | "timeout" | "unavailable", when there's no fix
}
```

| Field | Type | Notes |
|---|---|---|
| `punch_source` | `"Mobile"` | The one field with no sensible default for you. Hardcode it. |
| `wifi_ssid` | string ≤120 | Exact name. Don't uppercase, don't trim, don't strip quotes beyond the platform's own. Matching is case-**sensitive**. |
| `wifi_bssid` | string ≤64 | Sent and stored, **not currently checked**. Send it anyway — it's what lets the check be tightened later without re-collecting a year of data. |
| `lttd` / `lgtd` | float | |
| `accuracy_mtrs` | float ≥0 | The fix's confidence radius. A ±3 km reading that lands inside a 200 m circle is refused because of this field. |
| `location_error` | enum or null | Why there's no fix. Doesn't change the verdict — both checks are required — but it's the only way to tell a declined permission from a real basement. Send it. |

Every field is optional to the schema so older builds don't hard-fail, but missing evidence counts as *unknown*, and unknown is refused at an enabled site. Never send a placeholder to fill a gap.

### Success — `200`

```jsonc
{
  "punch_id": 8412,
  "punch_at": "2026-09-23T09:04:11Z",
  "direction": "IN",
  "attendance_date": "2026-09-23",
  "state": "clocked_in",
  "verification_status": "Verified",   // always, for an app punch
  "is_within_geofence": true,
  "shift": { "name": "General", "start_time": "09:00:00", "end_time": "18:00:00", "time_zone": "Asia/Kolkata" },
  "late_by_minutes": 4
}
```

An app punch that reaches `200` is always `"Verified"`. `"Unverified"` exists only for web punches at sites that have not opted in — the mobile client never sees it. If a site is not set up, the punch is **refused**, not quietly recorded (see below); there is no state where the app is told "recorded but unchecked".

### Refused — `403`

```json
{ "detail": "You don't appear to be on your office Wi-Fi. Connect to it and try again — if the network was renamed recently, ask HR to update it." }
```

**Show `detail` verbatim.** Every message names the specific thing the user can fix; a generic "verification failed" turns each one into a support call, because the employee can't tell which of the two checks went wrong. The server deliberately does not say which network it expected — telling a refused punch the right answer defeats the check.

The nine messages you'll see. The last three are setup gaps — nothing the employee can fix, which is why each one names HR:

| Situation | What the user is told |
|---|---|
| Punched from a browser at an app-only site | Clocking in from the browser is switched off for your location. Please use the mobile app. |
| No SSID sent | Couldn't read your Wi-Fi network. Turn on Wi-Fi and location, then try again. |
| Wrong SSID | You don't appear to be on your office Wi-Fi… ask HR to update it. |
| No location fix | Couldn't confirm your location. Move near a window and try again. |
| Fix too coarse | Your location isn't precise enough to confirm. |
| Outside the fence | You appear to be away from your work location. |
| Employee has no work location | Your account isn't linked to a work location, so app clock-in can't be checked. Please contact HR. |
| Site hasn't switched app clock-in on | App clock-in isn't switched on for your work location yet. Please contact HR. |
| Site enabled but has no approved network | Your work location hasn't finished being set up for app clock-in. Please contact HR. |

A refusal writes no punch row, but it **is** recorded — the attempt lands in the audit log and the SSID the app reported is stored against the site. That's what lets HR see "312 punches are failing on a network called NanoHealth-5G" and fix a rename in one click. So a refused punch is not a dead end; don't suppress or batch them.

### Other statuses

| Code | Meaning | App behaviour |
|---|---|---|
| `409` | Already clocked in (message carries the time) | Refresh state from `/me/today`, show it |
| `401` | Session replaced or expired | Clear token, go to login |
| `422` | Malformed body | A bug in the app — log it |

### State

`GET /attendance/me/today` returns `state` (`not_started` / `clocked_in` / `clocked_out`), today's first in, last out, seconds worked and lateness. Call it on screen open so the button shows the right action.

---

## 4. Collecting the evidence

Two independent reads, both needed on every punch. Run them **in parallel** — serialising them doubles the worst-case wait.

### Location

- Request a fresh fix, not a cached one. A cached fix from this morning at home is exactly the failure mode the geofence exists to catch.
- **10 second timeout** (raised from 5 by decision on 2026-09-22 — 5 s was too tight indoors).
- On timeout or denial, still send the punch, with `location_error` set. Don't silently swallow it and don't fabricate coordinates.
- Send `accuracy_mtrs` from the platform's own estimate (Android: `Location.getAccuracy()`; iOS: `horizontalAccuracy`).

### Wi-Fi — Android

- Use `ConnectivityManager` + `NetworkCapabilities` → `WifiInfo`. `WifiManager.getConnectionInfo()` is deprecated from Android 12.
- Needs `ACCESS_FINE_LOCATION` **and location services actually switched on**, plus `NEARBY_WIFI_DEVICES` on API 33+.
- If those aren't satisfied the SSID comes back as `<unknown ssid>` and the BSSID as `02:00:00:00:00:00`. **Detect both sentinels and send `null`**, not the literal string — otherwise every punch reports a network name that will never match, and the refusal message points the user at the wrong problem.
- Strip the surrounding double quotes Android puts around the SSID.

### Wi-Fi — iOS

- `NEHotspotNetwork.fetchCurrent` (iOS 14+). It does **not** require `NEHotspotHelper`.
- Needs the **Access WiFi Information** entitlement, and location permission granted.
- **The trap:** iOS 14's approximate-location toggle breaks *both* checks at once — you get a coarse fix that fails the accuracy threshold, and no SSID. Detect it specifically by checking for `CLLocationAccuracyReduced` and show a dedicated message telling the user to turn Precise Location on for this app. If you don't, the user sees a generic "not precise enough" and has no idea which setting to change.

### Permissions

Ask at the attendance screen, with a sentence explaining why, not on first launch. A denied location permission on iOS is painful to recover from — the user has to go to Settings — so spend the explanation.

---

## 5. Suggested punch flow

```
on punch tap:
    disable button, show progress
    (in parallel) read Wi-Fi SSID/BSSID, request fresh location with 10s timeout
    if iOS and accuracy is reduced -> show "turn on Precise Location", offer to open Settings, stop
    POST clock-in / clock-out with whatever was gathered (nulls where it failed)
    200 -> update UI from response; if verification_status == "Verified", nothing special to show
    403 -> show detail verbatim, re-enable the button so they can retry after fixing it
    409 -> refresh from /me/today
    401 -> clear session, go to login
```

Do **not** queue refused punches for a silent retry. The user has to change something — move, connect to the office Wi-Fi, grant a permission — and a background retry hides that from them while quietly filling the audit log.

Do **not** cache the evidence between punches.

---

## 6. `GET /me/punch-policy` — call this before you draw the button

Built 2026-10-09. The app cannot decide this on its own: app clock-in is switched on **per work
location**, so two employees of the same organization get different answers.

Call it when the attendance screen opens.

```jsonc
{
  "can_punch_from_app": false,          // the only field your button depends on
  "reason": "site_not_enabled",         // null when the answer is yes
  "message": "App clock-in isn't switched on for your work location yet. Please contact HR.",
  "requires_wifi": false,               // false => do not ask for Wi-Fi permission here
  "requires_location": false,           // false => do not ask for location permission here
  "lttd": 17.4347197, "lgtd": 78.3672273,
  "geo_fence_radius_mtrs": 250,
  "max_location_accuracy_mtrs": 75,
  "work_location_name": "NH-HO",
  "web_punch_allowed": true
}
```

When the site is ready: `can_punch_from_app: true`, `reason` and `message` null, both
`requires_*` true, and `web_punch_allowed` false.

### The four reasons for a "no"

| `reason` | What it means | Who fixes it |
|---|---|---|
| `no_shift` | No shift is scheduled today | HR |
| `no_work_location` | The shift carries no work location | HR |
| `site_not_enabled` | The site has not switched app clock-in on | HR |
| `site_not_configured` | Enabled, but no approved network | HR |

These are the **same codes a refusal uses**, and `message` is the **same sentence**. Show
`message` and hide the button. A test asserts the two match, so the pre-check and the refusal
cannot drift apart and tell the employee two different stories.

### What else it buys you

- **Permissions.** `requires_wifi` and `requires_location` are false where app punching is off.
  Ask for nothing you cannot justify at that site.
- **A warning before sending.** The geofence values let you tell someone they are too far away
  without a round trip. The server still decides; this only makes the message faster.
- **The web button.** `web_punch_allowed` is false wherever app punching is on.

### It never returns the Wi-Fi names

That list is the answer key to the check. A test greps the response for the SSID to keep it out.

### Two rules

- **Call it on screen open, not once at login.** HR can switch a site on at any time, and with
  one session per user a token can outlive that by days.
- **If the call fails, show the button anyway** and let the server decide. Failing the other way
  turns a flaky network into "attendance is switched off".

---

## 7. Test checklist

Worth covering before the first internal build:

1. Right Wi-Fi, inside the fence → `200`, `Verified`.
2. Mobile data only, no Wi-Fi → `403`, "couldn't read your Wi-Fi".
3. Personal hotspot → `403`, "not on your office Wi-Fi".
4. Office Wi-Fi from across the street → `403`, "away from your work location".
5. Location permission denied → `403`, and the request carried `location_error: "denied"`.
6. iOS with Precise Location off → caught locally, before the request.
7. Android 13 without `NEARBY_WIFI_DEVICES` → SSID sent as `null`, not `<unknown ssid>`.
8. Punch at a site with app punching switched off → `200`, `Unverified`, no warning shown.
9. Clock in twice → `409`, handled without a crash.
10. Sign in on the web mid-session → next punch `401`, app returns to login.

---

## References

- Decision record and rationale: `hrms-mobile-attendance-summary.md`
- Full implementation plan: `hrms-mobile-attendance-implementation-plan.md`
- Server-side verification logic: `backend/app/services/punch_verification_service.py`

---

## 8. Testing it yourself

Two commands, from `C:\Drive\Nanohealth`:

```powershell
.\reset-punch-sandbox.ps1     # rebuild a clean sandbox (~1-2 min, mostly uvicorn booting)
.\test-punch-api.ps1          # drive all eleven calls
```

Reset before every run. The test asserts that app clock-in starts switched off with no
approved network, which is only true on a fresh sandbox.

### What the reset does, if you'd rather do it by hand

The `api` container points at the **shared hrms-dev database**, so punching against
`localhost:8000` writes real rows and really switches app clock-in on for a real work
location — which immediately starts refusing browser punches for everyone assigned to that
site. Use an isolated database instead. One-time setup:

```bash
# 1. an empty database in the LOCAL postgres container
docker compose exec -T db psql -U postgres -c "CREATE DATABASE hrms_sandbox"

# 2. schema. NOTE: `alembic upgrade head` does NOT work on an empty database — it fails on
#    `DROP INDEX ix_policy_mappings_cdp`, which doesn't exist yet. Build from the models:
docker compose run --rm -T -e DATABASE_URL="postgresql+psycopg://postgres:postgres@db:5432/hrms_sandbox" \
  api uv run python -c "import app.models; from app.core.db import Base, engine; Base.metadata.create_all(engine)"

# 3. one org, one admin-who-is-also-an-employee, one work location with a geofence
docker compose run --rm -T -e DATABASE_URL="postgresql+psycopg://postgres:postgres@db:5432/hrms_sandbox" \
  api uv run python -m scripts.seed_punch_sandbox

# 4. a second API on :8002 bound to the sandbox (the one on :8000 stays on hrms-dev)
docker compose run -d --name hrms-sandbox-api \
  -e DATABASE_URL="postgresql+psycopg://postgres:postgres@db:5432/hrms_sandbox" \
  -p 8002:8000 api uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

It takes uvicorn 1–2 minutes to finish importing before `:8002` answers.

Credentials it prints: org `sandbox`, `punchtest@example.com` / `Sandbox@123`, work location
`1` at 12.9716, 77.5946 with a 200 m radius. App clock-in is deliberately left **off** with no
approved network, so the first thing you test is the setup guard.

To start over: drop and recreate `hrms_sandbox`, then repeat steps 2–3.

### The script

`test-punch-api.ps1` (in the Nanohealth folder, beside this file) drives all eleven calls and
prints the exact payload sent and the body returned for each:

```powershell
.\test-punch-api.ps1
```

It asserts both the status code and the message text — a refusal with the right status and the
wrong sentence is still broken, because the employee can't tell which check to fix.

### The payloads, for Postman or curl

Log in, then reuse `access_token` as `Authorization: Bearer …`.

```bash
BASE=http://localhost:8002

# login
curl -s -X POST $BASE/api/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"login_id":"punchtest@example.com","password":"Sandbox@123","subdomain":"sandbox"}'

TOKEN=...   # access_token from above
AUTH="Authorization: Bearer $TOKEN"
JSON="Content-Type: application/json"

# enable before setup -> 422 naming what is missing
curl -s -X PATCH $BASE/api/v1/attendance/work-locations/1 -H "$AUTH" -H "$JSON" \
  -d '{"mobile_punch_enabled":true}'

# approve a network -> 201, then enable -> 200
curl -s -X POST $BASE/api/v1/attendance/work-locations/1/networks -H "$AUTH" -H "$JSON" \
  -d '{"ssid":"NanoHealth-Corp"}'
curl -s -X PATCH $BASE/api/v1/attendance/work-locations/1 -H "$AUTH" -H "$JSON" \
  -d '{"mobile_punch_enabled":true}'

# the payload the app sends -> 200, "Verified"
curl -s -X POST $BASE/api/v1/attendance/me/clock-in -H "$AUTH" -H "$JSON" -d '{
  "punch_source":"Mobile",
  "wifi_ssid":"NanoHealth-Corp",
  "wifi_bssid":"a4:2b:8c:11:02:df",
  "lttd":12.9716, "lgtd":77.5946, "accuracy_mtrs":12
}'

# wrong network -> 403
curl -s -X POST $BASE/api/v1/attendance/me/clock-out -H "$AUTH" -H "$JSON" \
  -d '{"punch_source":"Mobile","wifi_ssid":"Airtel-8821","lttd":12.9716,"lgtd":77.5946,"accuracy_mtrs":12}'

# ~1.1 km away -> 403
curl -s -X POST $BASE/api/v1/attendance/me/clock-out -H "$AUTH" -H "$JSON" \
  -d '{"punch_source":"Mobile","wifi_ssid":"NanoHealth-Corp","lttd":12.9816,"lgtd":77.5946,"accuracy_mtrs":12}'

# no punch_source at all: defaults to "Web" -> 403
curl -s -X POST $BASE/api/v1/attendance/me/clock-out -H "$AUTH" -H "$JSON" \
  -d '{"lttd":12.9716,"lgtd":77.5946}'

# location permission denied on the phone -> 403, cause recorded
curl -s -X POST $BASE/api/v1/attendance/me/clock-out -H "$AUTH" -H "$JSON" \
  -d '{"punch_source":"Mobile","wifi_ssid":"NanoHealth-Corp","location_error":"denied"}'

# what the refusals recorded, and one-click recovery
curl -s $BASE/api/v1/attendance/work-locations/1/networks -H "$AUTH"
curl -s -X POST $BASE/api/v1/attendance/work-locations/1/networks/2/approve -H "$AUTH"
```

No `X-Enc-Key` header anywhere — plain JSON, because the encryption layer is opt-in.

### Pointing it at hrms-dev instead

Possible, but it is not a dry run:

* it switches app clock-in **on** for the work location you pass, which starts refusing
  browser punches for everyone assigned there;
* it writes real punch and audit rows against your own employee record;
* it signs you out of the web app, since only one session per user is live.

If you do it, pick a work location nobody is assigned to and switch it back off afterwards:
`PATCH /attendance/work-locations/{id}` with `{"mobile_punch_enabled": false}`.
