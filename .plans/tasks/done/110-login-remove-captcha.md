---
task: 110
title: Remove the arithmetic captcha from the login screen
status: ongoing
depends_on: []
---

# 110 — Remove the arithmetic captcha from the login screen

## Scope

The login page (`hrms/frontend/src/app/page.tsx`) has a purely client-side arithmetic
captcha ("a + b = ?") gating the sign-in form. It is generated with `Math.random()`,
never verified by the backend, and is one of the documented gaps in
`hrms/docs/authentication-session-flow.md` ("captcha is client-only"). Remove it
entirely — no replacement captcha, no backend captcha verification is in scope here.

Does NOT cover: login lockout, token revocation, refresh tokens, or any of the other
gaps listed alongside captcha in `authentication-session-flow.md` — those are separate,
unrelated concerns and this task must not touch them.

## Files

- `hrms/frontend/src/app/page.tsx` — remove:
  - `newCaptcha()` helper (page.tsx:10-12)
  - `captcha` / `captchaAns` state (page.tsx:24-25)
  - the captcha-check block at the top of `onSubmit` (page.tsx:131-136) that blocks
    submission and re-rolls the captcha on a wrong answer
  - `setCaptcha(newCaptcha())` / `setCaptchaAns("")` calls elsewhere: on mount
    (page.tsx:61), on submit failure (page.tsx:161-162), and in `backToLogin()`
    (page.tsx:206-207)
  - the captcha JSX block rendered between the password field and the error/submit
    button (page.tsx:451-467) — the `data-testid="login-captcha"` input and its
    surrounding `a + b = ?` display
- `hrms/docs/authentication-session-flow.md` — update the documented-gaps list to drop
  "captcha is client-only" (it no longer exists, client-only or otherwise).
- `hrms/CLAUDE.md` — the "Authentication & sessions" section's gap list also repeats
  "captcha is client-only"; update it to match.

## Acceptance criteria

- [ ] No references to `captcha` remain in `hrms/frontend/src/app/page.tsx`.
- [ ] Login form submits directly on Sign In with no captcha field, input, or check
      in the way — verified by loading `/` and signing in with valid credentials.
- [ ] `hrms/docs/authentication-session-flow.md` and `hrms/CLAUDE.md` no longer list
      captcha as a known gap.
- [ ] `uv run pytest` (backend, unaffected) and existing frontend build
      (`npm run build` or equivalent in `hrms/frontend/`) still pass — this is a
      frontend-only removal with no backend surface, so no new tests are required.
