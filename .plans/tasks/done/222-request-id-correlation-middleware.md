---
task: 222
title: Request-ID correlation middleware (replaces log_requests)
status: done
depends_on: [221]
---

# 222 — Request-ID correlation middleware (replaces log_requests)

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/backend/`.

## Scope
Give every request an ID that appears on every log line written while serving it, in the
`X-Request-ID` response header, and in the one access-log line per request.

1. New **pure ASGI** middleware `app/middleware/request_context.py` (`RequestContextMiddleware`).
   Do not use `@app.middleware("http")`: pure ASGI avoids BaseHTTPMiddleware's streaming and
   contextvar quirks and sees the real final status.
   - Request ID: accept an incoming `X-Request-ID` only if it matches
     `^[A-Za-z0-9._-]{1,100}$`, otherwise generate `uuid4().hex`. (The ALB adds
     `X-Amzn-Trace-Id`. If present and valid, also bind it as `trace_id` so ALB access logs
     can be joined to app logs.)
   - `bind_log_context(request_id=…)` (task 221 helper) at the start; `clear_log_context()`
     in `finally`.
   - Wrap `send` to capture `status` from `http.response.start` and append
     `x-request-id` to the response headers.
   - On completion, log **one** line on logger `app.request`: message
     `"%s %s -> %s (%.1fms)"` (keep today's readable form for text mode) with
     `extra={"http_method", "http_route", "http_path", "status_code", "duration_ms"}`.
     `http_route` is the matched route template (`scope["route"].path` when set, otherwise
     `"unmatched"`). **Never** log the query string, headers, or body. Query strings carry
     ids/search terms, and headers carry the bearer token.
   - Level: ERROR for status ≥ 500, INFO otherwise. 4xx are expected outcomes in this app
     (expired tokens, RBAC 403s, validation), and the service layer already WARNs at the
     guard with the failing values. Logging them again at WARNING would double the noise.
   - Unhandled exception: `logger.exception("%s %s -> 500 (%.1fms) [unhandled]", …)` then
     re-raise (same behaviour as today's `log_requests`).
   - Skip the access line (but still set the header) for `/healthz`, `/livez`, `/readyz`,
     `/metrics`, so probes every few seconds don't flood the logs.
2. Delete the `log_requests` middleware from `app/main.py`. Register the new middleware so it
   is the **outermost** user middleware (added last, after `CORSMiddleware`). That way its
   timing covers CORS and activity logging, and the request ID is bound before
   `activity_logging_middleware` runs.
3. Add `"X-Request-ID"` to CORS `expose_headers` in `app/main.py`, next to `X-Encrypted` /
   `Content-Disposition`, so the frontend can show it in error toasts.
4. Turn off uvicorn's duplicate access log: add `--no-access-log` to the `CMD` in
   `backend/Dockerfile` and `backend/Dockerfile-Dev` (and `Dockerfile-Prod` when it exists).
5. Scheduler jobs: in `app/core/scheduler.py` `_run` / `_run_global`, bind
   `job=<job_name>` and `run_id=<uuid>` for the duration of each run, and clear afterwards.
   This is the guide's "background jobs bind a job/run ID" point.

**Not in scope:** tenant/user binding and the 500 handler (223), metrics counters (225,
which reuses this middleware's `http_route`/status/duration).

## Files
- `backend/app/middleware/request_context.py` (new)
- `backend/app/main.py`
- `backend/app/core/scheduler.py`
- `backend/Dockerfile`, `backend/Dockerfile-Dev`
- `backend/app/tests/modules/test_request_context.py` (new)
- `docs/logging.md`: "Request correlation" section (header contract, what is and isn't logged, probe paths skipped)

## Acceptance criteria
- [x] Every response (2xx, 4xx, 5xx, encrypted routes included) carries `X-Request-ID`.
- [x] A valid incoming `X-Request-ID: abc-123` is echoed back. An invalid one (`"a b"`, 101 chars, `\n`) is replaced by a generated ID.
- [x] A log line written inside a sync route handler (threadpool) carries the same `request_id` as the access line.
- [x] Exactly one access line per request (uvicorn access log off). None for `/healthz`.
- [x] Access line has the route template (`/api/v1/leave/requests/{request_id}`), not the concrete path, in `http_route`. An unknown path gives `unmatched`.
- [x] Query string and `Authorization` header value never appear in the log output (test asserts on captured output).
- [x] A scheduler job's log lines carry `job` and `run_id`.
- [x] `X-Request-ID` is readable cross-origin (in `expose_headers`).
- [x] `uv run pytest` green.

## As built (13-Oct-26)
- Lives in `backend/app/observability/middleware.py` (`ObservabilityMiddleware`), not
  `app/middleware/request_context.py`. Tests are in `test_observability.py`.
- Registered **inside** CORS (after the activity logger, before `CORSMiddleware`), not
  outermost, so the JSON 500 it sends (task 223) still gets CORS headers.
- Route template: FastAPI 0.139 keeps included routes with router-relative paths
  (`scope["route"].path == "/auth/me"`), so the template is rebuilt from the public
  `fastapi.routing.iter_route_contexts()` (full `/api/v1/auth/me`). Found during the
  container check and covered by a nested-router test.
- `uvicorn.access` is also silenced in `configure_logging()`: setting `propagate=True`
  had re-enabled it despite `--no-access-log`, which printed query strings. Found in the
  container check.
- Events are structlog-style: `http_request_completed` with `http_route`, `status_code`,
  `duration_ms`.

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
