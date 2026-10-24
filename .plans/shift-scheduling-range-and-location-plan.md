# HR Manager → Shift Scheduling: range assignment + location/WFH visibility

Working copy: `workspace-2/hrms/` (branch `feature/gowtham_go_live` at time of writing).
Status: PLAN — no code written yet.

## 1. Reported problems (HR Manager → Shift scheduling → select shift)

| # | Report | Root cause (verified in code) |
|---|--------|-------------------------------|
| A | "Change location" — shift shows as `GEN` only; can't tell who is on WFH | The grid cell (`frontend/src/dashboards/hrManager/ShiftScheduling.tsx:340-381`) renders only `shiftMaster.code`. The API already returns `work_location_master_id` per day (`ResolvedDayOut`, `shifts/schemas.py:272`), the UI just never shows it. Changing location in the cell popup also forces the shift to stay selected (location is a sub-field of a shift assignment). |
| B | HR must assign day by day; wants week / month | The grid cell opens `BulkAssignShiftModal` in `singleDate` mode → `PUT /shifts/employee-shifts/day` (one employee, one date). The only multi-employee path (`POST /employee-shifts/bulk`) takes a single **effective date** and creates an *open-ended* standing row — it cannot express "Mon–Fri of next week" or "1–31 Nov", and it skips anyone who already has a row on/after that date. `auto_assign_shifts` takes a range but only materialises each employee's *existing* standing shift per day; it can't apply a new shift/location. |

## 2. Decision needed first: what is "WFH"?

Two things in the codebase are called WFH and they are different:

1. **Approved WFH request** — `attendance_request_details.request_type = 'WFH'` (employee-raised, approver-actioned), and the `WFH` attendance status (`status_masters` 419).
2. **A WFH work location** — a `work_location_masters` row (e.g. "Work From Home") assigned via the shift row's `work_location_master_id`. Nothing in the schema marks a location as remote, so today it's just a name.

The report ("HR manager applies WFH to whom") reads like **#2**: HR picks a location per shift assignment. Recommendation: treat #2 as the primary meaning, and *additionally* overlay #1 read-only on the grid (cheap, avoids HR scheduling someone on-site who has an approved WFH). **Confirm with whoever raised the defect before Phase 3.**

## 3. Plan

### Phase 1 — Show location on the grid (frontend only, smallest, ships first)
- `ShiftScheduling.tsx`: load `listWorkLocations()` alongside shifts; in each cell show a second line / small badge with the location short code (`work_locations.code` or first 3 letters of name). WFH location gets a distinct badge/icon.
- Add a **Location filter** (All / each location / "Not set") and a legend entry, next to the existing dept/role view — so HR can answer "who is on WFH this week" in one click.
- Cell tooltip: `GEN · 09:00–18:00 · Work From Home`.
- Add a **Location** column-state to the "Shifts this week" metric row (e.g. "On WFH this week: N").
- Skeleton: update `ShiftSchedulingSkeleton` only if the metric row changes (use shared `Shimmer*` primitives, no hand-rolled `animate-pulse` — note the current skeleton already hand-rolls one; fix opportunistically).
- Follow `hrms-spacing`, Tailwind-only, `hrms-date-format` (dd-MMM-yy in anything user-facing).

### Phase 2 — Range assignment backend
New endpoint `PUT /api/v1/shifts/employee-shifts/range` (plain `RequirePermission("UPDATE", "ATTENDANCE")` like `/day`):

```
{ employee_master_ids: [..], from_date, to_date,
  shift_master_id, work_location_master_id?, holiday_calendar_master_id?,
  weekdays?: [1..7],          # default all; lets HR say "Mon–Fri"
  skip_week_offs: true,       # default; uses is_shift_week_off on the NEW shift
  overwrite_manual: true|false }
→ { assigned, unchanged, week_off_skipped, manual_skipped, locked_skipped,
    outside_employment, per_employee: [...] }
```

Implementation notes:
- **Do not loop `_set_employee_shift_for_day` per day** for the write — a month × org would create ~30 single-day rows per employee and bloat `employee_shift_details`. Add `_set_employee_shift_for_range(...)` that carves **one bounded segment** `[from_date, to_date]` out of the timeline: truncate the covering row's tail, drop/trim rows fully inside, re-insert the "resume" remainder after `to_date`. Same carve semantics as the single-day function, generalised. When `weekdays`/week-off skipping makes the range non-contiguous, split into contiguous runs.
- Reuse existing guards: `_require_employee`, `_require_manager_or_admin`, `_require_assignable_shift`, `_get_work_location`, `_require_assignable_holiday_calendar`, `_within_employment`, `_attendance_locked` (locked days are skipped and reported, never an error for the whole batch).
- Cap range at 92 days (`_MAX_AUTO_ASSIGN_DAYS`) and employees per request; log INFO on success / WARNING at each guard; `log_activity` per employee (match `bulk_assign_employee_shift`).
- Tenant scoping on every query via `principal.tenant_id` (no RLS).
- A "location only" mode: `shift_master_id` optional + `change_location_only: true` → keep each day's current shift, change location. This fixes the "Change location forces re-picking shift" friction (A) and is how HR flips a week to WFH without touching shifts.
- Roster read perf: `list_shift_roster` does `resolve_employee_shift` + `_resolve_effective_row` + `is_shift_week_off` **per employee-day** (N×D×3 queries). Fine for a week; a month view of a whole org needs a batched version (load all rows for the date range once, resolve in memory). Do this in Phase 3 together with the month view.

### Phase 3 — UI: week / month apply
- `BulkAssignShiftModal`: add a **Apply to** segmented control — *This day* · *This week* · *Custom range* · *Whole month* — plus a weekday chip row (default Mon–Fri) and a "Skip weekly offs" checkbox. Date inputs use `DateField`. "Change location only" toggle. Result summary reuses the existing skipped-list panel.
- `ShiftScheduling.tsx`:
  - Row-level "⋯ → Assign week/month" and a column-header action for a whole day.
  - **Multi-select**: checkbox per employee row + "Assign shift to selected" (modal already accepts `employees[]`); drag-select a run of cells for one employee as a stretch goal.
  - Week/Month toggle on the breadcrumb control; month view uses the batched roster read (Phase 2 note). Keep the "never schedule into the past" clamp (`todayStart`).
  - "Copy last week → this week" action (backend: range endpoint called per source segment, or a thin `copy-week` helper) — the most common rota workflow after bulk apply.
- Employee Directory's existing bulk "Assign shift" keeps the effective-date (open-ended) mode; the modal distinguishes the two by whether `singleDate`/range mode is passed.

### Phase 4 — WFH overlay (only if §2 confirms request-based WFH matters)
- Roster response gains `wfh_request: true` per day, from approved (`status='Approved'`) `attendance_request_details` of type `WFH` overlapping the day. Read-only badge in the grid; no write path from this screen.
- If instead WFH must be a first-class location type: add `work_mode` (`OnSite|Remote|Hybrid`) to `work_location_masters` → **schema change, so `hrms-dbml-first` applies: draft `.plans/shift-wfh-schema.dbml`, get approval before any model/migration.** The shared hrms-dev DB can't be `alembic upgrade`d (see CLAUDE.md) — migration must be hand-written and existence-guarded.

## 4. Schema impact
Phases 1–3: **none** (`employee_shift_details` already models bounded dated segments). Phase 4b only, if approved.

## 5. Tests (same change as the code)
`backend/app/tests/modules/test_shifts.py` (97 tests today) — add: range happy path (interior split, edge-aligned, spanning multiple existing rows); weekday filter; week-off skip; locked-day skip; outside-employment skip; manual single-day row preserved when `overwrite_manual=false`; location-only keeps shift; manager can't target non-reports (403); **cross-tenant employee/shift/location ids rejected**; >92-day range 422; `from_date > to_date` 422; RBAC denial. Frontend: manual check of grid with WFH location, week apply, month apply, past-date clamp.

## 6. Task split (`hrms-task-tracker`, `.plans/tasks/ongoing/`)
1. Grid shows work location + location filter + WFH count (FE).
2. `_set_employee_shift_for_range` + `PUT /employee-shifts/range` + tests (BE).
3. Location-only change mode (BE+FE).
4. Modal range/week/month UI + multi-select (FE).
5. Batched roster read + month view (BE+FE).
6. Copy-last-week (BE+FE).
7. WFH request overlay / work-mode (pending §2 decision).

Suggested order: 1 → 2 → 4 → 3 → 5 → 6 → 7. Task 1 alone resolves defect A; tasks 2+4 resolve B.

## 7. Open questions
- WFH meaning (§2).
- Should assigning over a *manually set* single-day row overwrite it by default? (Proposed: yes for explicit HR action, with the checkbox to protect.)
- Is "whole org month view" required, or is department-filtered enough? Drives how urgent the batched roster read is.
- Should the range apply notify employees (WhatsApp/engagement)? Not in scope unless asked.
