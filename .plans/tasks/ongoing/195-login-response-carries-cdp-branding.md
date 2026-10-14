---
task: 195
title: Login responses (and /auth/me) carry the CDP's branding
status: ongoing
depends_on: []
---

# 195 — Login responses (and /auth/me) carry the CDP's branding

## Why

The web app always knows its tenant before login (subdomain in the URL), so the login
page calls `GET /public/organization?subdomain=…` and paints the CDP's colours/logo
(`frontend/src/lib/api.ts:getOrganization` → `--brand-primary`/`--brand-secondary`).
The mobile app logs in **without** a subdomain (`employeeapp/src/screens/LoginScreen/LoginViewModel.js`,
backend `auth/service.py:authenticate_without_subdomain`), so it only learns the tenant
from the login response — today that response carries `subdomain` and nothing else.

Reusing `GET /public/organization` after login would work but is worse:

- an extra round trip on every login (and on the OTP screen, before a session exists);
- `TokenResponse.subdomain` comes from `resolve_primary_host`, which returns **`None`**
  for a CDP with no active `organization_domain_mappings` row — then the client has no
  key to call `/public/organization` with at all, even though the CDP id is known.

So: build the branding **from the CDP id** server-side and embed it in the responses
that already resolve the CDP.

## Scope

All code in `hrms/backend/` (top-level clone — user chose it on 2026-10-08, not workspace-2).

1. **Shared builder.** In `app/modules/public/service.py`, extract
   `build_branding(db, cdp_id) -> OrganizationBrandingOut` out of
   `get_organization_by_subdomain` (reuses `_logo_url`, `_favicon_url`, `_theme_colors`,
   `CdpTypeMaster` lookup). `get_organization_by_subdomain` becomes: resolve CDP from host
   → `build_branding` → wrap with `subdomain`. **No change to `/public/organization`'s
   response shape** (web depends on it).
2. **Schema.** In `app/modules/public/schemas.py` add `OrganizationBrandingOut`:
   `care_delivery_program_master_id: int`, `organization_name: str`,
   `description: str | None`, `org_type: str | None`, `logo_url: str | None`,
   `favicon_url: str | None`, `theme_primary_color: str | None`,
   `input_focus_color: str | None`, `theme_secondary_color: str | None`.
   Make `OrganizationPublicOut` = `OrganizationBrandingOut` + `subdomain: str`
   (subclass) so the two can't drift.
3. **Colour sanitising.** `care_delivery_program_parameter_details.parameter_value` is
   free text. In `_theme_colors` (one place, benefits web too) return only values matching
   `^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$` (trimmed); anything else → `None`
   + `logger.warning("Ignoring invalid theme colour %r for CDP %s param %s", …)`.
   React Native red-boxes in dev on an invalid colour string, so the API must never
   hand one out. Check the shared dev DB's existing values (param ids 51/52/57) first so
   this doesn't silently blank a CDP that stores e.g. `rgb(...)` — if one does, widen
   the regex or normalise instead.
4. **Embed in auth responses** (`app/modules/auth/schemas.py`): add
   `branding: OrganizationBrandingOut | None = None` to `TokenResponse`,
   `OtpChallengeResponse`, `PasswordResetRequiredResponse`. Populate it in
   `auth/service.py`:
   - `_mint_token` (used by `login` and `verify_otp`) and `select_role`'s `TokenResponse`;
   - `_start_otp_challenge` (so the code-entry screen can be branded);
   - the `PasswordResetRequiredResponse` branch in `login`.
   - **Not** `refresh_token` — it's called on a timer; keep it lean (`branding=None`).
   Branding is non-sensitive (already public), and these routes are `EncryptedRoute` anyway.
5. **`/auth/me`.** Add the same `branding` field to `CurrentUserOut` and fill it in
   `build_me`. The mobile app already calls `/auth/me` on every launch
   (`AuthManager.fetchSessionTimeoutMinutes`) — this gives it a free refresh when an admin
   changes the theme, with no new call.
6. Avoid `public` ↔ `auth` import cycles: `auth.service` imports `build_branding` from
   `public.service`; `public/router.py` already imports from `auth`, which is fine — keep
   `public/service.py` free of `auth` imports.

**Not in scope:** the web frontend consuming the new field (task 196 — until then the web
keeps working unchanged, since `/public/organization` is untouched and the new field is
additive). The React Native `employeeapp/` is **not** changed by us — its developer gets
a handoff note describing the `branding` contract instead.

## Files

- `backend/app/modules/public/service.py`, `backend/app/modules/public/schemas.py`
- `backend/app/modules/auth/schemas.py`, `backend/app/modules/auth/service.py`
- `backend/app/tests/modules/test_auth.py`, `backend/app/tests/modules/test_public.py`
- `.claude/skills/hrms-mobile-api-integration` (root + `workspace-2/hrms/.claude/skills/`):
  document the new `branding` field on login / verify-otp / select-role / me.

## Acceptance criteria

- [x] `/public/organization` response is byte-for-byte the same shape as before (existing `test_public.py` passes unchanged).
- [x] Subdomain-less `POST /auth/login` → `TokenResponse.branding` has the CDP's name, logo URL and theme colours.
- [x] `branding` is present even when the CDP has **no** active domain mapping (`subdomain` is `null`, `branding` is not).
- [x] 2FA tenant: `OtpChallengeResponse.branding` populated; `verify-otp`'s `TokenResponse.branding` populated.
- [x] First-login: `PasswordResetRequiredResponse.branding` populated.
- [x] `select-role` returns branding; `refresh` does not (field `null`).
- [x] `GET /auth/me` returns `branding` for the caller's tenant only — test with two CDPs that user A's `/me` never returns CDP B's branding.
- [x] Invalid stored colour (e.g. `"teal"`, `"#12"`) → field `null` + WARNING logged; valid `#RGB/#RRGGBB/#RRGGBBAA` passes through.
- [x] Encrypted round-trip test for login still passes with the larger payload.
- [x] `uv run pytest app/tests/modules/test_auth.py app/tests/modules/test_public.py` green.
