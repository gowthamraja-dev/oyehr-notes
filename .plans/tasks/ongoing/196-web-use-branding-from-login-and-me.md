---
task: 196
title: Web — take CDP branding from login / me instead of a second /public/organization call
status: ongoing
depends_on: [195]
---

# 196 — Web — take CDP branding from login / me instead of a second /public/organization call

## Why

The web already supports subdomain-less login on shared hosts (`hrms-dev.nextenti.ai`,
localhost — `NEXT_PUBLIC_SHARED_HOSTS`). Today it gets branding by **two** round trips:

- `frontend/src/app/page.tsx` `onSubmit`: after `login()` resolves a subdomain it fires
  `getOrganization(result.subdomain)` to paint colours/logo — and if the CDP has no
  active domain mapping (`result.subdomain === null`) the page stays unbranded.
- `frontend/src/contexts/auth-context.tsx` (initial load + `refreshOrg`) and
  `frontend/src/app/roles/page.tsx`: call `getOrganization(sub)` next to `getMe()` on
  every authenticated page load, where `sub` is guessed from URL → tab → localStorage.
  On a shared host with a cleared cache, `sub` is empty and the dashboard falls back to
  the generic "NanoHealth" brand even though the session knows its CDP.

After task 195, `POST /auth/login`, `/auth/verify-otp`, `/auth/select-role` and
`GET /auth/me` all return `branding` (the same fields as `/public/organization` minus
`subdomain`), so the client can use it directly.

## Scope

All code in `hrms/frontend/` (top-level clone, same as task 195).

1. **Types** (`src/lib/api.ts`): add `OrganizationBranding` (=`OrganizationPublic`
   without `subdomain`; make `OrganizationPublic = OrganizationBranding & { subdomain: string }`).
   Add `branding: OrganizationBranding | null` to `LoginRawResponse`, every `LoginResult`
   variant and `Me`. (`verifyOtp` / `selectRole` left as-is when built: the OTP screen is
   already branded from the challenge response, and `AuthProvider` only mounts on
   `/dashboard`, where it reads `/auth/me` — nothing would consume it.)
2. **`applyOrgTheme`** accepts `OrganizationBranding & { subdomain?: string | null }`.
   It writes `THEME_CACHE_KEY` only when a subdomain is known (the pre-hydration script in
   `app/layout.tsx` keys on subdomain) — otherwise applies the CSS vars and skips caching.
3. **Login page** (`app/page.tsx`): on a login / verify-otp response that carries
   `branding`, `setOrg` + `applyOrgTheme` from it — remove the follow-up
   `getOrganization(result.subdomain)` call. The **pre-login** `getOrganization(effectiveSub)`
   on mount stays (there's no session yet; that's what the public endpoint is for).
4. **Auth context** (`contexts/auth-context.tsx`): derive `org` from `getMe().branding`
   (plus the tab/cached subdomain for the `subdomain` field) instead of a parallel
   `getOrganization(sub)`. `refreshOrg` (used after Org Settings saves the theme) re-reads
   `/auth/me`. Keep a `getOrganization` fallback only if `me.branding` is null (old backend).
5. **Roles page** (`app/roles/page.tsx`): use `branding` from `/auth/me` (or the stored
   login result) instead of `getOrganization(sub)`.
6. Leave `dashboards/hrAdmin/OrgSettings.tsx`'s own `getOrganization` call alone unless
   it's trivially replaceable — it reads its own org for the settings form.

**Not in scope:** backend (task 195); mobile app (handled by its developer from the
handoff note); any visual redesign of the login page.

## Files

- `frontend/src/lib/api.ts`
- `frontend/src/app/page.tsx`, `frontend/src/app/roles/page.tsx`
- `frontend/src/contexts/auth-context.tsx`

## Acceptance criteria

- [ ] Shared host, fresh browser (no localStorage): subdomain-less login → login page, roles page and dashboard all show the CDP's colours + logo, with **no** `/public/organization` request after the login POST (check Network tab).
- [ ] CDP with no active domain mapping: still branded after login (previously generic).
- [ ] 2FA tenant: OTP screen branded from the challenge response; dashboard branded after verify.
- [ ] Per-tenant host (`acme.…`): unchanged behaviour, pre-login branding still from `/public/organization`, no flash of default colours on reload (layout.tsx cache still written).
- [ ] Changing theme colours in Org Settings → `refreshOrg` repaints without a reload.
- [x] `npm run build` passes and `tsc --noEmit` is clean. `eslint` on the 4 changed files reports the same 4 pre-existing `react-hooks/set-state-in-effect` errors as before the change, none new.
