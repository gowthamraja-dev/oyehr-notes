---
task: 224
title: Split health probes /livez and /readyz
status: done
depends_on: []
---

# 224 — Split health probes /livez and /readyz

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/`.

## Scope
Today there is a single `GET /healthz` (`backend/app/main.py:113`) that runs `SELECT 1`, and
`k8s/dev-hrms-backend.yaml` points **both** `readinessProbe` and `livenessProbe` at it. If
the database is briefly unreachable, liveness fails and kubelet restarts every pod, which
turns a DB blip into a full outage. The same would happen with an ALB/ECS health check on it.

1. `GET /livez`: no I/O, returns `{"status": "ok"}`. Proves only that the process is serving.
2. `GET /readyz`: a bounded DB check. Run `SELECT 1` on the sync engine with a short timeout
   (`SET LOCAL statement_timeout = '2s'` inside the check transaction, or equivalent). Return
   `200 {"status": "ok", "database": "connected"}`, or **503**
   `{"status": "unavailable", "database": "error"}` on any exception. Log the exception at
   WARNING (not `exception`; the probe repeats every few seconds). Never put the error
   text in the body. Respect `pool_timeout=10` so the probe can't hang longer than the
   probe's own `timeoutSeconds`: use a dedicated tiny check with `connect_timeout` or run it
   via the existing pool and keep the probe timeout above 10s, and document which.
3. Keep `GET /healthz` as an alias of `/readyz` (same handler). `docs/secrets-config.md:47`
   and any external monitor rely on it.
4. All three stay plain (not `EncryptedRoute`), unauthenticated, `include_in_schema=False`,
   and are skipped by the request access log (222) and `activity_logging_middleware` (already
   skipped, since there's no bearer token).
5. Update `k8s/dev-hrms-backend.yaml`: `livenessProbe` → `/livez`, `readinessProbe` →
   `/readyz`. Keep the existing timings unless they are shorter than the readiness timeout.
6. `docs/deployment-aws.md`: ALB target-group health check = `/readyz`, ECS container health
   check (if any) = `/livez`.

**Not in scope:** checking S3/WhatsApp/other external dependencies. Readiness must not depend
on third parties whose outage the app can degrade around.

## Files
- `backend/app/main.py`
- `k8s/dev-hrms-backend.yaml`
- `docs/deployment-aws.md`
- `backend/app/tests/modules/test_public.py` (extend) or `test_health.py` (new)

## Acceptance criteria
- [x] `/livez` returns 200 without touching the DB (passes with the DB engine patched to raise).
- [x] `/readyz` and `/healthz` return 200 with a working DB, and 503 (body without error text) when the DB call raises.
- [x] None of the three appear in the request access log.
- [x] k8s manifest uses `/livez` for liveness and `/readyz` for readiness.
- [x] `uv run pytest` green.

## As built (13-Oct-26)
- `backend/app/observability/health.py` (plain router, `include_in_schema=False`).
  `/readyz` uses `get_db` + `SET LOCAL statement_timeout = '2s'`. `DB_CONNECT_TIMEOUT_S=5`
  (task 226) bounds connecting. k8s readiness got `timeoutSeconds: 3`.
- Tests are in `test_observability.py`.
- Verified live: DB stopped gave `/livez` 200 and `/readyz` 503; the API container's
  healthcheck uses `/livez`.

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
