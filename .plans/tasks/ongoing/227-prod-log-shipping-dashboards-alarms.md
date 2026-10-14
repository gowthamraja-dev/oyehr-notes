---
task: 227
title: Prod log shipping, dashboards & alarms (CloudWatch) + observability doc
status: ongoing
depends_on: [221, 222, 223, 224, 225, 226]
---

# 227 — Prod log shipping, dashboards & alarms (CloudWatch) + observability doc

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/` (docs, task
definition and IaC if/when it exists). **Decision-gated:** confirm the stack choice below with
whoever owns AWS before provisioning anything.

## Scope
The source guide's self-hosted Compose stack (Prometheus + Loki + Promtail + Grafana +
Alertmanager + postgres-exporter) does **not** fit HRMS prod:
- Fargate gives no host access, so Promtail can't mount `/var/lib/docker/containers` or the Docker socket.
- Loki, Prometheus and Grafana need persistent volumes, and Fargate disks are ephemeral.
- RDS already publishes what postgres-exporter would (connections, CPU, IOPS, replica lag,
  free storage), and Performance Insights replaces `pg_stat_statements` dashboards.

**Recommended (A): CloudWatch-native.**
1. **Logs:** ECS task definition `logConfiguration` = `awslogs`, group
   `/ecs/hrms-backend-<env>`, `awslogs-stream-prefix=api`. Set log-group retention explicitly
   (proposal: 30 days prod; the guide's 7 days is too short for HR incident/audit lookbacks.
   Confirm with the business). JSON lines from 221 are auto-parsed by Logs Insights.
2. **Saved Logs Insights queries** (commit the text in `docs/observability.md`):
   - by request ID: `fields @timestamp, level, logger, message | filter request_id = "<id>" | sort @timestamp`
   - errors: `filter level = "ERROR" | stats count() by logger, exc_type | sort count desc`
   - one tenant: `filter tenant_id = <id> | sort @timestamp desc`
   - slow endpoints: `filter logger = "app.request" | stats pct(duration_ms, 95) as p95, count() by http_route | sort p95 desc`
   - slow queries: `filter logger = "app.db.slow_query" | stats count(), max(duration_ms) by statement`
3. **Alarms → SNS topic `hrms-<env>-alerts`** (email/Slack subscription; test delivery end-to-end):
   - ALB `HTTPCode_Target_5XX_Count` / `RequestCount` > 5% for 10 min, **with** a minimum request count (the guide warns this is noisy at low traffic)
   - ALB `TargetResponseTime` p95 > 1s for 10 min
   - ALB `HealthyHostCount` < desired for 2 min (driven by `/readyz` from 224)
   - ECS service `CPUUtilization` / `MemoryUtilization` > 80% for 15 min; running task count < desired
   - RDS `DatabaseConnections` > 80% of `max_connections` (each task holds up to 2×(40+40) from `app/core/db.py`, so size this against the replica count), `FreeStorageSpace`, `CPUUtilization`
   - Log metric filter on `level = "ERROR"` count, and on scheduler failures (`logger = "app.core.scheduler" and level = "ERROR"`)
4. **RDS:** enable Performance Insights. Add `pg_stat_statements` to `shared_preload_libraries`
   in the parameter group (needs a reboot, so schedule it). Optionally set
   `log_min_duration_statement` (e.g. 1000ms) with RDS log export to CloudWatch. Note the
   guide's warning: query text in Postgres logs can contain literals, so restrict log-group access.
5. **Request tracing:** confirm ALB access logs (S3) are on, and that `trace_id`
   (`X-Amzn-Trace-Id`, bound in 222) lets an ALB log line be joined to app lines.
6. **Metrics endpoint (from 225):** decide one of:
   - (a) not scraped in prod; CloudWatch ALB/ECS/RDS metrics are enough to start. **Recommended first step.**
   - (b) ADOT collector sidecar in the task definition scraping `localhost:9100` → Amazon
     Managed Prometheus, viewed in Amazon Managed Grafana. Add when pool/scheduler metrics
     are needed in prod.
   - (c) CloudWatch agent Prometheus scraping → CloudWatch metrics.
7. **Dev k8s** (`k8s/dev-hrms-backend.yaml`): record what the cluster already collects
   (ask the Nextenti platform owner). If it runs Prometheus, add scrape annotations for
   port 9100. Don't stand up a stack just for dev.

**Option B (only if AWS-managed is rejected):** the guide's stack on a dedicated EC2/ECS-on-EC2
host with EBS volumes, Grafana Alloy instead of the deprecated Promtail, and auth in front of
Loki/Grafana. Much more to operate. Not recommended for this team size.

**Prerequisites/blockers to record:** infra isn't provisioned yet (no Terraform/CDK, no CI
deploy, per `docs/deployment-aws.md` "Not yet provisioned"). `backend/Dockerfile-Prod` is
cited in `docs/secrets-config.md` but not on this branch. This task produces the doc and the
task-definition/IaC snippets. Applying them happens when prod infra is built.

## Files
- `docs/observability.md` (new, or completed if 225 created it): architecture (logs → CloudWatch, metrics options, alarms), the field list from 221, request-ID contract (222), probe semantics (224), metrics catalogue (225), slow-query + timeout decision (226), saved queries, alarm table with thresholds and owners, retention table, runbook "how to investigate a 500 from a request ID"
- `docs/deployment-aws.md`: replace the bare "Logs → CloudWatch" with a Monitoring section linking `docs/observability.md`. Add `LOG_FORMAT=json`, `METRICS_ENABLED` to the env table
- Root `CLAUDE.md` "Cloud setup (AWS)" + "Logging" sections: link `docs/observability.md`
- Task-definition / IaC snippets (location per whatever IaC is chosen)

## Acceptance criteria
- [ ] Stack choice (A vs B, and metrics option a/b/c) confirmed by the AWS owner and recorded in `docs/observability.md`.
- [ ] `docs/observability.md` exists and covers every item in "Files" above.
- [ ] Log-group retention is set explicitly (not "never expire") and agreed.
- [ ] Each alarm in the table has a threshold, an SNS target, and has been test-fired once in staging (not prod), with delivery confirmed.
- [ ] Following the runbook in staging, a deliberately triggered 500 can be traced from the `request_id` in the response to its traceback in Logs Insights, with no secrets/PII in the line.
- [ ] Performance Insights on; `pg_stat_statements` enabled or explicitly deferred with a reason.

## Progress (13-Oct-26)
Done on `feature/gowtham_Observability`:
- `docs/observability.md` written: architecture, settings, probes, metrics catalogue,
  DB timing/timeout decision, saved Logs Insights queries, prod alarm list, security checklist.
  `docs/deployment-aws.md` has a Monitoring section plus the `LOG_FORMAT`/`METRICS_ENABLED` env rows.
- **Local stack** `monitoring/compose.yaml` (user asked for it): API + Postgres 18
  (`pg_stat_statements`) + postgres-exporter (`metrics_reader`/`pg_monitor`) + Prometheus
  (`monitoring/alerts.yml`, 7 rules mirroring the CloudWatch alarm list) + Alertmanager + Loki +
  Grafana Alloy + Grafana (provisioned datasources and an "HRMS API" dashboard).
  Verified end to end: all 6 Prometheus targets up; route-template series scraped from
  `api:9100`; logs searchable in Loki by `request_id`; Grafana → Prometheus/Loki/Alertmanager
  OK. Postgres-down drill: `/livez` 200, `/readyz` 503, JSON 500 with CORS, `PostgresDown`
  fired into Alertmanager, and recovery happened without restarting the API.

Still open (needs AWS infra / the AWS owner): stack decision sign-off, the awslogs log
group + retention, SNS alarms test-fired in staging, Performance Insights /
`pg_stat_statements` on RDS, `Dockerfile-Prod` with `LOG_FORMAT=json`.
