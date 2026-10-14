---
task: 99
title: Document the shifts/leave/attendance Loguru logging pattern
status: done
depends_on: [95, 96, 97]
---

# 99 — Document the shifts/leave/attendance Loguru logging pattern

## Scope
Per CLAUDE.md's Documentation convention ("write a doc for any non-standard flow"): this
repo's app-wide logging today is stdlib `logging` (`app/main.py:_setup_logging`), and tasks
94-97 deliberately introduce a *second*, Loguru-based logger scoped to exactly three
modules. That split is non-obvious from the code alone and needs a doc so a future
contributor doesn't try to "fix" the inconsistency or copy the wrong pattern into a new
module.

## Files
- `backend/docs/logging.md` (new) — or `docs/logging.md` at repo root if that fits the
  existing `docs/` convention better; match whichever sibling doc
  (`docs/payload-encryption.md`, `docs/authentication-session-flow.md`) is closest in
  placement to backend-only concerns.
- `CLAUDE.md` — add a short section (or a line under an existing section) linking the new
  doc, matching how Payload encryption / Authentication are introduced.

## What the doc must cover
- Why two logging systems exist (this was a scoped, deliberate rollout to 3 modules, not a
  project-wide migration) and which is authoritative where: stdlib `logging` everywhere
  else, Loguru only inside `app/modules/{shifts,leave,attendance}`.
- How to use it: `from app.core.logging import logger`, with the level/exception/warning
  conventions from tasks 95-97 (one paragraph, point to those files rather than duplicating
  the full guidance).
- Sink config summary (console + `logs/app.log`, rotation/retention/compression, `enqueue`,
  `backtrace`/`diagnose` settings) and where `LOG_LEVEL` is controlled
  (`settings.log_level`, already existing).
- Whether the `/logs` dev endpoint from [[98-dev-logs-viewer-endpoint]] was built, and if
  so its path and dev-only gating.
- An explicit note: **if/when this pattern is later extended to more modules**, that's a
  new decision (env var duplication risk, double-logging risk if someone accidentally wires
  a global Loguru intercept over stdlib) — not something to do silently.

## Acceptance criteria
- [x] Doc exists (`docs/logging.md`) and is linked from `CLAUDE.md` (new "Logging" section,
      placed right after "Payload encryption").
- [x] The doc opens with a table (stdlib vs. Loguru, scope + import line for each) so a
      reader can tell which logger to import in a new file purely from which module it's
      in, without reading further.

Also covered: why the split exists, the INFO/WARNING/`logger.exception` conventions, the
full sink config (console + `logs/app.log`, rotation/retention/compression, `enqueue`/
`backtrace`/`diagnose`, where `LOG_LEVEL` is controlled), the `/logs` dev endpoint from
task 98, and an explicit "Extending this later" section warning against a second `LOG_LEVEL`
setting or a global Loguru intercept over stdlib.

Completed: 2026-09-03
