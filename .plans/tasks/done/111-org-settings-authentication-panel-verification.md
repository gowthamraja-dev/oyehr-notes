---
task: 111
title: Verify Org Settings — Authentication panel save/load round-trip
status: done
depends_on: []
---

# 111 — Verify Org Settings — Authentication panel save/load round-trip

## Scope

Confirm the Organization Settings "Authentication" panel (SSO enforcement, 2FA toggle,
session timeout, IP restriction, minimum password length, symbol requirement) is wired
correctly end-to-end between frontend and backend:

- `hrms/frontend/src/dashboards/hrAdmin/OrgSettings.tsx` — `AuthenticationPanel`
  (loads via `getAuthPolicy()` on mount, saves via `saveAuthPolicy()` through the shared
  `registerSave` hook).
- `hrms/frontend/src/lib/api.ts` — `AuthPolicySettings` type, `getAuthPolicy` /
  `saveAuthPolicy` (both via `secureFetch`, matching the encrypted-route convention).
- `hrms/backend/app/modules/organizations/router.py` — `GET`/`PUT
  /api/v1/organizations/auth-policy`, gated `_READ`/`_UPDATE` (`SETTING` resource),
  mounted on the `EncryptedRoute` router.
- `hrms/backend/app/modules/organizations/service.py` — `get_auth_policy_settings` /
  `save_auth_policy_settings`, stored as one JSON blob on
  `care_delivery_program_parameter_details` (`parameter_master_id = 61`), scoped via
  `_require_cdp(db, principal)`.

No code changes were required — this was a verification pass, not new functionality.

Does NOT cover: the `get_session_timeout_minutes` / `get_auth_policy_for_cdp` login-time
consumers of this same param row, or the 2FA login-exchange flow itself — those are
already covered by `hrms/docs/authentication-session-flow.md` and existing auth tests.

## Files

No files changed.

## Acceptance criteria

- [x] Backend schema (`AuthPolicySettings` in `schemas.py`) matches the frontend type in
      `api.ts` field-for-field, including `min_password_length` being a `str` on both
      sides (frontend sends the full option label, e.g. `"8 characters"`, unparsed).
- [x] Frontend uses `secureFetch` (not raw `fetch`) for both GET and PUT, correct for an
      `EncryptedRoute`-mounted router.
- [x] Backend scopes both read and write through `_require_cdp(db, principal)` — no
      cross-tenant leak.
- [x] `uv run pytest app/tests/modules/test_organizations.py -k auth_policy` passes:
      `test_auth_policy_get_empty_then_upsert`, `test_auth_policy_scoped_to_own_cdp`,
      `test_auth_policy_unauthenticated` — all green.
- [x] Encrypted round-trip coverage exists generically for the `organizations` router in
      `app/tests/modules/test_encryption.py` (via `/organizations/profile`), so
      `/auth-policy` inherits it — no per-endpoint duplicate needed.
- [x] `npx tsc --noEmit` in `hrms/frontend/` reports no errors touching `OrgSettings.tsx`
      or `api.ts`.

Completed: 2026-09-18
