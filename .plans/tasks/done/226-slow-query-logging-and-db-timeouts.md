---
task: 226
title: Slow-query logging + DB timeouts
status: done
depends_on: [221]
---

# 226 — Slow-query logging + DB timeouts

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/backend/`.

## Scope
Today the only DB visibility is `SQL_ECHO`, which logs every statement or nothing. The guide
wraps each repository call in a timer. HRMS is sync SQLAlchemy with no repository layer, so do
it once at the engine level instead.

1. In `app/core/db.py` (or a new `app/core/db_instrumentation.py` imported there), attach
   `before_cursor_execute` / `after_cursor_execute` listeners to **both** `engine` and
   `async_engine.sync_engine`. Store the start time in `context._query_start`.
2. If elapsed ≥ `settings.slow_query_ms` (new setting, default `500`; `0` disables), log at
   WARNING on logger `app.db.slow_query`:
   `"slow query %.0fms: %s"`, with `extra={"duration_ms", "statement"}`. `statement` is the
   SQL **template** collapsed to one line and truncated to 500 chars. **Never log the bound
   parameters**: they carry employee names, phone numbers, salaries. The request ID and
   tenant arrive automatically via the 221/222/223 context filter.
3. If task 225 has landed (otherwise leave a TODO in 225's metrics module): observe every
   statement into `db_query_duration_seconds{engine="sync|async"}`. Use no statement label
   (unbounded).
4. **Statement timeout, decision-gated (default OFF).** New setting
   `db_statement_timeout_ms: int = 0`. When > 0, pass
   `connect_args={"options": f"-c statement_timeout={n}"}` to both engines. Ship it **off**:
   payroll calculation, leave year-close, employee import and the attendance assembler are
   legitimately long, and a global timeout would break them. Before turning it on in any
   environment, list the long jobs and either exempt them (`SET LOCAL statement_timeout = 0`
   in that job's session) or size the value above them. Record the decision in
   `docs/observability.md`.
5. Add `connect_timeout` (e.g. 5s) via `connect_args` so a down DB fails fast instead of
   hanging until the OS TCP timeout. This is safe to ship on.

**Not in scope:** `pg_stat_statements` / RDS Performance Insights and Postgres
`log_min_duration_statement`. Those are RDS parameter-group changes, owned by 227.

## Files
- `backend/app/core/db.py` (+ optional `backend/app/core/db_instrumentation.py`)
- `backend/app/core/config.py` (`slow_query_ms`, `db_statement_timeout_ms`)
- `backend/app/tests/modules/test_db_instrumentation.py` (new)
- `docs/logging.md` (slow-query line format) / `docs/observability.md`

## Acceptance criteria
- [x] With `SLOW_QUERY_MS=1`, a `SELECT pg_sleep(0.01)` emits one WARNING on `app.db.slow_query` containing the SQL template and `duration_ms`.
- [x] A query with a bound parameter (`WHERE mobile = :m`, `m="9999999999"`) logs the template and **not** the value (test asserts the value is absent from captured output).
- [x] Listeners fire for both the sync engine and the nhforms async engine.
- [x] `SLOW_QUERY_MS=0` emits nothing.
- [x] `DB_STATEMENT_TIMEOUT_MS` unset leaves Postgres' `statement_timeout` at its default (`SHOW statement_timeout` → `0`). Set to 50, `pg_sleep(0.2)` raises `QueryCanceled`.
- [x] `uv run pytest` green.

## As built (13-Oct-26)
- `backend/app/observability/db.py` (`instrument_engine`), attached in `app/core/db.py`
  to `engine` and `async_engine.sync_engine`. Start times are kept per connection in
  `conn.info` (a stack, popped on `handle_error`).
- Settings: `SLOW_QUERY_MS=500`, `DB_STATEMENT_TIMEOUT_MS=0` (off), `DB_CONNECT_TIMEOUT_S=5`.
- Tests are in `test_observability.py`.

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
