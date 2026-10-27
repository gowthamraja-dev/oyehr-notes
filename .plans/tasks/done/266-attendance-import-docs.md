---
task: 266
title: Attendance import — docs
status: done
depends_on: [268, 264]
---

# 266 — Attendance import — docs

## Scope
**Re-scoped by the v2 plan:** two docs — `docs/file-import.md` (the engine: tables, statuses, runner/heartbeat/resume model, retention, the `ImportHandler`
contract and a checklist for adding a new import type) and `docs/attendance-bulk-import.md` (the attendance handler): file layout and rules (with/without times, status skips, time zone, night shift), batch and row status machines,
runner/resume model (heartbeat CAS, chunk sizes, why not stored file), locked-day override and undo rules, retention, how to apply the migration on
hrms-dev, RBAC resource. Link it from a new short "Attendance bulk import" section in `workspace-2/hrms/CLAUDE.md` and the root `CLAUDE.md`.

## Acceptance criteria
- [x] Doc written and linked from both CLAUDE.md files

Completed: 2026-10-27
Note: two docs (file-import.md for the engine and the handler checklist, attendance-bulk-import.md for the attendance handler), linked from workspace-2/hrms/CLAUDE.md and the root CLAUDE.md.
