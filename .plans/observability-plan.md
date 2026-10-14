# Production logging & monitoring — plan (13-Oct-26)

Source: a generic guide, "Production Logging and Monitoring for FastAPI (Docker Compose +
PostgreSQL)", which recommends structlog, a pure-ASGI request middleware, Prometheus, Grafana,
Loki/Promtail and Alertmanager. This plan maps that guide onto what HRMS actually runs. Paths
are in `workspace-2/hrms/`, the active working copy per the root CLAUDE.md.

## Where HRMS is today

| Concern | Current state | File |
|---|---|---|
| App logging | stdlib `logging`, plain-text `%(asctime)s %(levelname)s %(name)s: %(message)s` to stdout **and** a rotating `logs/access.log` (in every environment) | `backend/app/main.py:_setup_logging` |
| Request log | `@app.middleware("http") log_requests`: one line per request (method, raw path, status, ms) and `logger.exception` on unhandled errors | `backend/app/main.py:69-91` |
| Duplicate access log | uvicorn's own access log is still on (`CMD uvicorn …` without `--no-access-log`), so every request is logged twice in two formats | `backend/Dockerfile`, `backend/Dockerfile-Dev` |
| Request correlation | none: no request ID, and log lines carry no tenant or user | — |
| Unhandled 500s | Starlette's `ServerErrorMiddleware` returns plain-text "Internal Server Error". It sits outside `CORSMiddleware`, so the browser reports the 500 as a CORS failure | `backend/app/main.py` |
| Health | one `GET /healthz` runs `SELECT 1`. k8s uses it for **both** liveness and readiness, so a DB blip restarts every pod | `backend/app/main.py:113`, `k8s/dev-hrms-backend.yaml:44-60` |
| Metrics | none. No `prometheus-client`, no pool or job metrics. Two 40+40 connection pools (sync + async) exist per process | `backend/app/core/db.py` |
| DB timing | `SQL_ECHO` logs every statement or nothing. No slow-query threshold, no `statement_timeout` | `backend/app/core/config.py:33` |
| Scheduler | APScheduler runs in-process and logs job failures with `logger.exception`. No metrics, and jobs carry no run ID | `backend/app/core/scheduler.py` |
| Deploy targets | dev = k8s (`k8s/dev-hrms-backend.yaml`, `bitbucket-pipelines.yml`, `SECRETS_PROVIDER=k8s`). prod = ECS Fargate + ALB + RDS + Amplify (`docs/deployment-aws.md`, "Logs → CloudWatch"). Infra is **not provisioned yet**. `backend/Dockerfile-Prod` is cited in `docs/secrets-config.md` but is not on this branch | — |

## What the guide says vs. what we do

| Guide | Decision for HRMS | Why |
|---|---|---|
| structlog | **Adopted (user decision, 13-Oct-26)**, rendering through stdlib handlers (`ProcessorFormatter`), so it stays one pipeline and existing `%s` call sites keep working. CLAUDE.md and `docs/logging.md` were updated | The first draft of this plan said stdlib-only, because of the earlier Loguru revert; the user chose to follow the guide |
| Pure-ASGI request middleware, request ID | **Adopted** (task 222) | Directly fills the correlation gap |
| Catch-all exception handler | **Adopted, extended** (task 223): also fixes missing CORS headers on 500s | |
| `/health/live` + `/health/ready` | **Adopted** (task 224) as `/livez` + `/readyz`. `/healthz` stays as an alias | Fixes the liveness probe that restarts pods on a DB blip |
| `prometheus-client` `/metrics` | **Adopted, but on a separate port**, never the ALB-facing one (task 225) | The ALB forwards every path on the API port to the internet, so `/metrics` there would be public |
| DB timing wrapper | **Adapted** (task 226) to SQLAlchemy cursor events on both engines, rather than wrapping each repository call | HRMS is sync and has no repository layer to wrap |
| Docker Compose Prometheus/Loki/Promtail/Grafana/Alertmanager, postgres-exporter | **Built as a local stack** (`monitoring/compose.yaml`, Alloy instead of the deprecated Promtail; user decision) to verify connectivity end to end. **Not adopted for prod.** Replaced by CloudWatch Logs + Logs Insights + CloudWatch alarms + RDS Performance Insights (task 227). Amazon Managed Prometheus/Grafana is an optional add-on | Prod is Fargate: Promtail needs the Docker socket, and Fargate gives no host access. Loki and Prometheus need persistent disks (Fargate disks are ephemeral). RDS already exposes the postgres-exporter metrics. Workspace-2's `docker-compose.yml` is fully commented out |
| Docker `local` log driver rotation | **N/A in prod** (awslogs driver). Task 221 drops `logs/access.log` outside development | The Fargate disk is ephemeral and runs N replicas, which breaks the "Stateless, ephemeral containers" rule |
| Container hardening (`read_only`, `cap_drop`, non-root) | **Out of scope here.** It belongs to the (missing) `Dockerfile-Prod` and ECS task-definition work | Not a logging concern. Note that `read_only` would break the dev `logs/` and `.crypto_key.pem` writes |

## Task split

| # | Task | Depends |
|---|---|---|
| 221 | Stdlib JSON log formatter + logging setup module | — |
| 222 | Request-ID correlation middleware (replaces `log_requests`) | 221 |
| 223 | Unhandled-exception handler, tenant/user and job log context | 221, 222 |
| 224 | Split health probes `/livez` / `/readyz` | — |
| 225 | Prometheus metrics on a private port | 222 |
| 226 | Slow-query logging + DB timeouts | 221 |
| 227 | Prod log shipping, dashboards & alarms (CloudWatch) + `docs/observability.md` | 221–226 |

Rollout order follows the guide's own advice: first JSON logs, request IDs and health
(221–224), then metrics (225–226), then shipping and alerting (227).
