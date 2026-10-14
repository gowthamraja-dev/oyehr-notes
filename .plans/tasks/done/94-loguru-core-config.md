---
task: 94
title: Loguru shared logger config (core plumbing for the 3-module rollout)
status: done
depends_on: []
---

# 94 — Loguru shared logger config (core plumbing for the 3-module rollout)

## Scope
This whole 6-task set (94-99) intentionally introduces Loguru-based logging **only** in
`app/modules/shifts`, `app/modules/leave`, and `app/modules/attendance` — no other
existing module gets touched, and the app's current stdlib logging setup
(`app/main.py:_setup_logging`, the existing `@app.middleware("http")` request logger) is
left exactly as-is. This task is the one shared exception: a small `app/core/logging.py`
that configures a Loguru logger, importable by the three modules. It does not replace
`app/main.py`'s stdlib logging, does not add a global request-logging middleware, and is
not registered anywhere itself — it only exists so tasks 95-97 have something to import.

Do NOT:
- Touch `app/main.py`, `app/api/router.py`, or any module outside the three named ones.
- Remove or alter the existing stdlib `logging` calls in `app/core/scheduler.py` or
  elsewhere — out of scope.
- Add a request-logging middleware — the app already has one in `main.py`; duplicating it
  globally would be outside the "only these 3 modules" constraint. (A per-module request
  log statement, if wanted, is a call inside that module's own router — see tasks 95-97.)

## Files
- `backend/pyproject.toml` — add `loguru` as a dependency (`uv add loguru` from `backend/`).
- `backend/app/core/logging.py` (new) — the Loguru config, structured like the other
  single-purpose files in `app/core/` (e.g. `notify.py`, `security.py`).
- `backend/.gitignore` / `backend/app/.gitignore` — ensure `logs/` (the log directory) is
  git-ignored, matching how `.crypto_key.pem` is already ignored for dev-local artifacts.

## Implementation notes
- Configure on import (module-level `logger.remove()` + `logger.add(...)` calls in
  `logging.py` itself) so `from app.core.logging import logger` is all a module needs —
  no call site required in `main.py`.
- Sinks:
  - Console: colorized, e.g.
    `logger.add(sys.stderr, level=settings.log_level, colorize=True, format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level:<8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>")`
  - File: `logs/app.log`, `rotation="20 MB"` (or `rotation="00:00"` for daily — pick one,
    20 MB is simpler and sufficient for a 3-month project), `retention="15 days"`,
    `compression="zip"`.
  - Both sinks: `enqueue=True` (multi-worker/thread safety under Uvicorn), `backtrace=True`,
    `diagnose=False` (never leak local variable values in prod logs).
- Level comes from the **existing** `settings.log_level` field in `app/core/config.py`
  (already `"INFO"` by default, already env-overridable) — do not add a second/duplicate
  `LOG_LEVEL` setting.
- `logs/` path: create relative to the backend working directory (same place `.crypto_key.pem`
  lives today), so it works unchanged under the Docker Compose bind mount. No new AWS/S3
  wiring — this is dev/container-local, consistent with how the project already treats
  `.crypto_key.pem` as dev-only (see CLAUDE.md's Cloud setup section) — if prod log
  aggregation is ever needed, that's a separate future task, not this one.

## Acceptance criteria
- [x] `uv add loguru` run from `backend/`; `pyproject.toml` / `uv.lock` updated.
- [x] `from app.core.logging import logger` works without raising — verified in the local
      `.venv` (`uv run pytest` also imports it transitively via the three modules' tests,
      all 328 passing). Not separately re-verified inside a rebuilt `api` container, but the
      same lockfile/image build will pick up the same dependency.
- [x] The stdlib path is untouched — `app/main.py` wasn't modified by this task set at all;
      existing request logging continues to work exactly as before.
- [x] `logs/app.log` is created on first `logger.*` call (confirmed) and is git-ignored via
      the root `.gitignore`'s existing `*.log` rule — no separate `logs/`-specific entry was
      needed.

Completed: 2026-09-03
