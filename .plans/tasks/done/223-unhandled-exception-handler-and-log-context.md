---
task: 223
title: Unhandled-exception handler, tenant/user and job log context
status: done
depends_on: [221, 222]
---

# 223 — Unhandled-exception handler, tenant/user and job log context

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/backend/`.

## Scope
1. **Consistent 500 body.** Today an unhandled exception reaches Starlette's
   `ServerErrorMiddleware`, which returns plain-text `Internal Server Error`. Add
   `@app.exception_handler(Exception)` in `app/main.py` returning
   `JSONResponse(500, {"detail": "Internal server error", "request_id": <rid>})` with the
   `X-Request-ID` header. Errors stay plaintext JSON even on `EncryptedRoute` routers (by
   design, per `docs/payload-encryption.md`). Never put `str(exc)` in the body.
2. **CORS on 500s.** `ServerErrorMiddleware` (where the `Exception` handler runs) sits
   *outside* `CORSMiddleware`, so the browser sees a 500 as a CORS error and the frontend
   can't read the body. Verify with a test, then fix. Preferred fix: in the 222 middleware,
   catch the exception, log it, and send the 500 JSON response itself *inside* the CORS
   layer, instead of relying on `ServerErrorMiddleware`. Alternative: add the CORS headers
   in the handler from `settings.cors_origins`. Pick one and record it in `docs/logging.md`.
3. **Exactly one traceback per failure.** After 1–2, an unhandled exception must produce a
   single `logger.exception` record (with `request_id`, `exc_type`), not one from the
   middleware plus another from uvicorn/`ServerErrorMiddleware`.
4. **Tenant/user on every log line.** In `app/api/deps.py:get_current_principal`, after the
   token validates, `bind_log_context(tenant_id=principal.tenant_id, user_id=<sub>,
   user_role_detail_id=…)`. Use **ids only**: no name, email, phone or mobile. This makes
   "grep one tenant's activity" (the existing `docs/logging.md` convention) work on every
   line, not just ones that remembered to interpolate `tenant_id`. The OTP-pending path
   (`scope == "otp_pending"`) binds `user_id` only.
5. **`HTTPException` / validation errors are unchanged.** FastAPI's own handlers keep
   rendering them. Do not log 4xx as errors (see 222's level rule).

**Not in scope:** metrics (225); alerting on 5xx (227).

## Files
- `backend/app/main.py`
- `backend/app/middleware/request_context.py` (from 222)
- `backend/app/api/deps.py`
- `backend/app/tests/modules/test_request_context.py` (extend) or `test_error_handling.py` (new)
- `docs/logging.md` ("Errors" subsection: 500 body contract, CORS fix chosen, context keys)

## Acceptance criteria
- [x] A test route that raises `RuntimeError("secret-ish detail")` returns 500 JSON `{"detail": "Internal server error", "request_id": …}`. The body does **not** contain the exception text.
- [x] That 500 response, requested with an allowed `Origin`, carries `Access-Control-Allow-Origin` (cross-origin readable).
- [x] Exactly one ERROR record with a traceback is emitted for it, carrying `request_id`.
- [x] An authenticated request's log lines carry `tenant_id` and `user_id`. An unauthenticated one has neither.
- [x] Lines from tenant A's request never carry tenant B's id under concurrent requests (context is cleared per request; test with two sequential requests on different tenants at minimum).
- [x] 401/403/422 responses are unchanged in body and status (existing `test_auth.py` / `test_authz.py` stay green).
- [x] `uv run pytest` green.

## As built (13-Oct-26)
- Took the "preferred fix": the 500 is sent by `ObservabilityMiddleware` itself (inside
  CORS), so there's no `@app.exception_handler(Exception)`. One
  `http_request_unhandled_exception` record carries the traceback, and the exception isn't
  re-raised, so uvicorn doesn't log a second traceback.
- Context binding is `_bind_principal_to_logs` in `app/api/deps.py`, used by both
  `get_current_principal` and `get_current_principal_no_activity`. (OTP-pending tokens
  never reach those, since they're refused earlier.)
- Verified live: with Postgres stopped, a DB-backed endpoint returned
  `500 {"detail":"Internal server error","request_id":"drill-500"}` with
  `access-control-allow-origin`, and exactly one traceback line was logged.

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
