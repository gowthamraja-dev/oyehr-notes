---
task: 225
title: Prometheus metrics on a private port
status: done
depends_on: [222]
---

# 225 — Prometheus metrics on a private port

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/backend/`.

## Scope
Expose request, DB-pool and scheduler metrics in Prometheus format. Prod scraping (ADOT
sidecar → Amazon Managed Prometheus, or not at all) is decided in 227. This task only makes
the numbers available, safely.

1. Add `prometheus-client` (`uv add prometheus-client`; pin via `uv.lock`). This is the one
   new runtime dependency in this plan. It is a metrics library, not a logging library, so it
   doesn't conflict with the stdlib-logging rule.
2. **Do not mount `/metrics` on the API port.** The ALB forwards every path on the API port,
   so it would be public (route labels and traffic shape leak). Instead, start
   `prometheus_client.start_http_server(settings.metrics_port)` from `lifespan` when
   `settings.metrics_enabled` is true. Settings: `metrics_enabled: bool = False`,
   `metrics_port: int = 9100`. The port is not in the ALB target group or the k8s Service.
   Scrapers reach it on the task/pod IP only.
   - Note in the doc: the image runs a **single** uvicorn worker today. If `--workers N` is
     ever added, switch to `prometheus_client` multiprocess mode (`PROMETHEUS_MULTIPROC_DIR`
     on a tmpfs), or the counters will be per-worker and wrong.
3. Request metrics, recorded in the 222 middleware (reuse its `http_route`, status,
   duration). Use bounded labels only:
   - `http_requests_total{method, route, status_code}` (Counter)
   - `http_request_duration_seconds{method, route}` (Histogram, buckets
     `.005,.01,.025,.05,.1,.25,.5,1,2.5,5,10`)
   - `http_requests_in_progress` (Gauge)
   Skip probe and metrics paths. `route` is the template or `"unmatched"`. **Never** label
   with tenant_id, user_id, request_id or raw path. Tenant cardinality grows with customers.
4. DB pool metrics: a custom collector reading `engine.pool` (sync) and
   `async_engine.sync_engine.pool` (nhforms): `db_pool_checked_out{pool}`,
   `db_pool_size{pool}`, `db_pool_overflow{pool}`. Pool exhaustion was already a real
   incident (see the comment in `app/core/db.py` about 25 parallel form-field requests).
5. Scheduler metrics in `app/core/scheduler.py`:
   `scheduler_job_runs_total{job, outcome="ok|error"}`,
   `scheduler_job_duration_seconds{job}`, `scheduler_job_last_success_timestamp{job}`. The
   last one lets 227 alert on "job hasn't succeeded in N hours".
6. Set `METRICS_ENABLED=true` in `backend/Dockerfile-Dev`, and add `containerPort: 9100`
   (named `metrics`) to `k8s/dev-hrms-backend.yaml`. Do **not** add it to the Service's
   NodePort.

**Not in scope:** DB query-duration histogram (226 adds it to this registry), Prometheus/
Grafana deployment and alert rules (227).

## Files
- `backend/pyproject.toml`, `backend/uv.lock`
- `backend/app/core/config.py` (`metrics_enabled`, `metrics_port`)
- `backend/app/core/metrics.py` (new: metric objects + pool collector + `start_metrics_server()`)
- `backend/app/middleware/request_context.py`, `backend/app/main.py` (lifespan), `backend/app/core/scheduler.py`
- `backend/Dockerfile-Dev`, `k8s/dev-hrms-backend.yaml`
- `backend/app/tests/modules/test_metrics.py` (new)
- `docs/observability.md` (new, metrics section; 227 completes it)

## Acceptance criteria
- [x] `GET /metrics` on the API port returns 404.
- [x] With `METRICS_ENABLED=true`, `curl :9100/metrics` shows `http_requests_total`, `http_request_duration_seconds_bucket`, `db_pool_checked_out{pool="sync"}` and `{pool="async"}`, and `scheduler_job_runs_total`.
- [x] After calling `/api/v1/leave/requests/5` and `/api/v1/leave/requests/6`, there is one series with `route="/api/v1/leave/requests/{request_id}"`, not two.
- [x] Probe paths do not increment `http_requests_total`.
- [x] No metric has a tenant/user/request-id label (test iterates the registry's label names).
- [x] With `METRICS_ENABLED` unset, no port is opened (tests and local dev unaffected).
- [x] `uv run pytest` green.

## As built (13-Oct-26)
- `backend/app/observability/metrics.py` (not `app/core/metrics.py`). `DbPoolCollector`
  defines `describe()` so registering it doesn't import `app.core.db` mid-import.
- Also `scheduler_job_last_success_timestamp_seconds` and `db_query_duration_seconds`
  (task 226). Default process metrics included.
- Verified live in `monitoring/compose.yaml`: Prometheus target `api:9100` up, route labels
  `/api/v1/...` templates, `:8180/metrics` returns 404.

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
