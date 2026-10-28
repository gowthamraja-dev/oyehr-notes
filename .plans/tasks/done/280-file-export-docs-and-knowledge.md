---
task: 280
title: File export docs, CLAUDE.md section, knowledge
status: done
depends_on: [275, 276, 277, 278, 279]
---

# 280 — File export docs, CLAUDE.md section, knowledge

## Scope
Write down what 274–279 built so the next module's export is "one handler", as `docs/file-import.md` did for imports. Docs only — no code.

## Files
* `hrms/docs/file-export.md` (new): the engine (contract, writers, limits, formula guard, audit, why plain router), a **"Writing an export type"** checklist
  (handler → `_LAZY` → mount → frontend `FileExportConfig` → tests), access control, limits, how it differs from the import engine (stateless, no tables, no runner).
* `hrms/docs/attendance-export.md` (new): the four report types — layout, cell codes and legend, totals definitions (Payable days source, Working days rule, paid/unpaid leave
  split or its documented fallback), params, scoping, audit, example rows, and the "not employed = blank" rule.
* `CLAUDE.md`: add a **"File exports — the shared export engine"** section next to "File imports", linking both docs; one paragraph + the rule
  "a new export is a handler, never a new endpoint family or a second CSV writer".
* `hrms/docs/attendance-bulk-import.md` / `file-import.md`: one-line cross-link ("the reverse direction is `file-export.md`").
* `.plans/attendance-shifts-leave-holidays-todo.md`: tick/record the export item if one exists.
* Project notes via the `project-notes` skill if it applies to this repo's notes convention; memory: save only non-obvious facts (e.g. the decision that exports have no tables).

## Acceptance criteria
- [x] Both docs exist, are linked from CLAUDE.md, and every endpoint/param/code in them matches the shipped code (spot-check by calling or reading each)
- [x] CLAUDE.md section follows the surrounding tone and length
- [x] No claims about behaviour that was dropped or changed during 275–279 (re-read the completed task files' notes)

## Implementation notes
* Added `docs/file-export.md`, `docs/attendance-export.md`, a "File exports" section in both CLAUDE.md files (repo + workspace root), cross-links from `file-import.md` / `attendance-bulk-import.md`,
  and a Knowledge Centre article `attendance.export` (`frontend/src/content/knowledge/attendance.ts`). The todo file has no export item to tick.

Completed: 2026-10-27
