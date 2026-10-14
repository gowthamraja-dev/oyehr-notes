---
name: hrms-task-tracker
description: >
  Track multi-step backend/frontend work in this repo as individual task files under
  `.plans/tasks/ongoing/` and `.plans/tasks/done/`. Use whenever a plan needs to be split
  into independently-completable units before executing, when picking up the next unit of
  a partially-built feature, or when a task's acceptance criteria are met and it needs to be
  moved to done. This is the repo's task-lifecycle convention — distinct from the whole-module
  planning docs directly under `.plans/*.md`.
---

# HRMS task tracker — `.plans/tasks/`

A lightweight, file-based task tracker so multi-step work survives across sessions without
re-deriving scope each time. Complements (does not replace) the whole-module planning docs
that already live at `.plans/*.md` (e.g. `leave-attendance-requirements-plan.md`) — those are
the *why/what* for a whole module; task files are the *checklist* for building one slice of it.

## 1. Layout

```
.plans/tasks/ongoing/   # not-yet-done task files
.plans/tasks/done/      # completed, verified task files — a record, never edited again
```

One Markdown file per independently-completable unit of work:
`.plans/tasks/ongoing/NN-<slug>.md`, numbered contiguously in the order they were carved out
of the parent plan (not necessarily the order they must execute — see `depends_on`).

## 2. Task file format

```markdown
---
task: 01
title: Short title matching the H1
status: ongoing
depends_on: []          # other task numbers, e.g. [1, 2] — omit or [] if none
---

# 01 — Short title matching the H1

## Scope
What this unit covers and, as important, what it explicitly does NOT cover (link the
sibling task file that owns the excluded part, if any).

## Files
Concrete paths this task creates or edits.

## Acceptance criteria
- [ ] Checklist of verifiable outcomes (tests pass, migration applies, endpoint returns X)
```

Keep each task file self-contained enough that a fresh session can execute it without
re-reading the parent plan — restate the concrete column lists, endpoint contracts, or
validation rules it needs, don't just say "see the plan".

## 3. Splitting a plan into tasks

- One file per unit that can be built, verified, and reviewed independently — not one file
  per tiny step. "Models + migration" is one task; "add a column" is not a task.
  - When you set up the layout for the first time, note the split (unit boundaries and how
    each is scoped down from the full plan) here as a project note for later.
- Set `depends_on` when order matters (e.g. a service layer depends on its models existing).
- Number contiguously across the whole plan being split, not per-dependency-chain.

## 4. Picking up work

Take the lowest-numbered file in `ongoing/` whose every `depends_on` entry is already in
`done/`. If several are unblocked, prefer the lowest number.

## 5. Completing a task — the "movement" step

Once a task's acceptance criteria are all met and verified (tests green, migration applied,
manual smoke-check done — whatever the file's own checklist says):

```bash
git mv .plans/tasks/ongoing/NN-slug.md .plans/tasks/done/NN-slug.md
```

Then flip `status: done` in the frontmatter and append a line `Completed: YYYY-MM-DD` at the
end of the file. **Do not otherwise edit the file's content after moving it** — `done/` is a
record of what was actually built and verified, not a living doc. If scope changes later,
that's a new task file, not an edit to a completed one.

Never delete a task file, from either directory — `done/` is the project's build history and
is useful for onboarding/auditing later.
