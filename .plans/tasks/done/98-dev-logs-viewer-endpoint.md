---
task: 98
title: "Optional: dev-only /logs viewer endpoint"
status: done
depends_on: [94]
---

# 98 — Optional: dev-only `/logs` viewer endpoint

## Scope
**This task is the one exception that cannot be scoped to only shifts/leave/attendance** —
a log *viewer* endpoint is inherently app-wide infrastructure, not module logic. Flagged as
optional; confirm with the user before starting, since it touches `app/main.py` or
`app/api/router.py`, which the rest of this task set (94-97, 99) deliberately avoids.

If approved: a single `GET` endpoint, registered only when
`settings.environment == "development"`, that reads the last 200-300 lines of
`logs/app.log` and renders them as basic pre-formatted HTML. No auth beyond the existing
dev-environment gate — do not expose this in staging/production (no HTTPS-only secrets are
in play, but log lines from shifts/leave/attendance can contain employee ids and dates,
which is enough to keep this dev-gated per CLAUDE.md's tenant-data-sensitivity stance).

## Files
- New plain `APIRouter` (unauthenticated, matching the pattern CLAUDE.md describes for
  `branding`/`health`/`public/crypto-key` — never put this on `EncryptedRoute`), e.g.
  `backend/app/modules/devtools/router.py`, or, if the team prefers not to create a new
  module for one endpoint, a single route added directly in `app/main.py` guarded by
  `if settings.environment == "development":`.
- `backend/app/main.py` — wire the router/route, gated by environment (only shared-file
  touch this task set makes outside of task 94's `app/core/logging.py`).

## Implementation notes
- Read the file with a bounded tail (don't load the whole file into memory — `logs/app.log`
  is rotated at 20 MB but read defensively anyway): seek from the end or use a deque of the
  last 300 lines.
- Escape log content before embedding in HTML (basic `html.escape`) — log lines can contain
  user-influenced strings (names, form answers) and this endpoint has no auth, so treat the
  content as untrusted for XSS purposes even though it's dev-only.
- Handle "file doesn't exist yet" (no logger call has fired) as an empty-state HTML page,
  not a 500.

## Acceptance criteria
- [x] User has explicitly confirmed this task should proceed (see Scope note above).
- [x] `GET /logs` returns the last 300 lines as escaped `<pre>` HTML when
      `settings.environment == "development"` (the default) — verified via `TestClient`,
      including that raw `<script>` content in a log line renders as inert escaped text.
- [x] The route returns 404 (not just empty) when `ENVIRONMENT=production` — verified: the
      route is registered inside `if settings.environment == "development":` in
      `app/main.py`, so it's simply never added to the app under any other environment
      value, giving a real 404 rather than a gated 403/empty body.
- [x] No auth/token required to view — this is the same posture as `/healthz` and the
      `/public/*` router (unauthenticated by design), scoped down by only ever existing in
      dev.

## Implementation notes (final)
Added directly to `app/main.py` (per the task file's second Files option — no new
`app/modules/devtools` module, since it's a single route) inside `create_app()`, right
after `/healthz`:
- Reads `logs/app.log` with `collections.deque(f, maxlen=300)` — bounded memory regardless
  of file size, no full-file load.
- Missing-file case renders `<p>No log entries yet.</p>` instead of a 500.
- Content is `html.escape`d before being wrapped in `<pre>`.
- No changes to `app/api/router.py` — the route lives directly on `app`, same level as
  `/healthz`, not under the `/api/v1` prefix.

Completed: 2026-09-03
