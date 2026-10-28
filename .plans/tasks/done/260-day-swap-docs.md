---
task: 260
title: Document the day-swap flow (resolution order, recalculation, hybrid runner, runbook)
status: done
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

## Carried over from tasks 258–259 (done) — things the docs must say
- **Responses:** `GET /shifts/employee-shifts/roster` cells and `GET /shifts/me/{date}` now carry `day_override` (`"WeekOff"` / `"Working"` / null), and `/shifts/me/{date}` also `is_week_off`. `day_override` is set **only when the swap changed the day** against the weekly rule; a swap that repeats the rule is not reported. Say so in `api-and-pages.md`.
- **The "Shifts this week/month" tile on the manager roster now counts working shifts only** (it used to count week-off cells too: SHF-D2). Mention it where the roster is described, and mark SHF-D2 done in `.plans/attendance-shifts-leave-holidays-todo.md`.
- The Day swaps screen keeps a removed swap in its default list until its undo finished (so a failed undo can be retried); `GET /shifts/day-overrides` needs `include_archived=true` for that.
- Paste the `scripts/permission_inventory.py` lines for the five `/shifts/day-overrides` routes into `docs/roles-and-permissions.md`.
- Tests share a database: a test that lists or counts `shift_day_overrides` must scope to its own tenant.
- The migration chain has three HRMS heads after the upstream merge; the day-swap revision is `d5e9a1c7f302` (down_revision `b83f6d1c0e47`). The hand-written DDL for hrms-dev is `UPGRADE_SQL` in that file, not yet applied anywhere shared.

## Files
- `workspace-1/hrms/docs/leave-and-attendance/shifts/day-overrides.md` (new, 10 sections)
- `workspace-1/hrms/docs/leave-and-attendance/shifts/domain-model.md` (new §2.4 + ER diagram), `api-and-pages.md`, `manager-scheduling.md`, `admin-configuration.md`; `docs/leave-and-attendance/README.md` (index row); `docs/leave-and-attendance/attendance/assembler.md` (§4 precedence)
- `workspace-1/hrms/docs/roles-and-permissions.md` (§7: shifts row and the five inventory lines)
- `workspace-1/hrms/frontend/src/content/knowledge/attendance.ts` (HR-facing text in two topics), `workspace-1/hrms/CLAUDE.md` (one sentence in the Overtime section)
- `.plans/attendance-shifts-leave-holidays-todo.md` (SHF-G1 and SHF-D2)

## Acceptance criteria
- [x] The doc matches what was built — checked against the code, not the plan: the setting name and default (`shift_day_override_sync_max_employee_days`, 500, env `SHIFT_DAY_OVERRIDE_SYNC_MAX_EMPLOYEE_DAYS`), the job (`shift_day_override_recalc`, `*/5 * * * *`), the status values, the audit action (`DayTypeOverridden`), the retry cap (3), the stale window (30 min), the per-run cap (20), the API limits (92 back / 366 ahead / 62 shift-dates / flip 92 / list 460) and the five routes with their gates were all read out of the running code in one script, and the routes through the project's own `permission_inventory.py`
- [x] A new developer can answer "why is this Saturday a week off though the rule says working?" from the doc alone: §2 is a four-step lookup (roster badge → Day swaps list → API → SQL) and the SQL was run against real data and returned the swap behind a swapped Saturday. (Judged by following it, not by a cold reader.)
- [x] Runbook steps were run once against a seeded database, and the doc shows real output: what is waiting or stuck; the job run by hand (and its stats line); a `Failed` swap read, its retries used up (`retries_exhausted`), and the by-hand re-queue; a dead worker's `Running` swap reclaimed after 30 minutes (it showed `attempts 2`); the audit and activity queries; the "which swap decided this date" query; the hand-applied DDL (run twice, no error). The five SQL blocks and the two bash blocks in the doc were then extracted and executed **as written**.
- [ ] …**Not rehearsed, and marked so in the doc:** the Admin's payroll unlock / re-lock (needs an Admin account and a real payroll month; the refusal and its message are tested), and applying the DDL to the shared hrms-dev database (deliberately not done without your go-ahead)
- [x] Linked from the shifts domain-model (§2.4 and the ER diagram) and API docs (§2.1, §2.3, §3.1, §3.3), the README index, the manager and admin pages and the assembler's precedence rule; SHF-G1 updated (covered for shift-wide and organisation-wide swaps; **per employee remains open**); SHF-D2 marked done
- [x] All relative links in the touched docs resolve; `tsc --noEmit` is clean after the knowledge-base edit

## What changed in existing docs
- `api-and-pages.md`: the roster row said "four queries"; it is five now (the swaps). Added `day_override` to the roster cell and to `/shifts/me/{date}` (plus `is_week_off`), the five new routes in §3.1, a paragraph on the SWAP marker and the working-shifts-only tile.
- `manager-scheduling.md`: the "Shifts this week" KPI counts working shifts only (it counted week-off cells before task 259); the SWAP badge.
- `assembler.md` §4: the precedence line now continues "…Holiday > shift override > all-shifts override > weekly rule > Working".
- `roles-and-permissions.md`: shifts row 16/18 → 20/22 (the two open routes are the self-service `/shifts/me*`) and the inventory lines.
- `CLAUDE.md`: one sentence, in the Overtime section because that is where a swap's most surprising effect lives (a worked day turned into a week-off becomes overtime on recalculation), saying that every week-off check must go through `calendar_resolver_service`. No new section was created, as the task asked.

## Known gaps — noticed, left alone (not part of this feature)
- **`roles-and-permissions.md` §7 is stale beyond the shifts row**: "117 of 233 endpoints gated" and the other modules' counts; the inventory tool now says **292 of 580**. I changed only the shifts row, so the table is not made to disagree with itself.
- **`api-and-pages.md` says `GET /shifts/me` was removed**; the inventory shows it is live again (ungated self-service; the employee app calls it). Not touched.
- **Mermaid:** the state diagram and the ER addition were read against the grammar but **not rendered** (no parser available locally). Please open the page once in a Mermaid-aware viewer.
- The in-app knowledge text was typechecked, not looked at in the running app.

## Series wrap-up (tasks 253–260)
All eight tasks are in `done/`. Nothing is committed. What remains for a person: a browser pass over the Day swaps screen and the roster marker (the two unticked visual boxes in 258 and 259); applying the DDL to hrms-dev with the project's usual go-ahead; merging the three HRMS migration heads; the two unrelated failures (`test_visitors`, `test_reimbursements_oversight`); and removing the throwaway Postgres container.

Completed: 2026-10-27
