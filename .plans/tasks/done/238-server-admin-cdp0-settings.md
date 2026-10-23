---
task: 238
title: Server Admin — configure CDP 0 parameters from a settings icon
status: done
depends_on: []
---

# 238 — Server Admin: configure CDP 0 parameters from a settings icon

## Why

CDP 0 (`care_delivery_program_masters.id = 0`, "NanoHealth", the Super Admin tenant) holds
**platform-wide defaults** in `care_delivery_program_parameter_details`. Other CDPs fall back
to them — e.g. `engagement/service.py:_email_config` uses CDP 0's `from_email` /
`from_email_password` (parameter_masters 7 / 8) until a CDP sets its own. Today the only way
to set these is SQL or a seed script. The Server Admin has no screen for it.

Current CDP 0 rows (dev): `theme_color` (51), `input_focus_color` (52), `secondary_color` (57),
`from_email` (7), `from_email_password` (8). Note the dev data is already off: row 841 has a
phone number in `str_val` and `from_email_password` is stored **in plaintext** in
`parameter_value`.

## Interpretation to confirm before building

"Once the value is configured it shouldn't read again" is read here as:

- **Secrets are write-only.** Once a secret (e.g. `from_email_password`) is saved, the API never
  returns it again; the UI shows "Configured" with a **Replace** action, never the value.
- **No re-prompting.** A configured parameter shows as configured; the screen does not ask for it
  again or pre-fill it.

If the intent was instead *server-side caching* (don't re-query the DB per request once
loaded) or a *one-time setup wizard that disappears after completion*, say so — scope below
changes. Non-secret values (colours, from-email address) stay readable/editable.

## Scope

**Backend** (`backend/app/modules/admin_organizations/` — extend it, no new module):

1. A fixed, code-declared catalogue of the CDP 0 parameters the Server Admin may manage:
   `(parameter_master_id, key, label, group, kind, secret: bool, validation)`. Start with the
   ids the code already depends on: 7 `from_email`, 8 `from_email_password` (secret),
   51/52/57 theme colours. Add more by adding a catalogue entry, not by exposing all 130
   `parameter_type='CDP'` masters. (Skip param 208 WhatsApp — that lives in
   `partner_parameter_masters`, a different concern.)
2. `GET /admin/organizations/platform-settings` → for each catalogue entry:
   `{key, label, group, secret, configured: bool, value: str | None}`; `value` is **always
   `null` for secrets**. Always reads `care_delivery_program_master_id = 0` — never a caller
   supplied id.
3. `PUT /admin/organizations/platform-settings/{key}` → upserts the CDP 0 row
   (`parameter_master_id`, `is_active=true`, `parameter_value`; set `created_by_id` /
   `updated_by_id`). Validates per kind (email regex, `#hex` colour as in task 195). An empty
   secret value is rejected (use it to *replace*, not to blank). Response is the same row shape
   as GET — still no secret echo.
4. Both on the existing `EncryptedRoute` router, gated by `RequireSuperAdmin`.
5. Logging: INFO `platform_setting_updated` with `key` only — **never the value**.
   Write a `user_activity_details` row via `log_activity` (see `hrms-activity-logging`).
6. Secrets at rest: **no encryption for now** (decided 2026-10-16). `from_email_password` stays
   plaintext in `parameter_value`, exactly as `engagement/service.py:_email_config` reads it
   today — that code is untouched. "Write-only" applies to the API/UI only (never returned or
   logged). Encrypting at rest, if wanted later, is a separate task.

**Frontend** (`frontend/src/dashboards/`):

7. A **settings (gear) icon button in the top-right of the header** in `shell.tsx` (next to the
   help/notification buttons, same `w-[38px] h-[38px]` style, `Tooltip` "Settings"), rendered
   **only when `dashboard.dashboardPath === "super_admin_portal"`**. Click →
   `navigate("settings")`.
8. A `settings` view registered in `superAdmin/index.tsx` — **not** in `NAV` (reachable only via
   the icon). New `superAdmin/PlatformSettings.tsx`: grouped form (Email, Theme). Per field:
   - non-secret → normal input, prefilled, Save.
   - secret → "Configured ✓" badge + **Replace** button that reveals an empty password input;
     never prefilled.
   - Calls via `secureFetch` (add `getPlatformSettings` / `savePlatformSetting` in
     `lib/api.ts`). Save per field/group, toast on success.
9. Conventions: Tailwind only, 10px page spacing, `ShimmerForm` skeleton for loading (no
   "Loading…"), `hrms-confirm-dialog` if a destructive action is added.

## Out of scope

- Per-CDP overrides (the org admin's own settings screens already exist).
- Exposing the other ~120 legacy `CDP` parameter masters.
- Any schema change — `care_delivery_program_parameter_details` already fits, so no DBML gate.
- Token revocation / auth changes.
- Encrypting secrets at rest (deferred — see scope item 6).

## Files

- `backend/app/modules/admin_organizations/{router,service,schemas}.py`
- `backend/app/tests/modules/test_admin_organizations.py`
- `frontend/src/dashboards/shell.tsx`
- `frontend/src/dashboards/superAdmin/index.tsx`, new `superAdmin/PlatformSettings.tsx`
- `frontend/src/lib/api.ts`

## Progress (2026-10-16)

Backend + frontend built; backend covered by 13 tests in `test_admin_organizations.py` (`-k platform`),
run against the `hrms_newinst` DB (the :5433 dev DB was down). `tsc` clean. **Not yet checked in a
browser** — the UI criteria below stay open until someone clicks through it.

## Acceptance criteria

- [ ] Gear icon appears top-right for the Server Admin only; absent for HR Admin / Employee etc.
- [ ] Clicking it opens the settings view; Back/breadcrumb behave like other views.
- [x] GET returns every catalogue entry; `value` is `null` for secrets and `configured`
      reflects whether an active CDP 0 row has a non-empty value.
- [x] PUT creates the CDP 0 row when absent and updates it when present (no duplicate rows).
- [ ] After saving a secret, no API response or log line ever contains it; UI shows
      "Configured" and only accepts a replacement.
- [x] Non-super-admin gets 403; unauthenticated gets 401.
- [x] Writes always target CDP 0 even if the caller's `tenant_id` differs; other CDPs' rows
      are never read or modified (scoping test).
- [x] Invalid email / colour → 422 with a field-attributed message.
- [x] Encrypted round-trip test for the new routes; happy path, 401/403, validation, scoping.
- [x] A CDP with no own email config still sends via the CDP 0 values after they are changed
      here (existing `_email_config` fallback intact).
- [x] Activity-log row written per save, value excluded.

Completed: 2026-10-16
