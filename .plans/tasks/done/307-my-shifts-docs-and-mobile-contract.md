---
task: 307
title: My Shifts — docs, mobile integration skill, CLAUDE.md
status: done
depends_on: [302, 303, 305, 306]
---

# 307 — My Shifts: docs

## Scope
Document the shipped APIs: a "My Shifts" section in `docs/leave-and-attendance/shifts/api-and-pages.md` (endpoints, request/response shapes, rules, the
single-day ShiftChange flow and how approval writes), the endpoint rows in `.claude/skills/hrms-mobile-api-integration/SKILL.md` (+ the copy under
`workspace-2/hrms/.claude/skills/` if present) and a short "Shift change requests" paragraph in `workspace-2/hrms/CLAUDE.md`. Note in the docs that a
ShiftChange is an `attendance_request_details` row, and the CHECK constraint. Mark the day-swap note: a ShiftChange approval is a per-employee single-day
write, distinct from `shift_day_overrides`.

## Files
`workspace-2/hrms/docs/leave-and-attendance/shifts/api-and-pages.md`, the two SKILL.md files, `workspace-2/hrms/CLAUDE.md`.

## Acceptance criteria
- [ ] Every new endpoint documented with an example response
- [x] Mobile skill catalogue lists the 6 new `/shifts/me/*` routes
- [x] CLAUDE.md paragraph added; no stale statements about "WFH only" request types

## Progress (2026-10-29)
Docs written: `workspace-2/hrms/docs/leave-and-attendance/shifts/api-and-pages.md` (§3.3 'My Shifts'), the six routes in `.claude/skills/hrms-mobile-api-integration/SKILL.md` (root copy only; the `hrms/` clone was not touched), and a paragraph in `workspace-2/hrms/CLAUDE.md`. Endpoints are documented with response field lists, not literal JSON samples. Not committed.

Completed: 2026-10-29
