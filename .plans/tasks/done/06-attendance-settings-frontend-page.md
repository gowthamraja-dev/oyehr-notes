---
task: 06
title: Attendance Settings admin page (Regularization + Late-mark rules)
status: done
depends_on: [5]
---

# 06 — Attendance Settings admin page (Regularization + Late-mark rules)

**Reconciliation note (superseding the original scope below): this task's premise is stale.**
It was written assuming zero attendance frontend code existed. Since then,
`frontend/src/dashboards/hrAdmin/LeaveAttendance.tsx` was built directly (commits `35eb8ff` →
`c462ce2` → `db3ccb1`) and is already live at the `leaveAtt` nav slot, already in
`CUSTOM_VIEWS`, and already calls the real `GET/PUT /api/v1/attendance/config`. This task's real
scope is now **fixing two specific bugs/gaps in that existing file's Regularization panel** — not
creating a new `AttendanceSettings.tsx`, not introducing new `SegmentedControl`/`Toggle`
components (the live file already has a working `Field`/`Card`/`FieldDef` pattern; reuse it, don't
replace it). The Late-mark panel and the shimmer-skeleton/shell items below are already
done/live and need no further work. The 5 "Leave Types" cards on the same page are a separate,
much bigger gap (they're 100% mocked with no backend at all) — tracked by the `leave` module task
chain (`.plans/tasks/ongoing/08`+), not this task.

## Scope

Fix `LeaveAttendance.tsx`'s **Regularization** card only, per two decisions made while walking the
Admin Console mockup against the current build:

1. **Regularization window must be a constrained 3/7/15-day choice, not a freeform number.**
   The original version of this task explicitly chose freeform (`"a preset select would invent a
   constraint the schema doesn't enforce"`) — that reasoning is now reversed: task `07` is adding
   `Literal[3, 7, 15]` validation to the backend (`schemas.py`'s `AttendanceConfigOut`/
   `UpdateAttendanceConfigRequest`), matching `.design/Admin Console.dc.html`'s preset select
   exactly. The frontend must follow.
2. **The Approver field has a real bug and a missing constraint.** The live file's
   `APPROVER_TO_API`/`APPROVER_TO_UI` maps (`LeaveAttendance.tsx` lines 180-187) send/receive
   `"HR"` for the second option — but the documented valid value (`scripts/seed_attendance_leave_masters.py`'s
   description, task `07`'s new `Literal["ReportingManager", "HRAdmin"]` validation) is
   `"HRAdmin"`, not `"HR"`. This has been silently "working" only because the backend has no
   validation today; once task 07 lands, a `PUT` with `"HR"` will `422`. Separately,
   `docs/leave-and-attendance/09-tenant-policy-knobs.md` §4 says v1 only honours Reporting
   Manager and "HR Admin" must render **disabled**, not simply omitted or freely selectable — the
   live file does neither (both options are fully selectable today).

## Files

**`frontend/src/lib/api.ts`** — the existing `AttendanceConfig` type
(`getAttendanceConfig`/`updateAttendanceConfig` already exist and are already used) has one
latent bug unrelated to the two fixes above but worth closing while touching this file: it
includes a `leave_year_start_month: number` field that **does not exist** on the real backend
`AttendanceConfigOut` (confirmed: 16 fields, no `leave_year_start_month` — that knob is reserved
for the not-yet-built `leave` module and isn't served by `/attendance/config`). Remove it from the
type; nothing currently reads or writes it.

**`frontend/src/dashboards/hrAdmin/LeaveAttendance.tsx`**:

- **Window field** (`regularizationWindowDays`, currently `type: "number"` at line 144): change
  to reuse the existing `"segmented"` field type (already used for `accrualFrequency`/
  `resetCycle`/`approver` — do **not** invent a new `"select"` input type for a 3-option field),
  with `options: ["3", "7", "15"]`. Since `Field`'s segmented branch currently compares/stores
  `value` as the option string directly (see `onChange(field.key, option)` at line 282), and this
  field is numeric everywhere else in the config object, store the numeric value but render/compare
  against string options — either coerce in `onChange` for this field (`Number(option)`) or extend
  `FieldDef`/`Field` to accept numeric options generically (`options: (string | number)[]`,
  compare with loose equality or `String(value)`). Prefer the generic fix — `late_mark`'s reset
  cycle and other segmented fields stay string-only and are unaffected either way.
- **Approver field** (`approver`, lines 146, 180-187): fix the map values —
  `APPROVER_TO_UI`/`APPROVER_TO_API`'s `"HR"` entries become `"HRAdmin"` (keep the display label
  "HR" as-is only if that's the intended UI copy — otherwise "HR Admin" reads better and matches
  the doc's own wording; either way the **stored** value must be `"HRAdmin"`).
- **Disable "HR Admin" in the segmented control**, per doc `09` §4 ("a control that silently does
  nothing is worse than no control" — show *why* it's unavailable, don't hide it). This needs a
  small extension to `FieldDef`/`Field`'s segmented rendering (currently no notion of a disabled
  option, lines 276-291): add `disabledOptions?: string[]` to `FieldDef`, and in the segmented
  render branch, for any option in that list — render with reduced opacity + `cursor-not-allowed`,
  no `onClick` handler, and a `title`/tooltip hint, e.g. "Coming soon — v1 routes all
  regularization approvals to the Reporting Manager." Apply this only to the `approver` field's
  `FieldDef` (`disabledOptions: ["HR"]` — the UI label, not the stored value, since disabling is a
  rendering concern keyed by what's displayed).
- No other change to this file — the Late-mark panel, the load/save `useEffect`/`handleSave`
  flow, the two-pane shell, and the merge-into-`attendanceConfig` PUT strategy are already correct
  and already live.

## Flagged but explicitly out of scope

`docs/leave-and-attendance/14-config-knob-reference.md` §4.3: `attendance_rebuild_window_days`
(id 321 in the old scheme, a column on task 07's new table, not wired to any endpoint yet) must be
`>= regularization_window_days`, rejected (not warned) on write — this validation does not exist
in `service.py::update_config` today. Constraining the window to 3/7/15 in this task does not fix
that cross-field invariant; it remains unenforced until `attendance_rebuild_window_days` is
actually wired to an endpoint. Not fixed here.

The 5 "Leave Types" cards on the same page (`POLICIES` entries with `kind: "leave_type"`) are
fully mocked and out of scope for this task — see the `leave` module task chain
(`.plans/tasks/ongoing/08` onward).

## Acceptance criteria

- [x] `AttendanceConfig` type in `api.ts` no longer includes `leave_year_start_month` — verified
      already absent (it never had it; the stale field only existed in this task's original code
      snippet, not in the real file).
- [x] Regularization window renders as a 3-option segmented control (3/7/15 days), not a number
      input; selecting each option and saving round-trips correctly against the backend. Verified
      live via browser: selected 15, saved, hard-reloaded the page, and 15 was still selected on
      re-fetch — confirmed against `GET /api/v1/attendance/config` (200) in the network log, no
      console errors. (Task 07's backend `Literal[3, 7, 15]` validation is still pending — today
      the backend accepts any int — but the frontend now only ever sends 3/7/15.)
- [x] Approver segmented control sends/receives `"HRAdmin"` (not `"HR"`) for the second option —
      fixed in `APPROVER_TO_UI`/`APPROVER_TO_API`; confirmed via code review. Not exercised
      end-to-end in the manual test since "HR" is now disabled and unselectable (see next item),
      so `"HRAdmin"` is never actually sent by this page — the fix guards against the value ever
      being wrong if that changes later.
- [x] "HR Admin" renders visibly disabled (reduced opacity, `cursor-not-allowed`, no click
      handler) with a hint explaining why, and cannot be selected or saved. Verified live:
      clicking "HR" leaves "Reporting Manager" selected with no change; `document.querySelector`
      on the button confirmed `disabled: true`, the expected `title` tooltip text, and
      `cursor-not-allowed opacity-60` in its class list.
- [x] Late-mark panel, skeleton-free loading state (existing `"Loading attendance config…"` text),
      and the rest of the page are unaffected — no regression. Verified live: Late-mark Rules
      panel (threshold/reset-cycle/notify toggle) rendered and behaved normally throughout.

Completed: 2026-08-12
