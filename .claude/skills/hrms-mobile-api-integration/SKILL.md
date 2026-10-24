---
name: hrms-mobile-api-integration
description: >
  End-to-end guide for integrating a mobile app (iOS/Android/Flutter/React Native) against
  the HRMS backend, written for a mobile developer with zero backend context. Covers: base
  URL/versioning, the two independent security layers (JWT auth + RSA/AES payload
  encryption — encryption is NOT WebCrypto-only, mobile must reimplement it natively),
  multi-tenancy (subdomain is a plain string field, not real DNS), which routers are
  encrypted vs plain, login/2FA/role-selection flow, secure token storage, the
  employee-self-service ("/me/*") endpoint catalogue (clock-in/out, leave, payroll,
  reimbursements, shifts), error-response shape, and gotchas (single-session-per-device
  invalidation, app punches are verified per work location — ask /me/punch-policy first —
  the org-configurable idle-session-
  timeout and its POST /auth/refresh sliding-expiry endpoint). Use whenever
  building or reviewing the mobile app's backend integration, or onboarding a mobile
  developer new to this backend.
---

# HRMS Mobile API Integration — a guide for developers with no backend context

This is written for someone building the HRMS mobile app who has never touched this
FastAPI backend before. It explains the *mechanics* every screen/feature will need —
not the field-by-field shape of every endpoint (for that, see **§9 "Finding the exact
shape of an endpoint"**).

Read this top to bottom once; after that, use it as reference.

### When asked to write instructions for one specific endpoint

If invoked with a single endpoint (e.g. `attendance/me/this-month`) rather than a request
for the whole guide, don't just name the endpoint and point back at §2 ("apply the
encryption layer") — **inline the full concrete wiring** for that call, every time,
unless the endpoint is one of the plain/unencrypted exceptions in §3:

- State the exact header/body shape for *this* request: `X-Enc-Key` value, and whether a
  request body applies (GET → header only, no body; POST/PATCH/PUT → the `{"iv", "ct"}`
  envelope wrapping this endpoint's actual JSON payload).
- State the exact response shape: `X-Encrypted: 1` + `{"iv", "ct"}`, decrypted with the
  same AES key the client generated for the request — reproduce the RSA-OAEP / AES-GCM
  parameters from §2's contract table inline (2048-bit RSA-OAEP-SHA256/MGF1, AES-256-GCM
  with a 96-bit random IV and 128-bit tag appended to ciphertext) rather than citing them
  by section number.
- Call out the round-trip explicitly: fetch `/public/crypto-key` once → generate a fresh
  AES key per request → wrap it → encrypt the body (if any) → send → decrypt the response
  with that same AES key. A mobile developer implementing one endpoint should be able to
  build the request from this note alone, without flipping back to §2 to find the actual
  recipe.
- Still flag the endpoint-specific gotchas that apply (tenant scoping, error shape, any
  §10.1-style behavioral notes) — the inlined crypto recipe is additive, not a replacement
  for the rest of the endpoint note.

## 0. The shape of the system

- Backend: FastAPI, mounted at **`/api/v1/...`** (every path below is relative to that —
  the full login path is `/api/v1/auth/login`).
- Base URL: local dev is `http://localhost:8000`; ask your backend/DevOps team for the
  staging/prod URL (production is HTTPS behind a load balancer — see §2, HTTPS matters
  for more than just transport security).
- Auth: **stateless JWT bearer tokens**, minted at login, sent on every request after.
- On top of that, most endpoints ALSO encrypt the request/response **body** — a second,
  independent layer (§2). Don't confuse the two: a request can be perfectly
  authenticated (valid JWT) and still get rejected/garbled if you get the encryption
  envelope wrong, and vice versa.
- Multi-tenant: every organization ("CDP" in the backend's vocabulary) is identified by
  a **subdomain string** you pass explicitly in the login request body — see §4. This is
  NOT a real DNS subdomain the mobile app needs to resolve; it's just a text field.

## 1. Two independent layers — don't conflate them

| Layer | Purpose | Where it lives |
|---|---|---|
| **Authentication** (JWT) | Who is calling — attach `Authorization: Bearer <token>` | §5-§7 |
| **Payload encryption** (RSA+AES) | Confidentiality of the request/response *body*, on top of TLS | §2 |

Both apply to most endpoints simultaneously. A request to a protected+encrypted endpoint
needs: a valid bearer token AND a correctly-encrypted body AND the right headers.

## 2. Payload encryption — the part that trips up mobile developers

**The web frontend's implementation uses WebCrypto (`crypto.subtle`), which is a
browser-only API. It does not exist on iOS/Android/Flutter/React Native.** You are not
"reusing" the web client's crypto code — you're reimplementing the same *wire contract*
in your platform's native crypto library. That's normal and expected; the backend
doesn't care what language produced the bytes, only that they match the contract below.

### Why it exists
Defense-in-depth on top of TLS (and it gives real confidentiality in local dev, which
runs over plain `http://`). It is **not a replacement for TLS** — you still need HTTPS in
any non-local environment.

### The wire contract (implement this exactly)

1. Fetch the server's RSA public key once: `GET /api/v1/public/crypto-key` (plaintext,
   no auth needed) → `{"public_key": "<PEM SPKI>", "alg": "RSA-OAEP-256/A256GCM"}`. Cache
   it in memory for the app's lifetime.
2. For each request that has a body (or even a GET, to get an encrypted *response*):
   - Generate a random **AES-256** key (32 random bytes) per request — never reuse it.
   - **RSA-OAEP** encrypt that AES key with the cached public key: `MGF1(SHA-256)`,
     hash `SHA-256`, empty label, 2048-bit key. Base64-encode the result → send as the
     **`X-Enc-Key`** request header.
   - **AES-256-GCM** encrypt the JSON body: random 12-byte (96-bit) IV, no AAD. GCM
     produces ciphertext + a 16-byte (128-bit) auth tag — **append the tag to the
     ciphertext** (this is what WebCrypto and Python's `cryptography` both do by
     default; if your platform's AES-GCM API returns tag separately, concatenate it
     yourself: `ct = ciphertext || tag`).
     Body becomes `{"iv": base64(iv), "ct": base64(ciphertext_with_tag)}`.
     For a GET (no body), skip this — send no body at all, only the `X-Enc-Key` header.
3. Server decrypts, runs the endpoint, then encrypts the **response** with the *same*
   AES key you generated (it never sees your raw key — it unwrapped it via its RSA
   private key) and returns `{"iv": ..., "ct": ...}` with response header
   **`X-Encrypted: 1`**.
4. Decrypt the response body with your AES key + the returned `iv` the same way.

| Item | Exact value |
|---|---|
| Public key fetch | `GET /api/v1/public/crypto-key` (plaintext) |
| Request header | `X-Enc-Key: base64( RSA-OAEP-SHA256( raw 32-byte AES key ) )` |
| Request body | `{"iv": base64(12-byte nonce), "ct": base64(AES-256-GCM(json))}` — omit entirely for GET |
| Response header | `X-Encrypted: 1` (present only when the response body is encrypted) |
| Response body | `{"iv": base64(12-byte nonce), "ct": base64(AES-256-GCM(json))}` |
| RSA | 2048-bit, OAEP, MGF1(SHA-256), SHA-256 hash, empty label |
| AES | AES-256-GCM, 96-bit random IV, 128-bit tag appended to ciphertext |

### Critical gotchas

- **Errors are never encrypted, on any endpoint.** A 4xx/5xx response is always plain
  `{"detail": ...}` (or a Pydantic validation array — see §8), regardless of whether the
  endpoint is otherwise encrypted. **Detect encryption by status code + shape**: a `2xx`
  response with `{"iv": ..., "ct": ...}` (or the `X-Encrypted` header) is encrypted;
  anything else — including any non-2xx — is plain JSON. Don't try to decrypt an error
  body.
- **GET requests have no encrypted request body** — query parameters travel in the URL
  in plaintext. Never put sensitive data in a query string on this API.
- **"Tolerant mode"**: a request sent *without* `X-Enc-Key` is currently served in
  plaintext by most endpoints (handy while you're bringing up the integration —
  `curl`/Postman without any crypto still works against dev). Don't ship the mobile app
  without doing the encryption for real, even though it technically "works" without it
  today.
- **Key rotation in dev**: the dev server auto-generates its RSA key pair on container
  rebuild, so a cached public key can go stale (you'll get a decryption failure /
  `400`). Refetch `/public/crypto-key` once and retry if that happens. Production pins a
  stable key, so this is a dev-only annoyance.
- **HTTPS is still required.** This layer is defense-in-depth, not a TLS substitute —
  don't skip certificate validation in the app to "make it easier" to point at a
  self-signed dev box; use a real cert or accept the dev inconvenience.

### Per-platform starting points (you still have to wire this yourself)

- **iOS (Swift)**: `Security`/`CryptoKit` frameworks do both RSA-OAEP (via `SecKeyCreateEncryptedData`
  with `.rsaEncryptionOAEPSHA256`) and AES-GCM (`CryptoKit.AES.GCM`) natively — no third-party
  dependency needed.
- **Android (Kotlin/Java)**: `javax.crypto.Cipher` with `RSA/ECB/OAEPWithSHA-256AndMGF1Padding`
  for the key wrap, and `AES/GCM/NoPadding` for the body — both in the standard JDK/Android
  crypto provider, no extra library needed.
- **Flutter (Dart)**: the standard `crypto`/`pointycastle` or the `cryptography` pub package
  can do RSA-OAEP-SHA256 and AES-GCM; there isn't a single first-party package that does
  both out of the box, so expect to compose two.
- **React Native**: pure JS `crypto`/WebCrypto polyfills are typically not constant-time /
  not audited for RN's JS engine — prefer a native-module crypto library
  (e.g. `react-native-quick-crypto`) over a pure-JS one for this.

In every case: write a small round-trip unit test in your app (encrypt a known payload,
decrypt it, compare) before wiring it into real network calls — it's much easier to debug
in isolation than through a live 400 from the server.

## 3. Which endpoints are encrypted vs plain

**Default assumption: encrypted**, almost every module router in this backend uses
`EncryptedRoute`. The exceptions (always plain JSON, no crypto envelope) are:

- **Public/health**: `GET /api/v1/public/*` (org branding, the crypto-key endpoint
  itself), `GET /healthz`.
- **File uploads** (multipart form-data can't be JSON-encrypted): any upload endpoint —
  these are always on their own plain router even inside an otherwise-encrypted module.
- **CSV/file exports** (e.g. the attendance register export) — same reason, a browser/
  app file download can't unwrap `{iv, ct}`.
- **Reference/lookup data**: `master_data`, `geography` modules (non-sensitive, no PII).
- **Server-Sent-Events streams** (e.g. the WhatsApp engagement live-update stream) — a
  raw event stream, not a single JSON response, so it isn't wrapped.
- **The dynamic-forms package** (`/api/v1/forms/*`) and its one public shared-link flow —
  a separate subsystem the HRMS backend hosts, not authenticated the same way at all.
- **Device/hardware integration** (`iclock`) and the **Meta WhatsApp webhook** — both are
  server-to-server/device callbacks, not something the mobile app calls.

Everything you'd actually build a mobile screen against — auth, employees, attendance,
leave, payroll, reimbursements, shifts, roles, engagement — is encrypted. If you're ever
unsure about one specific endpoint, ask (or check the router file) rather than guessing;
sending a plain-JSON body to an endpoint expecting the envelope, or vice versa, fails
loudly rather than silently.

## 4. Multi-tenancy — the "subdomain" is just a string you know in advance

Don't build any DNS/subdomain-resolution logic into the mobile app. The backend takes a
literal `subdomain` string in the **login request body** and looks up which organization
it maps to (`organization_domain_mappings`) — it is never inferred from a Host header or
from where the app's traffic is coming from.

Practically: the mobile app needs to know, per install/per user, which organization
string to send. Options product usually picks from: a hardcoded value if the app is
single-tenant per build, a "choose your organization" field/screen, or a value baked into
an invite link/QR code the employee receives from HR. Get this answer from product/
backend before building the login screen — it decides the UX, not the API.

## 5. Login flow

```
POST /api/v1/auth/login
{ "subdomain": "acme", "login_id": "employee@acme.com", "password": "..." }
```

`login_id` accepts an email, a mobile number, or an employee id — same field, whichever
identifier the org uses. The response is **one of two shapes** — always check
`otp_required` first to know which you got:

**`otp_required: false`** (2FA not enabled for this org) — a real session, ready to use:
```json
{ "otp_required": false, "access_token": "<jwt>", "token_type": "bearer",
  "tenant_id": 19571, "user_role_detail_id": 4021, "role_master_id": 7 }
```

**`otp_required: true`** — password was correct, but you must complete a 2FA step before
you have a usable session:
```json
{ "otp_required": true, "challenge_token": "<short-lived jwt>",
  "expires_in": 600, "masked_email": "ad***@yopmail.com" }
```
The code is emailed to the **organization's shared contact address**, not the individual
user's own email (a deliberate current design choice — don't build a "check your own
inbox" message around it, tell the user to check with whoever holds that org inbox).
Exchange it:
```
POST /api/v1/auth/verify-otp   { "challenge_token": "...", "code": "123456" }  → same
  TokenResponse shape as the non-2FA case above
POST /api/v1/auth/resend-otp   { "challenge_token": "..." }  → { expires_in, masked_email }
  (rate-limited: 429 if you call it again within 60s of the last send)
```
5 wrong codes locks that specific challenge (`429`, must resend to get a fresh code) —
this does not lock the user's account, only that one OTP.

**Both `login` and `verify-otp` are on the encrypted router** — apply §2 to these calls
too, from the very first request.

### 5.1 Organization branding comes with the login response

`subdomain` may be omitted from the login body — the backend then resolves the
organization from `login_id` (409 if that login exists in more than one org). Either way,
every response that has resolved the org carries the org's resolved `subdomain` **and** a
`branding` object — `login` (all three shapes: session, OTP challenge,
`must_reset_password`), `verify-otp`, `select-role` and `GET /auth/me`. Only
`POST /auth/refresh` leaves it `null`.

```json
"branding": {
  "care_delivery_program_master_id": 12, "organization_name": "Acme Health",
  "description": "People & Payroll", "org_type": "Hospital",
  "logo_url": "https://…/logo.png", "favicon_url": "https://…/favicon.png",
  "theme_primary_color": "#1E4FA3", "input_focus_color": "#3B82F6",
  "theme_secondary_color": "#0EA5E9"
}
```

Use it instead of calling `GET /public/organization` after login — that endpoint needs a
subdomain, and `subdomain` is `null` for an org with no domain mapping, while `branding`
is always built from the org id. Every field except the id and name can be `null` (fall
back to the app's defaults per field); colours are always `#RGB`/`#RRGGBB`/`#RRGGBBAA` —
the backend drops anything else. Cache it like the subdomain (keep it across logout so the
next login screen is branded) and refresh it from the `/auth/me` call made on launch.

## 6. Storing the token, and keeping the session alive

The access token's `exp` is **org-configurable** — HR Admin sets it under Organization
Settings > Authentication > "Session timeout" (**1 minute – 8 hours (480 min)**, default
30 if never configured; see `hrms/docs/authentication-session-flow.md` "Idle timeout").
It is a real, **server-enforced** idle timeout, not a flat session cap and not something
your client can fake: while the app keeps calling refresh during genuine use, an active
user stays signed in indefinitely; only genuine inactivity — no *real* (non-refresh)
authenticated calls for the full configured window — stops refresh from succeeding, at
which point the user must either confirm they're still there or log in again from
scratch. The backend tracks `users.last_activity_at` itself and checks it inside
`/auth/refresh` — calling refresh in a loop from a script or a stuck client timer does
**not** keep a truly idle session alive; only real API activity does.

**`POST /auth/refresh`** mints a fresh token with a renewed `exp`, same session (it does
not rotate/invalidate the session the way logging in elsewhere does — see §7):
```
POST /api/v1/auth/refresh
Authorization: Bearer <current access_token>
Body: { "confirm_activity": false }

→ 200 { "access_token": "<new jwt>", "token_type": "bearer", "tenant_id": ..., "user_role_detail_id": ..., "role_master_id": ... }
```
Replace your stored token with the new `access_token` on success. This call is on the
encrypted router like everything else under `/auth` — apply §2.

**Two specific rejections to branch on**, both `401` with `{"detail": {"code": "...",
"message": "..."}}`:
- **`SESSION_TIMEOUT`** — no real activity within the configured window. Recoverable:
  show a "still there?" prompt, and if the user confirms, call refresh again with
  `{"confirm_activity": true}` — this bypasses the idle check (it counts as the activity
  itself) and succeeds as long as the session hasn't hit the hard cap below. Give the
  user a short window (e.g. 30-60s) to respond before treating it as a real timeout and
  logging out.
- **`SESSION_EXPIRED`** — the session has outlived the absolute hard cap (24h by
  default from when it began, `settings.refresh_hard_cap_hours`), **regardless of
  activity or `confirm_activity`**. Not recoverable — log out and send the user back to
  the login screen immediately, no "still there?" prompt.

Any other failure (network blip, or the session already ended for an unrelated reason —
logged out elsewhere, deactivated) — treat as best-effort: let the next real API call's
ordinary 401 handling take over, don't retry aggressively or show an error for a failed
refresh itself.

**No client-side activity tracking of any kind** — no per-touch, per-navigation, or
foreground/background tracking either, same as the web client. `users.
last_activity_at`, updated server-side by every real (non-refresh) authenticated call,
is the only activity signal. The client's whole job is one scheduled check: call
`/auth/refresh` (with `confirm_activity: false`) once, near the *current token's* `exp`
— `exp - min(30s, timeout / 2)` (a flat 30s buffer above the 1-minute floor; matches the
flow's own worked example: a 15-minute timeout schedules the check at the 14:30 mark).
On success, reschedule from the new token's `exp`; on `SESSION_TIMEOUT`, show the "still
there?" prompt with a countdown sized to the token's *actual remaining life* (`exp -
now` at that moment), not an arbitrary constant — if the user doesn't respond before the
token would have expired anyway, they'd be logged out by the next 401 regardless. Pause
the timer while backgrounded and recompute it from wall-clock on foreground-return (an
elapsed background nap may mean the check is already overdue) — this is about not
wasting a suspended timer, not about foreground state being an activity signal. Making a
real (non-refresh) API call at all — e.g. loading a screen's data — is itself what keeps
`last_activity_at` fresh server-side; the refresh timer's job is only to keep the
*credential* from expiring in between.

Still design the rest of the session UX around a refresh eventually being refused
(backgrounded for a long time, or the org's admin set a short timeout and the app was
never reopened) — `SESSION_TIMEOUT`/`SESSION_EXPIRED` always mean "the session is
ending," refresh only postpones that while there's real activity, it doesn't prevent
it forever.

Store the token in your platform's secure storage, not plain preferences/UserDefaults:
- iOS: **Keychain**.
- Android: **EncryptedSharedPreferences** or the **Android Keystore**-backed storage.
- Flutter: the `flutter_secure_storage` package (wraps Keychain/Keystore for you).
- React Native: `react-native-keychain` or Expo's `SecureStore`.

On every subsequent call, attach:
```
Authorization: Bearer <access_token>
```
in addition to the encryption headers from §2 where applicable.

## 7. One live session per user — a gotcha, not a bug

**Logging in anywhere immediately invalidates every other token that user was holding.**
This is real, current backend behavior: each login (or OTP-verify) writes a fresh session
id, and every token names the session it belongs to — an old token whose session id no
longer matches gets `401` with the message:
```json
{ "detail": "Session ended — signed in elsewhere. Please sign in again." }
```
Concretely: if the same employee logs into the web portal (or a second phone) while
already signed in on your app, the app's next API call will 401 with that exact message.
**Special-case this message** — show "You've been signed out because you signed in
elsewhere" rather than a generic "session expired, please log in again," which would be
misleading (nothing timed out; a newer login pushed this one out).

Logout (`POST /api/v1/auth/logout`) does the same thing server-side — it's a real
revocation of the current token, not just "the client forgets it." Still always clear
your locally stored token on logout regardless of whether the network call succeeds
(best-effort — don't block the UI on it).

Switching roles (§7.1 below) does **not** trigger this — it's the same session, a new
token for a different membership.

### 7.1 Multiple roles in one organization

A user can hold more than one role in the same org. After login:
```
GET  /api/v1/auth/roles         → { roles: [{ user_role_detail_id, role_master_id, role_name }] }
POST /api/v1/auth/select-role   { "user_role_detail_id": 4022 }  → same TokenResponse shape,
                                   scoped to that membership — replace your stored token with it
```
If there's exactly one role, most clients skip the picker screen and go straight in
(the token from `/login` is already scoped to *a* role — the caller's lowest-id active
membership — so a single-role user doesn't need this step at all).

## 8. Errors — status codes and shape

Never encrypted (see §2). Two shapes, both under the `detail` key:

- **A specific rejection** (401/403/404/409/422/423/429/...): `{"detail": "<message>"}` —
  the string is meant to be shown or at least logged, not parsed for meaning beyond
  matching it for the special case in §7.
- **A request-validation failure** (malformed/missing field, wrong type): `422` with
  FastAPI/Pydantic's default shape:
  ```json
  { "detail": [ { "loc": ["body", "password"], "msg": "Field required", "type": "missing" } ] }
  ```
  `detail` is a **list** here, not a string — check `isinstance` before assuming one
  shape.

Common status codes you'll see building the app: `401` (no/expired/superseded token —
send the user back to login), `403` (deactivated account, or a permission the caller's
role doesn't have), `404` (record not found / not in your tenant — cross-tenant lookups
404, they don't leak a 403), `409` (a conflicting state — e.g. clocking in while already
clocked in), `422` (validation), `423` (the record is locked, e.g. a payroll-closed
attendance day), `429` (rate-limited — OTP resend/attempts).

## 9. Finding the exact shape of an endpoint

This skill covers the *mechanics* that apply across the whole API. For the exact
request/response JSON of one specific endpoint, use the live OpenAPI docs rather than
guessing or relying on this doc going stale:
- **Swagger UI**: `GET /docs` (interactive, try-it-out — note this hits the *plain*
  request path even for encrypted endpoints, so "try it out" in the browser will fail
  auth/crypto the same way a naive mobile call would; it's still the best place to read
  the schema).
- **Raw OpenAPI JSON**: `GET /openapi.json`.

## 10. Employee self-service endpoints — the mobile app's actual surface

Everything below is prefixed `/api/v1` and requires a bearer token (§6); no additional
permission grant is needed beyond being the employee whose own record it is — these
`/me/*` routes are intentionally left open to any authenticated employee regardless of
their role's permission grid (a role with attendance/leave/payroll *read* denied still
sees their own data).

| Area | Endpoint | Notes |
|---|---|---|
| Profile | `GET /auth/me` | Session identity — user id, org name, role name. |
| Profile | `GET /employees/me`, `PATCH /employees/me` | Full employee record; self-edit. |
| Home | `GET /home/summary` | Landing-screen aggregate. |
| Home | `GET /home/holidays` | Org holiday calendar. |
| Attendance | `GET /attendance/me/punch-policy` | Ask before drawing the clock button: can this employee punch from the app here, and what to collect. See §10.1. |
| Attendance | `POST /attendance/me/clock-in` | See §10.1. |
| Attendance | `POST /attendance/me/clock-out` | See §10.1. |
| Attendance | `GET /attendance/me/today` | Today's punch state — poll this to render the clock-in/out button state. |
| Attendance | `GET /attendance/me/daily` | Paginated daily log. |
| Attendance | `GET /attendance/me/analytics` | Period (day/week/month) aggregate. |
| Attendance | `GET /attendance/me/this-month` | Month summary card. |
| Attendance | `GET /attendance/me/requests` | The caller's own attendance requests — regularizations and WFH (`?request_type=Regularization\|WFH`, `?status=`). Each row has `request_type`; a WFH row has `to_date` and `punch: null`. |
| Attendance | `GET /attendance/me/wfh-setup` | Before showing the work-from-home form: `{approver, remote_site_name}`. If either is null the request would be refused (no approver / no remote work location), so say so and disable submit. |
| Attendance | `POST /attendance/requests/wfh` | Raise a work-from-home request for a date range — `{from_date, to_date, reason}`, ≤ 31 days. Self-service. 422 when there is no approver or the organisation has no remote work location, or on overlap with another WFH request or leave. Approval moves those days' work location to the remote site — it has no attendance or payroll effect, and an Approved request can't be cancelled. |
| Attendance | `POST /attendance/requests/{id}/cancel` | Cancel the caller's own **Pending** request (regularization or WFH). |
| Shifts | `GET /shifts/me/{target_date}` | The employee's resolved shift for one date. |
| Leave | `GET /leave/me/requests` | The caller's own leave requests. |
| Leave | `GET /leave/me/balances` | Leave balances by type. |
| Leave | `GET /leave/me/policy` | The caller's resolved leave policy + per-type rules (half day, notice, document, accrual, carry forward). Only offer types with `covered: true` in the apply form; "no policy" is a 200 with `policy_id: null`, not an error. |
| Leave | `GET /leave/me/ledger` | The caller's leave history — every credit/debit (`txn_type`: Accrual, Availed, Reversal, CarryForward, Encashment, LapseExpiry, Adjustment), oldest first, with `leave_type_name`. |
| Leave | `POST /leave/requests`, `POST /leave/requests/preview` | Submit / preview a leave request (not `/me/`-prefixed, but scoped to the caller). |
| Leave | `POST /leave/requests/{id}/cancel` | Cancel the caller's own pending request. |
| Payroll | `GET /payroll/me/summary` | Payslip summary. |
| Payroll | `GET /payroll/me/tax-documents` | List. |
| Payroll | `GET /payroll/me/payslips/{id}/download-url` | Returns a URL, not the file bytes — fetch that URL separately (S3-backed, likely time-limited). |
| Reimbursements | `GET /reimbursements/me/summary` | — |
| Reimbursements | `POST /reimbursements/me/claims` | Submit a claim — this is where file-upload-style attachments would go through the shared image/file service (plain multipart router, not encrypted — see §3). |

### 10.1 Clock-in / clock-out specifics

**App punches are verified, per work location.** HR switches app clock-in on for each work
location and picks what it checks (the "check mode"): office Wi-Fi name, location (geofence +
accuracy), both, or **No Check**. A punch that fails a required check is **refused** —
`403` with a readable sentence in `detail`, and no punch is recorded. The work location is the
one on the employee's shift for today, so two employees of one organization can get different
answers. The app can't work this out itself; it asks.

**1. Before drawing the button — `GET /attendance/me/punch-policy`**

```
{ "can_punch_from_app": true, "reason": null, "message": null,
  "requires_wifi": true, "requires_location": true, "check_mode": "WifiAndGeofence",
  "lttd": 12.9716, "lgtd": 77.5946, "geo_fence_radius_mtrs": 200,
  "max_location_accuracy_mtrs": null, "work_location_name": "HQ",
  "web_punch_allowed": false, "web_check_mode": null }
```
- `can_punch_from_app` — `false` → disable/hide the button and show `message` (already written
  for the employee; `reason` is `no_shift` | `no_work_location` | `site_not_enabled` |
  `site_not_configured`, the same codes a refusal would use). **If the request itself fails,
  show the button anyway** — a flaky network must not read as "attendance is off"; the server
  still judges the punch.
- `requires_wifi` / `requires_location` — what to collect, and therefore which permissions to
  ask for. Both are `false` at a **No Check** site: collect nothing, punch at once — the punch
  is accepted and recorded as `Unverified`. (On Android, reading the Wi-Fi name needs fine
  location permission, so a site that requires Wi-Fi needs that permission too.)
- `check_mode` — `Wifi` | `Geofence` | `WifiAndGeofence` | `NoCheck`. For display/support only;
  branch on `requires_*`, which stay correct if a mode is ever added.
- `lttd`/`lgtd`/`geo_fence_radius_mtrs`/`max_location_accuracy_mtrs` — the site's fence, so the
  app can warn "you're too far away" before sending. The server still decides. The approved
  Wi-Fi names are never returned (telling a client what to report is telling it how to pass).
- `web_punch_allowed` / `web_check_mode` — for the **web** client only. Ignore them in the app.
- Refetch on screen focus: HR can change a site at any time. After a refusal, refetch too —
  the site may have changed since the screen loaded.

**2. The punch — `POST /attendance/me/clock-in` (and `clock-out`, same body)**

```
{ "punch_source": "Mobile",
  "wifi_ssid": "NanoHealth-Corp", "wifi_bssid": "aa:bb:cc:dd:ee:ff",
  "lttd": 12.9716, "lgtd": 77.5946, "accuracy_mtrs": 18.5, "location_error": null }
```
- Always send `"punch_source": "Mobile"` — `Web` is checked by different rules.
- Every evidence field is optional, but **missing evidence is "unknown", which a site that
  checks it treats as a refusal**, never a pass. Send what the policy asks for:
  `accuracy_mtrs` is the fix's accuracy radius (a coarse fix is refused at a location-checking
  site); `location_error` (`denied` | `timeout` | `unavailable`) says why there is no fix —
  leave it `null` when you didn't ask (No Check). `wifi_bssid` is stored, not checked.
- Send a **fresh** fix (seconds old), not the OS's last known position — indoors that can be a
  fix from hours ago, outside the building.
- Clock-out is verified exactly like clock-in.
- Refused → `403`, `detail` names the fix ("You don't appear to be on your office Wi-Fi…",
  "Couldn't confirm your location…", "App clock-in isn't switched on for your work location
  yet…"). Show it as-is; don't replace it with a generic failure.
- Response (`ClockActionOut`) includes `verification_status` (`Verified`, or `Unverified` at a
  No Check site), `is_within_geofence` (nullable — null when no location was sent or the site
  has no fence; recorded even where it isn't enforced), `late_by_minutes`, the resolved
  `shift`, and `state` (`"clocked_in"` / `"clocked_out"`) — use `state` to drive the button,
  don't infer it from timestamps yourself.
- **Only one open session per employee at a time.** Clocking in while already clocked in
  (anywhere — any device) returns `409 Conflict`. If an employee forgot to clock out
  days ago (including from a different device/session), clock-in stays blocked with that
  same 409 until the stale session is closed — the fix is a regularization request
  (`POST /attendance/requests` with punch=`Clock-out` and the missed time; see the
  attendance module for the exact shape), not a retry. If the app's clock-in button keeps
  409ing for no obvious reason, this is the first thing to check with backend/HR — it's
  not a client-side bug.
- `GET /attendance/me/today` gives you `state` (`not_started`/`clocked_in`/`clocked_out`),
  `active_in_at`/`first_in_at`/`last_out_at`, and `worked_seconds_so_far` — poll this on
  screen load to render the correct button/timer state rather than trying to derive it
  from local state alone (the source of truth is always the server).
  `worked_seconds_so_far` = the day's first clock-in → last clock-out, or → now while clocked
  in (tick +1/s from it only while `clocked_in`; always show the server value otherwise). A day
  whose LAST punch is a clock-in settles at 0 hours with `remarks = "Forgot to clock out"` —
  confirm before a same-day re-clock-in, and surface `remarks` from `/me/daily`.

## 11. Local/dev setup checklist

- Point the app at `http://localhost:8000` (or your machine's LAN IP if testing on a
  physical device — note §2's per-platform crypto still works fine over plain HTTP in
  dev; only the *web* client's WebCrypto path requires a secure context, that constraint
  doesn't apply to native mobile crypto libraries).
- `GET /healthz` — quick "is the backend up" check, unauthenticated, unencrypted.
- Ask backend for a seeded dev tenant's `subdomain` + a test login (`login_id`/password)
  — don't try to self-register; there's no public sign-up endpoint, accounts are
  provisioned by HR/admin.
- If you get a decrypt failure that wasn't happening before, refetch `/public/crypto-key`
  first (dev key rotates on container rebuild — see §2).
