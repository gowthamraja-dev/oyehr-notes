---
task: 260
title: Document the day-swap flow (resolution order, recalculation, hybrid runner, runbook)
status: ongoing
depends_on: [253, 254, 255, 256, 257, 258, 259]
---

# 260 — Docs

Plan: `.plans/shift-day-swap-plan.md`. CLAUDE.md's rule: a flow that is not obvious from the code gets a doc under `docs/`. Repo: `workspace-1/hrms/`.

## Scope
New doc `docs/leave-and-attendance/shifts/day-overrides.md` covering:
1. **What it is and when to use it** — dated WeekOff/Working exceptions vs the weekly rule (`shift_week_off_details`) vs a holiday; why the
   alternate-Saturday swap needs it; what it is NOT (no permanent pattern change).
2. **Resolution order** — Holiday > shift override > org-wide override > weekly rule > Working; the single matcher in `calendar_resolver_service`.
3. **Recalculation** — which rows are recomputed, why gap days resolve live, forced recompute of locked rows (stay locked), the audit row
   (`DayTypeOverridden`), what happens to OT / Absent / leave / payroll (the four side effects from the schema note), idempotency.
4. **Hybrid runner** — the Setting and its default, inline vs queued, the 5-minute job, advisory lock, `Running` reclaim, retry cap, how to read `recalc_result`.
5. **Runbook** — a swap stuck `Pending` (check the job log, run retry), a `Failed` swap (read `failed[]`), undoing a swap, what to do when the date is in a closed
   payroll period (reopen payroll first), the hrms-dev hand-applied DDL.
6. **API summary** — the five routes and their gates (`ATTENDANCE` READ / UPDATE).

Also: add a one-line pointer from `docs/leave-and-attendance/shifts/domain-model.md` (tables list) and `api-and-pages.md`, mark the
week-off-per-date gap (`SHF-G1` in `.plans/attendance-shifts-leave-holidays-todo.md`) as covered for org/shift-wide swaps (per-employee remains open),
and add a short "Day swaps" entry to `frontend/src/content/knowledge/attendance.ts` if the knowledge base lists week-offs. Link the new doc from
`hrms/CLAUDE.md` only if a relevant section exists (shifts/attendance); do not invent a new CLAUDE.md section for it.

## Files
- `workspace-1/hrms/docs/leave-and-attendance/shifts/day-overrides.md` (new)
- `workspace-1/hrms/docs/leave-and-attendance/shifts/domain-model.md`, `api-and-pages.md`
- `workspace-1/hrms/frontend/src/content/knowledge/attendance.ts` (only if applicable)
- `.plans/attendance-shifts-leave-holidays-todo.md` (status note on SHF-G1)

## Acceptance criteria
- [ ] The doc matches what was built: route paths, Setting name and default, job name and cron, status values, audit action string — checked against the code, not the plan
- [ ] A new developer can answer "why is this Saturday a week-off though the rule says working?" from the doc alone
- [ ] Runbook steps were run once against the dev stack (or marked as untested with the reason)
- [ ] Linked from the shifts domain-model and API docs; SHF-G1 note updated
