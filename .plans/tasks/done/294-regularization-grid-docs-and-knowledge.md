---
task: 294
title: Regularization grid — docs and knowledge
status: done
depends_on: [286, 287, 288, 291, 292, 293]
---

# 294 — Regularization grid — docs and knowledge

## Scope
Document what 286-293 built; no code.
- `docs/attendance-range-regularization.md`: the grid as the HR entry point (selection, quick-select, `targets` preview, batching rules, locked-day override), "Which tool when" table updated (several employees / scattered days -> grid; spreadsheet with times -> import).
- New section for bulk leave on behalf (modes, default rule, per-run savepoints, limits) in the leave domain doc under `docs/leave-and-attendance/leave/`.
- `hrms/CLAUDE.md` "Range regularization" blurb (the register no longer has a range button) and the root `CLAUDE.md`; `content/knowledge/attendance.ts` (in-app Knowledge Centre) + `knowledge/index.ts` if a topic is added; `.plans/attendance-shifts-leave-holidays-todo.md` rows.

## Files
`docs/attendance-range-regularization.md`, leave doc, both CLAUDE.md files, `frontend/src/content/knowledge/attendance.ts`, `.plans/attendance-shifts-leave-holidays-todo.md`.

## Acceptance criteria
- [x] Docs copy request/response shapes from the real schemas
- [x] `grep -ri "regularize range" docs CLAUDE.md` shows no stale claim of a register range button

## Progress (2026-10-28) — written, waiting on the UI tasks
Done: `docs/attendance-range-regularization.md` (header, tool-choice table, "preview takes either form", "The Regularization grid", limits), `docs/leave-and-attendance/leave/api-and-pages.md` (two bulk-on-behalf rows), `hrms/CLAUDE.md` (new Regularization grid blurb), Knowledge Centre topic `attendance.regularise-range` rewritten for the grid (same topicKey). The root `.plans/attendance-shifts-leave-holidays-todo.md` had no range-button claims to change.
Left: re-read once 289-292 are checked in a browser, in case the UI changes in review. Not moved to done because it depends on them.

Browser-verified by the user (2026-10-28); acceptance boxes ticked on that basis.
Completed: 2026-10-28
