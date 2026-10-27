---
task: 257
title: /shifts/day-overrides API — preview, create/flip, list, archive, retry
status: done
depends_on: [253, 254, 255, 256]
---

# 257 — Day-overrides API

Plan: `.plans/shift-day-swap-plan.md` §2, §3 "API". Repo: `workspace-1/hrms/backend/app/modules/shifts/`.
Routes go on the existing `/shifts` router (already `route_class=EncryptedRoute`). Register the static paths **before** any
`/{shift_id}` route so `day-overrides` is not parsed as an id.

## Scope
Endpoints (all CDP-scoped by `principal.tenant_id`; reads `RequirePermission("READ","ATTENDANCE")`, writes
`RequirePermission("UPDATE","ATTENDANCE")` plus `_require_shift_admin(db, principal, "UPDATE")` in the service, like `replace_week_offs`):

| Method + path | Body / query | Returns |
|---|---|---|
| `POST /shifts/day-overrides/preview` | `DayOverrideRequestIn` | `DayOverridePreviewOut` |
| `POST /shifts/day-overrides` | `DayOverrideRequestIn` | `DayOverrideBatchOut` (201) |
| `GET /shifts/day-overrides` | `from`, `to`, `shift_id?`, `include_archived=false` | `list[DayOverrideOut]` |
| `DELETE /shifts/day-overrides/{id}` | – | `DayOverrideOut` (archived, recalc settled/queued) |
| `POST /shifts/day-overrides/{id}/recalculate` | – | `DayOverrideOut` (re-queue; inline if small) |

`DayOverrideRequestIn`: `shift_ids: list[int] | None` (None/absent = **all shifts**, stored as `shift_master_id NULL`),
`reason` (1–255, required), and exactly one of
- `dates: list[{date, day_type: "WeekOff"|"Working"}]`
- `flip: {weekday: 1..7, from_date, to_date}` — the server expands every matching weekday in the range (a 5th Saturday included),
  asks `resolve_rule_day_type` what the rule gives for each, and proposes the opposite.
`shift_ids` set → one row per `(shift, date)`; every id must belong to the tenant (404 otherwise, never "exists in another tenant").

Rules / validation:
- Dates within `today − 92 days … today + 366 days`; at most 62 resulting rows per request; flip range ≤ 92 days → 422.
- A date that resolves `Holiday` is **skipped** and returned under `skipped` with `reason: "holiday"` (holiday wins).
- A row that changes nothing for any affected shift is skipped with `reason: "no_change"`; if every row is skipped → 422.
- A date inside a closed payroll period (`payroll_period_blocking`) → **409** naming the period; nothing is written (all-or-nothing).
- Existing live row for the same scope + date → **upsert** (update `day_type`/`reason`, reset `recalc_status` to Pending), never a duplicate.
- Preview is read-only and returns, per row: `date`, `rule_day_type`, `proposed_day_type`, `scope` (all shifts / shift names),
  the 255 `ImpactCounts`, `holiday_wins`, `no_change`, `payroll_blocked`; and at the top `mode: "inline" | "queued"`
  (same threshold test as 256) and `employee_days_total`.
- Create: validates, writes rows, then `settle_overrides` (256). The response says which path ran and carries each row's
  `recalc_status` and `recalc_result` when inline.
- Archive: `is_active=false, archive=true, archived_by_id, archived_at`; `recalc_status='Pending'`; then `settle_overrides`.
  Never a SQL DELETE (`hrms-soft-delete`). Retry on a `Done` row → 409.
- Activity log: `log_activity(...)` for create, archive (deletion) — `hrms-activity-logging`; INFO on success, WARNING at each guard;
  no PII in logs.

## Carried over from task 256 (done)
- **Sessions are `autoflush=False`.** Flush after writing override rows and before `settle_overrides` or any count query, or the queries will not see them.
- `settle_overrides(db, cdp_id, overrides, *, actor_user_id) -> SettleOutcome(mode, employee_days, threshold)` in `app/services/shift_day_override_runner.py`: flushes, never commits. Return `mode` and `employee_days` from the create / archive / retry responses.
- **Set `created_by_id` on create and `updated_by_id` on upsert; set `archived_by_id` on archive.** The job audits as that user; an override with none is marked `Failed` ("no acting user").
- Retry: `recalc_status = 'Pending'`, `recalc_result = None` (clears the automatic-attempt count), then `settle_overrides`. Retry on a `Done` row is a 409; on a `Running` row also a 409 (a worker has it).
- Archive: `archive = true`, `is_active = false`, `archived_by_id`, `archived_at`, then `settle_overrides`; the job also picks archived rows.
- The default threshold (500 employee-days) is `SHIFT_DAY_OVERRIDE_SYNC_MAX_EMPLOYEE_DAYS`; measured 6.9 ms and 22 statements per row locally. The preview's `mode` must use the same function (`scope_row_count` summed over the request vs `settings.shift_day_override_sync_max_employee_days`).

## Carried over from task 255 (done)
- The service is `app/services/shift_day_override_service.py`: `count_impact(db, cdp, OverrideSpec | ShiftDayOverride)` → `ImpactCounts` (`.as_dict()`), `payroll_period_blocking`, `resolve_rule_day_type`, `recalculate_override`. Preview rows come from `count_impact` per `(scope, date)`; add `rows_changing` to the preview output.
- Payroll 409 text: "Payroll for <period name> is locked. Ask an Admin to unlock the payroll month first." (the guard is `locked_at`, not `processed_at`).
- Preview's `rule_day_type` comes from `resolve_rule_day_type` and only sees the tenant's default (all-locations) holiday calendar: label a `Holiday` there "Holiday (default calendar)". The recalculation still lets each employee's own calendar win.
- `leave_overlaps` = approved leave days whose stored fraction disagrees with the new day type (not "missing rows"); say so in the preview wording.
- `recalculate_override` does not mark `Running` and does not commit; the caller (256) marks `Running` first and commits after.

## Files
- `workspace-1/hrms/backend/app/modules/shifts/schemas.py` (add the six models above)
- `workspace-1/hrms/backend/app/modules/shifts/day_overrides.py` (new, the service; `service.py` was not touched)
- `workspace-1/hrms/backend/app/modules/shifts/router.py`
- `workspace-1/hrms/backend/app/tests/modules/test_shift_day_overrides.py` (34 API tests added to the 9 table tests), `test_authz.py` (2 new tests, 1 extended)

## Acceptance criteria
- [x] Alternate-Saturday org (Sat 2nd/4th off): flipping Saturdays in Nov for all shifts creates `WeekOff` on the 7th and 21st and `Working` on the 14th and 28th; the preview's per-date numbers (`employee_days`, `rows_changing`) are exactly what the create then reports (`recalc_result.days_changed`)
- [x] Small request → `mode=inline`, rows `Done`, attendance rows changed; large (threshold monkeypatched to 3 for 8 employee-days) → `mode=queued`, rows `Pending` with no result, attendance untouched; the preview reports the same mode
- [x] Holiday date skipped with reason `holiday` (preview: `holiday_wins`); an already-that-way date skipped as `no_change`; all skipped → 422 "Nothing to change"
- [x] Locked payroll month → 409 "Payroll for November 2026 is locked. Ask an Admin to unlock the payroll month first." and **zero rows written**; the preview reports it (`payroll_blocked`, `payroll_blocked_periods`) without refusing. Archive and retry in a locked month are refused too
- [x] Re-posting a date updates the row in place (same id, no duplicate, no unique-index error); an identical re-post is skipped; a removed swap can be made again as a new row
- [x] Archive: `archive=true, is_active=false, archived_by_id, archived_at`, never deleted; the rule returns, with a reversal audit row (`Swap removed: <reason>`); a `user_activity_details` row (`DELETE /shifts/day-overrides/{id}` with `deleted_data`); a second archive → 409
- [x] No grid / read-only grid / unauthenticated: 401 on all five routes, 403 on all five for a role with no grid, and for a READ-only grid 200 on the list and 403 on the four writes (also `test_authz.py`: an admin-flagged READ-only account cannot change anything; HR Manager's default grid can preview, list, and reach archive/retry; Employee's cannot)
- [x] **Cross-tenant:** another tenant's `shift_id` → 404 on preview, create and list; another tenant's swap id → 404 on archive and retry and it is left untouched; the list never returns another tenant's rows; an archived shift of this tenant is not offered either
- [x] Encrypted round trip through `EncryptedRoute` (preview): response `X-Encrypted: 1` and decrypts to the 4 rows
- [x] Validation 422s, parametrised over preview and create (17 cases): missing/blank/too-long reason, both/neither of `dates`/`flip`, empty `dates`, a repeated date, bad `day_type`, weekday 0 and 8, `from_date > to_date`, a flip over 92 days, empty and duplicate `shift_ids`, a date 105 days back / beyond 366 ahead, 63 rows; the exact window edges (92 back, 366 ahead, 62 rows) are accepted; the list needs `from` and `to`, `to >= from`, ≤ 460 days
- [x] `uv run pytest app/tests/modules/test_shift_day_overrides.py app/tests/modules/test_authz.py` green (43 + 44). Mutation check, 10 deliberate bugs, each caught: tenant filter dropped from the lookup; payroll guard off; shift ids unchecked against the tenant; holidays not skipped; `no_change` never detected; a Running swap changeable; date window off; archive without the activity log; list without the permission check; archive without the full soft-delete set
- [x] Full backend suite before/after: no new failure, +36 passing. `scripts/permission_inventory.py` lists the five routes as READ / UPDATE ATTENDANCE

## What was built
- `modules/shifts/schemas.py`: `DayOverrideRequestIn` (+ `DayOverrideDateIn`, `DayOverrideFlipIn`), `DayOverridePreviewOut` / `DayOverridePreviewRowOut` / `DayOverrideImpactOut`, `DayOverrideOut`, `DayOverrideSkippedOut`, `DayOverrideBatchOut`.
- `modules/shifts/day_overrides.py`: `preview_day_overrides`, `create_day_overrides`, `list_day_overrides`, `archive_day_override`, `recalculate_day_override`. Routes in `router.py` before the `/{shift_id}` ones.
- `UserActivityDetail` rows: `POST`/`PUT /shifts/day-overrides/{id}` on save (one per swap), `DELETE …/{id}` on remove, `POST …/{id}/recalculate` on retry.

## Decisions and deviations (258 builds against these)
- **Create, archive and retry all return `DayOverrideBatchOut`** (`mode`, `employee_days_total`, `threshold`, `overrides[]`, `skipped[]`), not a bare `DayOverrideOut` as the table above said, so the screen handles one shape and always knows inline vs queued. Archive and retry return one override and no `skipped`.
- **Wire names:** the request uses `date` (matching the task text); every output uses `override_date`, as the column does. Preview rows use `date`.
- **A new skip reason, `shifts_differ`.** A flip over *every* shift needs one answer per date, but shifts can have different rules (one shift off on the 2nd/4th Saturdays, another on every Saturday). Where they disagree the date is skipped and HR must choose specific shifts. "Every shift" means this tenant's live shifts (active, not archived). Preview `rule_day_type` can therefore be `Mixed`.
- **`no_change`:** with a live swap already at that exact scope and date it is `no_change` only if day type and reason are both identical (otherwise it is an update). With none, it is `no_change` when the date already resolves to the proposed type for every covered shift (rule plus any existing swap).
- **Holiday means the tenant's default (all-locations) calendar** in the preview and the skip; an employee's own calendar still wins at recalculation time (task 255).
- **Preview is gated UPDATE**, not READ: it is the first half of a write and reveals per-person impact.
- **A `Running` swap cannot be changed** (save over it, archive, retry → 409 "being recalculated right now"), so the job's final write cannot overwrite HR's change.
- **List:** `from` and `to` required, ≤ 460 days; `shift_id` returns that shift's own swaps **and the organisation-wide ones**; an archived shift is still viewable; archived swaps only with `include_archived=true`. Ordered by date, organisation-wide first.
- Dates are checked against "today" in the scheduler zone (IST): `today - 92 … today + 366`. `day_overrides._today` is the seam tests patch.
- The row limit is on candidate (shift, date) pairs, before skipping: 62.
- Not done here (belongs to 260): paste the `permission_inventory.py` lines for these routes into `docs/roles-and-permissions.md`.

Completed: 2026-10-26
