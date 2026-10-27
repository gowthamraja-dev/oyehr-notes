---
task: 258
title: HR Admin "Day swaps" screen — preview, flip-a-weekday, list, retry, remove
status: done
depends_on: [257]
---

# 258 — Day swaps screen (frontend)

Plan: `.plans/shift-day-swap-plan.md` §4. Repo: `workspace-1/hrms/frontend/`. API contract = task 257 (restated below).
Skills to follow: `hrms-date-format`, `hrms-confirm-dialog`, `hrms-spacing`; CLAUDE.md Tailwind-only and shimmer rules.

## Scope
1. **API client** in `src/lib/api.ts` (next to `replaceShiftWeekOffs`, ~line 2279), all via `secureFetch` (the shifts router is encrypted),
   errors through `_detailMessage` so a 409 "payroll period closed" text reaches the user:
   `DayOverrideRequest`, `DayOverridePreview`, `DayOverride` types mirroring 257's schemas;
   `previewDayOverrides`, `createDayOverrides`, `listDayOverrides(from, to, shiftId?)`, `archiveDayOverride(id)`, `recalculateDayOverride(id)`.
2. **UI** under `src/dashboards/hrAdmin/AttendanceShifts_components/` — a "Day swaps" section/tab beside Shift defaults
   (new file `components/DaySwaps.tsx`; read `index.tsx` first for how sections are mounted):
   - Scope: "All shifts" (default) or a multi-select of shifts.
   - Mode A *Pick dates*: rows of `DateField` + WeekOff/Working select. Mode B *Flip a weekday*: weekday select + From/To `DateField`s,
     helper line "Every <weekday> in the range becomes the opposite of what the shift rule gives."
   - Required reason. **Preview** button → table of dates: rule says → becomes, employees, locked days, people with punches,
     overtime expected, leave overlaps; skipped dates with the reason (holiday / no change); a blocking banner for a closed payroll period;
     a mode note "Recalculated now" vs "Queued — finishes within a few minutes". Save is disabled until a preview exists and nothing is blocked.
   - After Save: toast; the list below reloads.
   - List of swaps (default window: this month ±1) with: date (`dd-MMM-yy`), scope, WeekOff/Working chip, reason, recalc chip
     (Pending / Running / Done / Failed), counts from `recalc_result`, **Retry** on Failed, **Remove** via `useConfirm()`
     ("Removing restores the shift rule for this date and recalculates attendance."). While any row is Pending/Running, poll every 10 s and stop when none are.
   - Shimmer skeleton from `components/ui/Shimmer.tsx` primitives (`ShimmerTable` + `ShimmerForm`), exported as `DaySwapsSkeleton`;
     page-level padding/gap 10px; table header `py-[10px]`, body `py-3`; Tailwind only; no new `.module.css`.
   - Gated like week-off editing: only shown when the user may UPDATE ATTENDANCE; otherwise hidden, not disabled.

## API as built (task 257, done) — build against this, not the sketch above
Base `/api/v1/shifts/day-overrides`, all through `secureFetch`. Gates: list `READ ATTENDANCE`; preview, save, remove, retry `UPDATE ATTENDANCE` (hide the screen's actions for a READ-only user).
- `POST /preview` and `POST /` take `{ reason, shift_ids?, dates?: [{date, day_type}], flip?: {weekday, from_date, to_date} }` (exactly one of `dates` / `flip`; omit `shift_ids` for **All shifts**; `weekday` is ISO 1=Mon..7=Sun; flip range ≤ 92 days; ≤ 62 shift-dates; dates within 92 days back … 366 ahead).
- **Preview** → `{ mode: "inline"|"queued", employee_days_total, threshold, payroll_blocked_periods: string[], rows: [{ date, shift_master_id, scope, rule_day_type: "Holiday"|"WeekOff"|"Working"|"Mixed", proposed_day_type, skip_reason: null|"holiday"|"no_change"|"shifts_differ", holiday_wins, no_change, payroll_blocked, existing_override_id, impact: { employee_days, locked_rows, rows_changing, rows_with_punches, ot_rows_expected, absent_expected, leave_overlaps } }] }`. Skipped rows are in `rows` with `skip_reason` set (no impact numbers). Holiday here means the default calendar; `Mixed` = the shifts disagree. `leave_overlaps` = approved leave days whose stored fraction disagrees with the new day type. Preview returns 200 even for a locked payroll month (show a blocking banner from `payroll_blocked_periods`).
- **Save / remove / retry** all return `{ mode, employee_days_total, threshold, overrides: DayOverride[], skipped: [{date, shift_master_id, scope, reason}] }`. `mode: "queued"` means "finishes within a few minutes" (poll the list); `"inline"` means it is already `Done`/`Failed`.
- `DayOverride` = `{ id, shift_master_id, shift_name (null = all shifts), override_date, day_type, reason, recalc_status: "Pending"|"Running"|"Done"|"Failed", recalculated_at, recalc_result: { employees, days_recomputed, days_changed, days_force_locked, ot_rows_created, failed: [{employee_master_id, error}], attempts? } | null, is_active, archive, created_by_id, created_at, archived_by_id, archived_at }`.
- `GET /?from=&to=&shift_id=&include_archived=` (from and to required, ≤ 460 days). With `shift_id` it returns that shift's swaps plus the all-shifts ones.
- `DELETE /{id}` removes (soft); `POST /{id}/recalculate` is **Retry** (only for `Failed` or `Pending`; `Done` and `Running` → 409). A removed swap whose undo is still `Pending`/`Failed` appears only with `include_archived=true`: the screen's default list should show it until it is `Done`, or HR cannot retry it.
- Errors worth showing verbatim (`detail`): 409 payroll "Payroll for <month> is locked. Ask an Admin to unlock the payroll month first."; 409 "This swap is being recalculated right now. Try again in a moment."; 422 "Nothing to change: every date is a holiday, already set that way, or the shifts disagree"; 404 for a shift or swap that is not this tenant's.
- Saving a date that already has a swap for the same scope **updates it** (same id); an identical save is skipped as `no_change`.

## Files
- `workspace-1/hrms/frontend/src/lib/api.ts` (types + `previewDayOverrides`, `createDayOverrides`, `listDayOverrides`, `archiveDayOverride`, `recalculateDayOverride`)
- `workspace-1/hrms/frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/DaySwaps.tsx` (new: `DaySwaps`, `PreviewPanel`, `SwapRow`, `DaySwapsSkeleton`, `DaySwapsListSkeleton`)
- `workspace-1/hrms/frontend/src/dashboards/hrAdmin/AttendanceShifts_components/utils/daySwaps.ts` (new: every piece of logic that can be wrong without a browser)
- `workspace-1/hrms/frontend/src/dashboards/hrAdmin/AttendanceShifts_components/index.tsx` (mounts the section below "Organization shifts", behind `usePermission("UPDATE", "ATTENDANCE")`)
- `workspace-1/hrms/frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/Skeleton.tsx` (the page skeleton adds `DaySwapsSkeleton` for the same roles)

## Acceptance criteria
- [x] Flip Saturdays for a month → the preview lists every Saturday with the opposite day type (against the live API through the real client: 7 → 31 Oct, the 31st being a 5th Saturday with no attendance rows); Save is disabled before a preview (rendered, and `canSave`)
- [x] A holiday date and a no-change date show as skipped with the reason, not as errors (rendered `PreviewPanel` with a holiday, no-change and shifts-differ row: three italic "Skipped · …" rows, no red banner)
- [x] A closed-payroll 409 shows the server's sentence and writes nothing (live API through the real client: the exact sentence, 0 rows written; the preview reports it as an error banner + "Payroll locked" tag and keeps Save disabled)
- [x] After a queued save the list shows Pending and updates to Done on its own; polling stops when none are pending — **the data side**: live backend with the limit at 1, the driver ran the screen's loop (`needsPolling`) while the real scheduled job ran in the background: Pending → Done after 1 poll, then the loop stopped; a retry and a removal under queued mode also stayed queued until the job ran
- [ ] …the same, **in a browser**: the component's own `setInterval` effect and the chips re-rendering were not watched live (the effect is 5 lines, read and typechecked, not exercised)
- [x] Failed row shows Retry; Remove goes through `useConfirm` (rendered `SwapRow` in every state: Done → Remove; Pending → Remove; Running → Remove disabled; Failed → Retry + Remove, failure count with the employees on hover; removed + Failed → Retry only; removed + Done → no actions). No `confirm(` / `window.confirm` anywhere in the diff
- [ ] …clicking Remove and seeing the styled confirm modal and the toast: not done (needs a browser)
- [x] All dates display `dd-MMM-yy` (rendered output has no raw ISO date; weekday label read off local parts, checked under IST, Auckland and Los Angeles); every date input is `DateField` (3 in the initial render: one form row + the two list-window fields; no bare `<input type="date">`)
- [x] Skeleton mirrors the real layout (form card + table with header row, `ShimmerForm` + `ShimmerTable`, the list's column template); no centred spinner or "Loading…" text anywhere
- [ ] …a side-by-side visual check of skeleton vs real layout, spacing (10px gaps, `py-[10px]` / `py-3` rows), narrow widths: not done (needs a browser)
- [x] `npx tsc --noEmit`: 0 errors. `eslint` on the files I wrote/changed: clean (5 warnings remain in untouched code: `ShiftsList.tsx`, `useShifts.ts`, an unused `ShiftsList` import in `index.tsx`). `npm run build`: passes
- [x] Manual check against a running API, **through the real `api.ts` functions from Node, not through the UI**: inline path, queued path (limit 1), remove, retry (Failed → Done, inline and queued), the payroll refusal, server validation messages reaching the user as sentences, the audit/activity trail in the database (15 audit rows = 4 dates × 3 employees + 3 reversed; 6 POST + 1 DELETE activity rows)

## How it was verified (scripts are not in the repo; they live in the session scratchpad)
- The frontend has no test runner (only `lint`) and none was added. `daySwaps.ts` has no React in it, so its checks run under plain Node (`node --experimental-strip-types`): request building and every validation message, the 92-day flip and 460-day window edges, default window across year ends and a leap year, `canSave`, polling, visible swaps, the toast wording; run under three time zones. Mutation check, 5 deliberate bugs, each caught: Save ignoring that the form changed; a failed removal vanishing from the list; the 92-day limit off by one; payroll lock not disabling Save; Failed counted as "busy" for polling.
- The component and its parts were server-rendered with React (`renderToString`) with the real `DateField`, `Segmented`, `Chip`, `Shimmer*` and `useConfirm`; only the shell's `Icon` was stubbed (the shell imports Next-compiler-only modules).
- End to end: the real backend on a throwaway Postgres (port 5434, a seeded tenant + shift + 3 employees with real attendance rows for the October Saturdays), driven with the real `api.ts` over the real RSA/AES payload encryption.

## What this does NOT cover
- Anything that needs a browser: click-through, the date picker pop-up, the confirm modal, toasts, layout and spacing by eye, narrow widths. **Do a pass in the running app before relying on the visuals.**
- The page layout around the new section: it sits below "Organization shifts", whose own cards use the page's older `mb-5` / `px-5 py-4` chrome; inside the new section the gaps are 10px (`gap-[10px]`) and table rows follow `py-[10px]` / `py-3`.

## Decisions
- **Where it lives:** a section on the existing Attendance & Shifts page, below the shift list (the page has no tabs), shown only with `UPDATE ATTENDANCE` (hidden, not disabled). `usePermission` returns true while permissions load and for a role with no grid saved; the API still refuses such a role (the shifts API does not treat "no grid" as unrestricted), same as the page's own shift list.
- **Removed swaps stay visible until their undo is Done.** The screen always fetches with `include_archived=true` and filters (`visibleSwaps`): a removal whose recalculation is Pending or Failed stays in the default list, so HR can retry it; a finished one appears only under "Show removed". This closes the gap noted when task 257 was finished, with no backend change.
- **A preview is only good for exactly the request it was made for.** Any edit to the form invalidates it (the request key changes), and Save is enabled only for a current preview with something to write and no locked payroll month. The server enforces all of that again.
- After a successful save the dates and reason are cleared, but scope, mode and weekday are kept for the next swap.
- Client-side checks mirror the server's limits (reason ≤ 255, flip ≤ 92 days, list window ≤ 460 days, no repeated date) so the sentence appears before a round trip; the server's own message is shown for anything else.
- The skeleton for the list alone (`DaySwapsListSkeleton`) is used while the first fetch is pending, so the form is usable immediately; `DaySwapsSkeleton` (both cards) is for the page-level skeleton.
- `PreviewPanel` and `SwapRow` are exported only so their states can be rendered on their own.

Completed: 2026-10-27
