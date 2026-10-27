# Week-off / working-day swap (org-wide or per shift) + attendance recalculation

Working copy: `workspace-1/hrms/` (user-directed 26-Oct-26, same as the WFH series; branch `feature/gowtham_go_live`; check `git -C workspace-1/hrms status -sb` before starting).
Status: PLAN — schema approved 26-Oct-26, no code written yet.
Schema (approved, the contract): [`shift-day-swap-schema.dbml`](shift-day-swap-schema.dbml) — one new table `shift_day_overrides`.
Do not restate or edit it here. Tasks: 253–260 under `.plans/tasks/ongoing/`.
Logging on this branch is stdlib `logging.getLogger(__name__)` (no structlog yet) — follow the surrounding modules.

## 1. Scope

**In**
- HR marks specific dates as `WeekOff` or `Working` for **every shift** (organisation-wide) or for **chosen shifts**,
  with a required reason. Typical use: the alternate-Saturday org swaps which Saturdays are off.
- A **bulk flip**: "for every Saturday between A and B, make the working ones off and the off ones working".
- A **preview** before saving: per date, what the rule says today, what it becomes, and what that does.
- **Recalculation** of the attendance already computed for those dates, including locked days, audited.
- **Hybrid recalculation** (decided 26-Oct-26): small swap → inline in the request; large swap → saved `Pending`
  and settled by a scheduled job. One function does the work in both paths.
- Removing a swap restores the rule for those dates and recalculates them again.
- Everything that asks "is this date a week-off?" becomes override-aware: attendance, register, roster grid,
  auto-assign `skip_week_offs`, leave day-counting, payroll's no-shift fallback, the employee app's `/shifts/me/{date}`.

**Out (explicit)**
- A permanent recurring-pattern change (effective-dating `shift_week_off_details`). Separate DBML if wanted.
- Half-day "Working" override (full day only).
- Any leave-ledger change. Approved leave over a swapped day is only **reported** in the preview.
- Re-running payroll. A date inside a closed payroll period is **refused**, not patched.
- Touching `shift_week_off_details` rows or locking history through the existing week-off replace. A swap never calls
  `_lock_computed_attendance_for_shift`.
- Materialising attendance rows for days that have none. Those resolve live under the new rule.
- The employee app: no screen. It already reads `is_week_off` from `/shifts/me/{date}`, which becomes override-aware.

## 2. Flow

```
HR: Attendance & Shifts → "Day swaps" → pick scope (All shifts | chosen shifts)
      mode A  pick dates, each WeekOff | Working
      mode B  "Flip a weekday between [from] and [to]"  (server expands: every Saturday, opposite of what the rule gives)
      reason (required)
  POST /shifts/day-overrides/preview   → per date: rule_day_type → proposed, holiday_wins, no_change,
                                         employees, rows_to_recalculate, locked_rows, rows_with_punches,
                                         ot_rows_expected, leave_overlaps, payroll_blocked; plus mode inline | queued
  POST /shifts/day-overrides           → upsert one row per (scope, date); recalc_status 'Pending'
        employee-days ≤ SHIFT_DAY_OVERRIDE_SYNC_MAX_EMPLOYEE_DAYS  → recalc inline now, status Done/Failed
        otherwise                                                   → stays Pending; job picks it up
  GET  /shifts/day-overrides?from&to&shift_id   → list with recalc_status, recalculated_at, recalc_result
  POST /shifts/day-overrides/{id}/recalculate   → re-queue (Failed/Pending); inline if small
  DELETE /shifts/day-overrides/{id}             → archive + recalc_status 'Pending' → same hybrid path
```

Resolution order everywhere: **Holiday > override(shift, date) > override(all shifts, date) > weekly rule > Working.**

## 3. Backend

| Area | Change | Task |
|---|---|---|
| Model + migration | `ShiftDayOverride` in `app/models/shift_day_override.py`, registered in `models/__init__.py`; Alembic revision on the HRMS branch + a hand-written, existence-guarded DDL copy for the shared hrms-dev DB (applied only with the user's go-ahead) | 253 |
| Resolver | One shared matcher in `calendar_resolver_service`: an override loader (tenant + date range) and a picker (shift beats org-wide). `week_off_from_rows(rows, date, override=None)`, `is_shift_week_off(..., tenant_id=None)`, `_resolve_week_off` (no-shift → org-wide override, then Sat/Sun), `resolve_day_types_for_pairs` (one extra query). The roster grid, auto-assign and leave callers get it for free | 254 |
| Recalc service | `app/services/shift_day_override_service.py`: `recalculate_override(db, cdp_id, override)` — find existing `employee_attendance_details` rows for the date(s) in scope, `recompute_attendance_day(force=row.is_locked)` in a SAVEPOINT each, write `attendance_audit_logs` (`DayTypeOverridden`) for every row whose `day_type`/`attendance_status` changed, fill `recalc_result`. Payroll guard + employee-day counter live here too | 255 |
| Hybrid runner | Settings `shift_day_override_sync_max_employee_days` (default 500). `JOB_DEFS["shift_day_override_recalc"]` per CDP every 5 min, advisory lock like `attendance_assembler_job`, picks `Pending`/`Failed`(retry cap) rows including archived ones, `Running` rows older than 30 min are reclaimed | 256 |
| API | Schemas, service, routes under `/shifts/day-overrides` (encrypted router, same as shifts). Gates via `RequirePermission` + `_require_shift_admin` (`ATTENDANCE` READ / UPDATE). Writes call `log_activity` (archive = deletion) per `hrms-activity-logging` | 257 |
| Roster field | `ResolvedDayOut` / roster cell gain `day_override: "WeekOff" \| "Working" \| None` | 259 |

Recalculation scope for one override row: attendance rows with `attendance_date = override_date` for the tenant, restricted to
`shift_master_id = override.shift_master_id` when the row is shift-specific (all rows for an org-wide one). A shift-specific row
also suppresses the org-wide row for that shift's employees, so an org-wide recalc recomputes everyone and the resolver decides.
Employees with no row for the date are not recomputed. Dates are limited to `today − 92 days … today + 366 days`.

Per-day side effects that already follow from `recompute_attendance_day` (no new code, but covered by tests and shown in the preview):
`day_type`, `attendance_status`, `payable_day_fraction`; `overtime/sync.sync_day` (Processed OT never touched); a row stays locked
after a forced recompute.

## 4. Frontend

| Screen | Change | Task |
|---|---|---|
| API client | `lib/api.ts`: types + `previewDayOverrides`, `createDayOverrides`, `listDayOverrides`, `archiveDayOverride`, `recalculateDayOverride` via `secureFetch` | 258 |
| HR Admin → Attendance & Shifts | "Day swaps" section beside Shift defaults: scope picker, date list / flip-a-weekday form (`DateField`), reason, **preview table** before Save, list of existing swaps with a recalc status chip (Pending / Running / Done / Failed + Retry), remove through `useConfirm`. Tailwind only, 10px page spacing, shimmer skeleton from the shared primitives | 258 |
| HR Manager → Shift Scheduling | Swapped dates show a small marker on the roster header/cell ("Swapped: working Sat") so OFF/working on the grid is explainable | 259 |

## 5. Tests (same change as each feature)

- `test_shift_day_overrides.py` (new): create / upsert / flip expansion / preview numbers / archive / retry; 401/403; **cross-tenant**
  (tenant B's shift id rejected, tenant B's org-wide row never affects tenant A); validation (date window, ≤ 62 rows, reason required,
  no-change 422, holiday skipped, closed payroll period 409).
- `test_calendar_resolver_batch.py`: single-date and batch functions agree with overrides present (org-wide, shift, both, none, holiday).
- `test_attendance_recompute.py`: override flips `day_type`; a locked row is forced and stays locked; audit row written once;
  second recalculation is a no-op (idempotent).
- `test_overtime.py`: Working → WeekOff day with punches creates one Pending OT row; a Processed row is untouched.
- Leave day-count test: `exclude_week_offs` leave over a swapped date counts the new working day.
- Job test: `Pending` row is picked up, `Failed` is retried then capped, `Running` rows are reclaimed, advisory lock honoured.
- `test_authz.py`: day-override routes need `ATTENDANCE` READ / UPDATE; a no-grid role is refused.

## 6. Open decisions (small, decide inside the named task)

- The "payroll period is closed" predicate — read how payroll refuses attendance edits (task 255); fall back to
  `locked_at`/`approved_at` not null.
- Sync threshold default (500 employee-days) — tune after measuring one `recompute_attendance_day` call (task 256).
- Whether `Failed` rows retry automatically N times or wait for HR's Retry (task 256; plan assumes 3 automatic tries).
