---
task: 180
title: HR Manager attendance — live grace-based Absent count that drops on punch-in, plus break minutes
status: ongoing
depends_on: [178, 179]
---

# 180 — HR Manager attendance: live Absent count + break minutes

Work in **`workspace-2/hrms/`**. Run `git -C workspace-2/hrms status -sb` first. Builds on task 179
(which stores the same-day `Absent` after grace-in) and task 178 (which fills and exposes
`break_minutes`).

## Why
After task 179, `employee_attendance_details` holds today's `Absent` for no-shows past grace. The HR
Manager screen should show that count during the day and reduce it as soon as someone punches in.
Today the screen only loads on mount and filter change (there is no polling in
`frontend/src/dashboards/hrManager/Attendance.tsx`), so the count stays frozen until the page is
reloaded.

## Scope change — 2026-10-05: no grace cron
At the user's request, task 179's 5-minute `attendance_grace_absent` job (`run_grace_absent_sweep`)
was **removed**, along with its tests and docs. The recompute rule (`_grace_absent_elapsed`, row 14a)
stays. So nothing stores a same-day `Absent` for a no-show unless something else recomputes that day.
**This task's read-time rule is now the only way the HR Manager screen counts today's no-shows as
Absent.** That changes two things below:
- Drop any "gap between cron ticks" framing.
- **Employees with no stored row for today must be covered too.** This is the common case for a
  no-show. `_attendance_rows_for_pairs` (`dashboard_service.py`) synthesizes those rows without
  `shift_start_at`, so they would stay "Yet to check in" all day. Resolve each synthesized
  employee's shift and today's shift instants in batched, CDP-scoped queries (no N+1, reusing the
  recompute service's shift resolution and `_shift_instants`), then apply `_grace_absent_elapsed`.
  Acceptance test: an employee with **no row at all**, on a grace-10 shift at 09:20 → `absent`.

Partial work from the stopped agent run (read-time rule for stored NULL rows,
`_grace_shifts_for_rows`, 60 s `LIVE_REFRESH_MS` polling, tile subtitles, docs in
`api-and-pages.md` §4.5) is already in the `workspace-2/hrms` working tree, uncommitted and
unverified. Review it and build on it.

## Scope
### Backend (`backend/app/modules/attendance/dashboard_service.py`)
- `compute_effective_status` (`:82-109`) already maps a stored `"Absent"` to `EffectiveStatus.absent`,
  and `display_attendance_status` returns Present for a punched open day. So the grace-Absent rows
  are counted with **no classifier change**. Confirm this with tests rather than editing. Update the
  docstring: "`today` NULL means yet-to-check-in" is now "NULL today = within grace, or a shift
  without grace".
- **Gap between cron ticks (≤ 5 min):** to avoid that lag, add one read-time rule. When the stored
  status is NULL, the row is a Working day for **today**, and `row.shift_start_at` is set, call the
  shared `_grace_absent_elapsed` helper from task 179 (via the row's `shift_master_id` → policy). If
  it is True, classify the row as `absent`. Reuse the helper; never re-implement grace here. Rows
  synthesized for employees with no stored row (`_attendance_rows_for_pairs` `:253`) have no shift
  instants, so they stay `yet_to_check_in` until the cron materializes them. Note that limit in a
  comment.
- `_exception_matches` (`:703`): `missing_clock_in` is unaffected. Do not add a new exception type.
- Endpoint: `GET /api/v1/attendance/analytics` (`router.py:437`, `EncryptedRoute`, `_READ`). No contract
  change except the `break_minutes` field already added in task 178.

### Frontend (`frontend/src/dashboards/hrManager/Attendance.tsx`, 978 lines)
- **Auto-refresh while viewing today.** When the selected range includes today, re-fetch
  `getManagerAttendanceSummary` (`frontend/src/lib/api.ts:2429`) every 60 s. Pause while
  `document.visibilityState !== "visible"`, refetch immediately on becoming visible, and stop when
  the range is entirely past. Keep the existing data on screen while refetching, with no skeleton
  flash. The shimmer skeleton is only for the first load.
- Absent tile (`SUMMARY_TILES` `:59-75`): adjust the tooltip or subtitle to say that today's count
  includes employees who have not checked in by their shift's grace time and drops as they punch in.
  Update the "Yet to check in" tile description to match (within grace, or shifts without grace).
- Register row: show `break_minutes` next to worked hours (e.g. "8h 30m · 45m break"), and "—" when 0.
  Follow the existing hours formatting from task 166. Use `hrms-spacing` table density, and add no
  new column unless the row layout has no room. If a column is added, update the register's
  `ShimmerTable` column count in the same change.
- Don't touch the admin Insights page separately: it reuses `hrManager/Attendance.tsx`
  (per memory: the HR Manager attendance UI is canonical).

### Out of scope
- Employee-side and mobile UI wording for a same-day Absent.
- Push or real-time (Postgres NOTIFY) updates. Polling is enough here.

## Files
- `backend/app/modules/attendance/dashboard_service.py`: the read-time grace rule and docstrings.
- `backend/app/tests/modules/test_attendance_dashboard.py`.
- `frontend/src/dashboards/hrManager/Attendance.tsx` (plus its skeleton if the register columns change).
- `docs/leave-and-attendance/attendance/api-and-pages.md`: the HR Manager attendance section
  (live refresh and the Absent definition).

## Acceptance criteria
- [ ] Backend: 3 employees on a grace-10 shift starting 09:00, `now=09:20`. One punched at 09:05, one
      has a stored grace-Absent, and one has a NULL row (the cron hasn't ticked) → analytics returns
      present=1, absent=2, yet_to_check_in=0, and late=0.
- [ ] The Absent employee clocks in at 09:25 → analytics returns present=2, absent=1, and late=1.
- [ ] A grace-0 shift with no punch at 12:00 → counted as yet_to_check_in, not absent.
- [ ] Org-scoping: a grace-Absent in CDP B never appears in CDP A's counts. Department and shift
      filters still apply.
- [ ] Frontend: with today in range, the Absent tile drops within about 60 s of an employee punching
      in (manual check with two browser sessions), with no skeleton flash on refetch. Polling stops
      on a hidden tab and for a past-only range.
- [ ] The register shows break minutes for a day with an OUT → IN gap.
- [ ] `uv run pytest` green; `npm run lint` and `npm run build` pass in `frontend/`.
