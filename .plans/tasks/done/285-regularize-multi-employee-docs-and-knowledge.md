---
task: 285
title: Regularize half day / WFH / multi-employee — docs and knowledge
status: done
depends_on: [281, 282, 283, 284]
---

# 285 — Regularize half day / WFH / multi-employee — docs and knowledge

## Scope
Document what 281–284 built; no code.
- `docs/attendance-range-regularization.md`: new "Day status" section (Present / Half day first-second / Work from home = Present + remote site, the new codes
  `DAY_OPEN` / `NO_REMOTE_SITE` / `WFH_LOCKED`, half-day punch maths), a "Many employees" section (the two bulk endpoints, limits 50 employees / 1,000 employee-days, 404-on-any-foreign-id,
  one commit, per-employee notification), and update the "Which tool when" table (several employees + same range/status → bulk regularize; different times per row → import).
- Root `CLAUDE.md` / `hrms/CLAUDE.md` attendance blurbs and the `.plans/attendance-shifts-leave-holidays-todo.md` tracker rows, if they mention the one-employee limit.
- `docs/attendance-bulk-import.md`: its "out of scope" cross-reference to range regularization, if present.

## Files
`docs/attendance-range-regularization.md`, `docs/attendance-bulk-import.md`, both CLAUDE.md files, `.plans/attendance-shifts-leave-holidays-todo.md`.

## Acceptance criteria
- [x] The doc matches the shipped request/response shapes (copy from the real schemas, not from the task text)
- [x] "Which tool when" table updated; no stale "single employee only" claims remain (`grep -ri "one employee\|single employee" docs/attendance-range-regularization.md`)

## As built (2026-10-27)
`docs/attendance-range-regularization.md` rewritten for day status and many employees (new sections, code table, tool-choice table, limits); `docs/attendance-bulk-import.md` cross-reference
and the `hrms/CLAUDE.md` range-regularization blurb updated. The root `CLAUDE.md` and the `.plans` tracker had no one-employee claims to change.

Completed: 2026-10-27
