---
task: 221
title: structlog JSON logging + logging setup module
status: done
depends_on: []
---

# 221 — structlog JSON logging + logging setup module

Parent plan: `.plans/observability-plan.md`. Work in `workspace-2/hrms/backend/`, branch
`feature/gowtham_Observability`.

**Revised 13-Oct-26 (user decision):** use **structlog** as the source guide does, replacing
the old stdlib-only setup. The "no third-party logger" rule in CLAUDE.md / `docs/logging.md`
was updated to record the decision. The file name is kept for history.

## Scope
- New `app/observability/logging_config.py` `configure_logging()`, replacing
  `app/main.py:_setup_logging`. structlog `ProcessorFormatter` on stdlib handlers, so
  existing `logging.getLogger` + `%s` call sites, uvicorn, SQLAlchemy and nhforms all render
  through one pipeline. New code uses `structlog.get_logger(__name__)`.
- `LOG_FORMAT` = `json` | `console` (default). `LOG_TO_FILE` (unset = dev only).
  `logs/access.log` always in console format. `/logs` viewer regex updated for it.
- Per-request/job context (`app/observability/context.py`) as a mutable dict in a
  ContextVar, merged by a processor. It's a dict because FastAPI's threadpool copies
  contexts, so a plain `ContextVar.set()` in a sync dependency would be lost.
- Redaction of sensitive keys (`password`, `token`, `authorization`, …). uvicorn's
  `color_message` dropped. httpx/httpcore capped at WARNING (they log full URLs).
- uvicorn's loggers routed through root, `uvicorn.access` silenced (the middleware replaces it).
- `Dockerfile-Dev`: `LOG_FORMAT=json`.

## Files
- `backend/app/observability/{__init__,context,logging_config}.py`
- `backend/app/core/config.py`, `backend/app/main.py`, `backend/app/templates/logs.html`
- `backend/pyproject.toml`, `backend/uv.lock` (structlog 26.1.0)
- `backend/Dockerfile-Dev`
- `backend/app/tests/modules/test_observability.py`
- `docs/logging.md` (rewritten), `CLAUDE.md` (repo) and root `CLAUDE.md` Logging sections

## Acceptance criteria
- [x] `LOG_FORMAT=json`: a stdlib `logger.info("x %s", 1)` renders as JSON with `event == "x 1"`, `level`, `logger`, `timestamp` (UTC `Z`).
- [x] `logger.exception(...)` renders an `exception` key with the traceback.
- [x] `extra={...}` keys become fields; non-serialisable extras don't raise.
- [x] structlog-native loggers go through the same handlers and context.
- [x] Context keys appear on records in the same context, and not after it is cleared.
- [x] Sensitive keys redacted; the login password and token never appear in captured logs.
- [x] uvicorn lines go through the same formatter (verified in the container: JSON `uvicorn.error` lines); `uvicorn.access` silenced.
- [x] `logs/access.log` only when `ENVIRONMENT=development` (container runs `ENVIRONMENT=local`: no file).
- [x] Console format matches the `/logs` viewer regex.
- [x] Full suite: no new failures against the baseline.

## As built (13-Oct-26)
- Found in the first full-suite run: structlog's `ConsoleRenderer` defaults to a **rich**
  traceback (rich comes with `fastapi[standard]`) that prints every frame's local variables.
  That leaks PII into the console and `logs/access.log`, and it hung a payroll test for
  minutes while rendering. Fixed with `exception_formatter=structlog.dev.plain_traceback`,
  covered by `test_tracebacks_never_include_local_variables` (json + console).
- Rotated `logs/access.log.N` files weren't matched by the repo's `*.log` rule.
  `.gitignore` now also ignores `*.log.[0-9]*` and `backend/logs/`.
- New `backend/.dockerignore` (`.venv/`, `logs/`, `.crypto_key.pem`, caches) keeps the host
  venv and the dev RSA key out of images. `.env` deliberately stays (it's tracked, and the k8s
  secrets merge writes into it).

Verification: full suite on a fresh migrated Postgres 18 = 267 failed / 1824 passed, with a failure set identical to the origin/main baseline (267, all pre-existing seed-data gaps); 43/43 new tests in test_observability.py pass. Live-checked in the monitoring/compose.yaml stack (images hrms-ws2-api:local and :dev). Commit 33b1ea6 on feature/gowtham_Observability.

Completed: 2026-10-13
