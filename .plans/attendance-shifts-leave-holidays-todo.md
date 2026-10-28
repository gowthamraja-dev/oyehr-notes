# Attendance · Shifts · Leave · Holidays — consolidated TO-DO

Consolidated on 16-Oct-26 from:
- `.plans/attendance-and-shifts-gap.md` (HR Manager feedback notes)
- `issues.csv` (84 review rows; the 33 touching attendance / shifts / roster / leave / holidays / devices are used here)
- `workspace-2/hrms/docs/leave-and-attendance/**/gaps.md` (older design-level gaps, referenced as `gaps#N`)
- a read of the code in `workspace-2/hrms` (branch `feature/gowtham_go_live`); nothing was run, so every "code says" is from reading only
- `.plans/tasks/ongoing/` + `done/` (to avoid re-planning what exists)

**Paths** below are relative to `workspace-2/hrms/backend/app/` (BE) or `workspace-2/hrms/frontend/src/dashboards/` (FE).
**Size:** S ≤ ½ day · M 1–3 days · L > 3 days. **Priority:** P0 fix now · P1 next · P2 later.
**Schema flag 🗄️** = needs a DBML draft + your approval first (`hrms-dbml-first`) before any plan/task file.

---

## Task tracker — attendance P0 converted (16-Oct-26)

All three attendance P0 items are now task files in `.plans/tasks/ongoing/` (numbers continue after 233). Run order follows `depends_on`.

| Task | File | Covers | Depends on | Status |
|---|---|---|---|---|
| 234 | `done/234-hr-reopen-locked-attendance-day.md` | ATT-D1 (override part) — audited HR regularization on a locked day. Backend + tests + docs done 16-Oct-26; **no UI field for the reason yet** and one acceptance box (full pytest green) left unticked — see the file's Notes | — | **done** |
| 235 | `235-locked-day-message-and-shift-edit-warning.md` | ATT-D1 (visibility part) — clear 423 text, lock-impact preview + confirm in shift editor, stale comment | 234 | ongoing |
| 236 | `236-attendance-day-panel-missing-clockout-hint.md` | ATT-D2 — "Incomplete" + hint + Regularize in the Day tab, `missing_clock_out` in API | — | ongoing |
| 237 | `237-attendance-status-rule-legend.md` | ATT-G1 — `GET /attendance/status-rules` + "How status is decided" popover | — | ongoing |

Not converted (not P0): ATT-D3…D7, ATT-G2…G7, ATT-N1 (needs DBML first). Open product decisions in §6 do **not** block 234–237 (236 and 237 deliberately avoid changing any rule).

---

## 0. Read this first — what the code changed about the reports

Several reported "bugs" are the code behaving as designed, with the rule hidden from the user. These are re-classified so effort goes to the real problem.

| Reported | What the code actually does | Real problem |
|---|---|---|
| "4h54m = Present, 2h32m = Half day, rule inconsistent" (ATTENDANCE-B4) | The General shift has overrides **full day = 4h, half day = 2h** (ATTSHIFTS-B2). Those thresholds explain every row quoted. | Bad config + **rule not visible anywhere** (no legend). The "inherited" label in the shift form also doesn't match the backend default (see SHF-D4). |
| "Absent + Late" (INS-B3) | Any day with worked time below half-day threshold is stored **Absent** (`SHORT_DAY_STATUS`, `services/attendance_recompute_service.py:49`); late is **not zeroed** for Absent/HalfDay (`:379-381`). | Late and status are independent, so contradictory pills are possible. Needs a decided rule (ATT-D3). |
| "Present 4 days, late 5 days" (notes) | Late is counted on its own (`modules/attendance/dashboard_service.py:376-377`), not limited to Present days. The docstring at `:735-739` admits late can exceed present. | Counting rule is wrong for display. Same fix as above. |
| "Attendance closed for Sep month" (notes #6) | That text does not exist. The only lock is `employee_attendance_details.is_locked` → HTTP 423 *"Attendance for {date} is locked"*. It is set in **two** places: (1) a shift timing/policy/week-off edit (`modules/shifts/service.py:326-350`) and (2) **automatically by the recompute once the shift's `regularization_window_days` has passed** (`services/attendance_recompute_service.py:208-222,755-756`). No month-close, no payroll-cutoff link. | A 30-Sep request approved on 10-Oct is most likely locked by path (2) (a 10-day window), which HR on-behalf cannot get past. Needs the override (task 234) and, long-term, a real period-close (ATT-N1). |
| "B. Nagaraju Absent while roster shows no shift" (ATTENDANCE-B6) | On re-test the register shows **General** shift, not "no shift". | Probably a genuine absence. Real issue is the roster `—` pattern (SHF-D3). Downgraded; close after re-check. |
| "Week-off bar not showing" (notes #4) | `shared/EmployeeAttendanceChart.tsx:54-63` already has a WeekOff series; the legend only lists statuses present in the data. | Not reproduced in code. Needs a repro (which employee/range). Likely data (days stored as another status). |
| "Remote Work employees get no holidays" (HOLIDAYS-B1) | The resolver gives no-location employees the **org-wide** calendar (`services/calendar_resolver_service.py`). Only the admin **filter** hides org-wide rows. | UI bug in the filter (HOL-D1). But a worse real bug exists: HOL-D2. |
| "Save on New shift fires nothing" (W-SHIFTS-1) | Save is blocked client-side: new-shift draft defaults `overtime_tracking_enabled = true` with `ot_after_minutes = null`; the error banner is in a collapsed panel, off-screen (`hrAdmin/AttendanceShifts_components/components/ShiftDefaults.tsx:188-204,347-351`). | Bad default + invisible error (SHF-D1). |
| "Location end < start accepted" (W-SHIFTS-5) | Validators exist for work location (`modules/attendance/schemas.py:45-47,77-79`; `service.py:358-366`) and shift assignment (`shifts/service.py:769`). Not reproduced. | Re-test; if still reproducible it is a different endpoint (VER-1). |
| "Policy wizard start date not kept" (W-LEAVE-7) | `effctv_dt` is sent and persisted on create and patch (`modules/leave/policy_service.py:~272-309`; FE `hrAdmin/Leave_components/LeavePolicies.tsx:379`). | Not reproduced. Probably the segmented date input (typing leaves it empty). Re-test (VER-2). |

---

## 1. ATTENDANCE

### 1A. Defects (existing behaviour is wrong)

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| ATT-D1 | P0 | M | 📋 **TASKS 234 + 235** · **Shift edits silently lock past attendance, and a locked day blocks regularization even for HR.** Editing shift timing/policy/week-off — or simply letting the regularization window pass — locks the past computed row. Regularize submit and approve both return 423 on a locked day. HR on-behalf also cannot get past it. | `shifts/service.py:326-350`; `attendance/service.py:945,1050,1591,1964`. **Refined after reading the code:** the lock is a *deliberate* freeze of history and **stays**. It is set by a shift edit **and** automatically once a shift's regularization window passes (`attendance_recompute_service.py:755-756`) — the latter is the likelier cause of the 30-Sep case. The defect is that there is no way back and no warning. Action: 234 = audited HR override (reason required, forced recompute of that one day); 235 = clear 423 text, impact preview + confirm before a locking shift edit, fix the stale model comment (`models/employee_attendance_detail.py:70`). |
| ATT-D2 | P0 | S | 📋 **TASK 236** · **Missing clock-out silently zeroes the day.** Closed day with IN and no OUT = Present, remark "Forgot to clock out", but worked hours "—" and Attendance % 0%, with no hint in the day panel (ATTENDANCE-B3). | `recompute:519-523`; `dashboard_service.py:236-243,640-648`. Cause of 0%: payable fraction is 0 for that day. Action: show "Incomplete" + hint + Regularize action, show "—" instead of 0%; API exposes `missing_clock_out`. Payable/payroll treatment left to the §6 decision. |
| ATT-D3 | P1 | M | **Late counted independently of status.** Absent + Late, Half day + Late, late days > present days. | `recompute:379-381`; `dashboard_service.py:376-377`. **Decision needed (§6 Q1):** recommended — late applies only to Present/HalfDay days; Absent never shows Late; all late counts use present days as denominator. |
| ATT-D4 | P1 | S | **Punctuality denominator ≠ Present.** "28 of 50 on time" vs 49 Present; range "176 of 293" vs 276 (ATTENDANCE-B2). | `dashboard_service.py:735-741, 708, 355-378`. Code uses Present count as denominator, so a population/date mismatch exists between the two tiles (probably open day or HalfDay/OnDuty/WFH inclusion at `:136`). Reproduce with the 09-Oct data, then align both to one definition. |
| ATT-D5 | P1 | S | **Department filter shows 14 options for 9 departments** (ATTENDANCE-B1, INS-B1). The code already reads `department_masters` (`employees/service.py:1273-1288`; filter at `dashboard_service.py:301-308`), so the twins are probably **duplicate `department_masters` rows** (case variants + 2 extras). | Data clean-up + unique case-insensitive index on `(cdp, lower(name))`. Check tasks 187–192 (all still "ongoing"; attendance part of 188 is effectively done — update status). |
| ATT-D6 | P2 | S | **Grace shows 15/15 while Flexible = Disabled** (ATTSHIFTS-B1). | List shows the stored value even when the rule is off. Show "—" / "off" in the list when the toggle is off, or clear on save. |
| ATT-D7 | P2 | S | **Leave "Absent" after approved auto-approve leave not rebuilt** (see LEV-D2) — listed here because it shows on the attendance register. | — |

### 1B. Gaps (missing capability)

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| ATT-G1 | P0 | S | 📋 **TASK 237** · **No visible rule for Present / Half day / Absent / Late.** Users cannot tell why a day got its status ("What is logic for Absent and Present — put those details on the system"). | Only grace tooltips exist (`hrManager/Attendance.tsx:86,95`). Add a "How status is decided" legend/popover on the register, showing the *actual* thresholds of the selected shift (full-day, half-day, grace-in/out, auto-absent day). Read from the same function as the recompute (`day_thresholds`, `recompute:400-410`) so it can't drift. |
| ATT-G2 | P1 | M | **No month-close / attendance-period lock policy** (notes #6). Regularization window is per shift only (`policy_config.regularization_window_days`, 0 = unbounded); there is no "until day X of next month" rule and nothing ties to payroll close (`PayrollPeriod.locked_at` exists, not read by attendance). | See ATT-N1 for the proposed design. |
| ATT-G3 | P1 | M | **No explanation for status "today"** — someone shown Absent after grace then Present when they punch in (notes last line). Task 179/180 intentionally flag same-day Absent after grace-in. | **Decision needed (§6 Q2):** recommended — before day close show "Late / Not in yet", and only stamp Absent at day close; keep the live count as "Not checked in". |
| ATT-G4 | P1 | M | **Biometric duplicate / unmapped IDs have no fix action** (DEVICES-B1, B4). Banner says one person is credited with another's punches, but only the terminal can be fixed. 7 unmapped IDs per terminal. | `devices/*`. Add in-app "Reassign / unmap ID" for HR with audit; surface duplicate IDs in the matrix; list unmapped IDs with a "Map to employee" action. |
| ATT-G5 | P2 | S | **Device logs drawer says "Development only" but is reachable by HR Manager and shows name + PIN** (DEVICES-B2). | Gate behind admin/dev flag or mask PIN/name. Also log order not newest-first consistently (DEVICES-B3 — probably UTC vs IST). |
| ATT-G6 | P2 | M | **"3 late marks = ½ day"** cannot be applied per row (`gaps#12`). | Compute at payroll time as an aggregate; do it with ATT-D3's decision. |
| ATT-G7 | P2 | S | **Overlap gate between attendance request types** missing (`gaps#41`). | Add validation on create. |

### 1C. Suggestions (improve what exists)

| ID | P | Size | Item |
|---|---|---|---|
| ATT-S1 | P1 | S | Week-off bar: add a visible "Week off" / "Holiday" entry in the chart legend even when the range has none, and reproduce the reported case (VER-3). |
| ATT-S2 | P2 | S | Regularization error messages should name the cause and the next step ("Locked by a shift change on 12-Sep — ask HR to reopen") instead of a bare 423. |
| ATT-S3 | P2 | S | Day-status wording: use "HalfDay" and "Late" as separate badges consistently; today Half day appears as "Present / Late / Half day" together. |
| ATT-S4 | P2 | S | Show regularization eligibility on the employee side ("You can regularize until 10-Oct") using the same window rule. |

### 1D. New implementation

| ID | P | Size | Item |
|---|---|---|---|
| ATT-N1 | P1 | L 🗄️ | **Attendance period close.** Proposed: per-CDP `attendance_period_locks` (period month, cutoff date, locked_at/by, reopened_at/by, reason). Rule: a month auto-locks at *cutoff day N of next month* (tenant parameter) or when payroll locks that period. Regularization/leave edits into a locked month are refused with a clear message, **except** an audited HR "Reopen period / late-regularize" action. Replaces the accidental lock in ATT-D1. `gaps#36` already recommends a cutoff job + manual "lock month". |
| ATT-N2 | P2 | M | Auto-close forgotten sessions at shift end + grace (status "Auto-closed — needs review"), instead of Present with "—" hours. |
| ATT-N3 | P2 | M | Tenant-level attendance rules page (thresholds as defaults for all shifts, legend preview). |

---

## 2. SHIFTS & ROSTER

### 2A. Defects

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| SHF-D1 | P0 | S | **New shift cannot be created (silent no-op).** Draft defaults `overtime_tracking_enabled: true`, `ot_after_minutes: null`; Save returns early with an error shown in a collapsed section. Same early-return for blank break minutes, max-regularization, late-mark values. | `ShiftDefaults.tsx:183-322,347-351,790-792`; defaults in `utils/types.ts` `draftForNewShift`. Fix: sane defaults (OT off, or a prefilled value), scroll/expand to the first error, toast on failure. Also: `start == end` computes `is_night_shift=false` but backend requires `end <= start` → 422 (`shifts/service.py:381-387`). |
| SHF-D2 | P1 | S | **"Shifts this week 556" counts OFF days** (ROSTER-B1: 402 GEN + 154 OFF). | `ShiftScheduling.tsx:161-164` counts any day with a shift id; week-off days keep their shift id (`shifts/service.py:1025-1028`). Count only working days; show OFF separately. **Done 27-Oct-26 (task 259):** the tile now counts `shift_master_id != null && !is_week_off` (live check: 124 cells with a shift became 100 working). |
| SHF-D3 | P1 | M | **Roster `—` for most days, GEN on one day** (ROSTER-B5: 172 empty cells this week). | No auto-assign on employee add (`EmployeeShiftDetail` is only created in `modules/shifts`). Clicking a roster cell for someone with no standing row creates a one-day row (`shifts/service.py:872-886`). Fix: when a day-assign hits an employee with no standing assignment, ask/default to "from this date onward"; show a distinct "No shift" state with a one-click "Assign standing shift"; add data backfill for the 77-of-104 mapped gap. |
| SHF-D4 | P1 | S | **Shift form "inherited" label ≠ backend default.** UI shows full = worked time, half = half of that; backend falls back to fixed **510 / 270 min** (`attendance_recompute_service.py:47-48,404-407`). "Override" sends 0, which backend treats as unset (`OptionalMinutesField.tsx:23`). | Make UI compute the same default (or backend derive from the shift). Fix Override to prefill the inherited value. This is the root of the "4h = full day" confusion. |
| SHF-D5 | P1 | S | **New-shift UI defaults differ from API defaults**: UI draft = flexible, no grace, no regularization/late rule; API = not flexible, grace 0/0 (`utils/types.ts` vs `shifts/schemas.py:22-27`). | Pick one set; show them. |
| SHF-D6 | P2 | S | **"Direct reports 104" label for an org-wide HR view** (ROSTER-B2). | `ShiftScheduling.tsx:225,304`. Rename to "Employees"; empty state "No employees found". |
| SHF-D7 | P2 | S | **Mismatch of General shift config**: min-full-day 4h/half 2h on a 9h shift (ATTSHIFTS-B2). | Data fix + warn in the form when full-day < 50% of shift length. |

### 2B. Gaps

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| SHF-G1 | P0 | M 🗄️ | **HR cannot assign a week-off per employee/date** (notes #5). Week-offs are defined only on the shift (`shift_week_off_details`, whole-set `PUT /shifts/{id}/week-offs`). The roster shows OFF but cannot set it. | Options: (a) per-date `OFF` day row on `employee_shift_details` (existing day-carve logic `_set_employee_shift_for_day`) with a flag; (b) per-employee week-off pattern table. Recommended (a) for ad-hoc days + (b) only if "employee X always off Wed" is needed. Needs DBML. **Status 27-Oct-26 — covered for shift-wide and organisation-wide swaps** (Day swaps: `shift_day_overrides`, tasks 253–260, `docs/leave-and-attendance/shifts/day-overrides.md`): HR can make a date a week off or a working day for every shift or chosen shifts, past dates included, with attendance recalculated. **Still open: per employee** (one person off on one date) — a swap applies to a shift, not a person. |
| SHF-G2 | P0 | M | **DONE (tasks 295–298, 2026-10-28): the roster grid is drag-selectable and bulk-assigns via `PUT /shifts/employee-shifts/cells` (+ `/cells/preview`); week/month/range assign via `PUT /employee-shifts/range` landed earlier — see `docs/leave-and-attendance/shifts/manager-scheduling.md` §4.** Original gap: **No bulk assign for a week/month on the roster** (notes #5, "should be done everyday day-wise"). Backend has `POST /shifts/employee-shifts/bulk` (open-ended from one date, no end date) and `auto-assign` (max 92 days, never called from the UI). UI: directory "Assign shift" + single-cell modal only. | Add to the roster: multi-select employees × date range (week / month / custom), shift + location + week-off pattern, preview of conflicts, apply. Needs an **end date** on the bulk endpoint (`shifts/schemas.py:214`) and range mode. |
| SHF-G3 | P0 | M | **Location is assigned separately from shift and is not visible on the roster** (notes). Location lives on the assignment (`work_location_master_id`), roster API already returns it per day (`schemas.py:269`) but the cell renders only OFF/code/`—`. WFH is not shown anywhere on the roster. | (1) Show a location badge in each cell (+ filter by location). (2) Combine shift + location in one "Assign" form (already one modal; make location required-or-explicit). (3) **Decision (§6 Q3):** should a shift *definition* carry a default location? Recommended: yes, an optional default location on the shift that pre-fills the assignment (🗄️ one nullable FK on `shift_masters`). |
| SHF-G4 | P1 | M | **Auto-assign not exposed.** Task 41 planned an Auto-assign button; it is in `done/` but the roster has none, and task 41 still says `ongoing` and references the removed `ShiftAssignment`/Mark Off design. | Either wire it into the bulk dialog (SHF-G2) or retire. Update task 41's status. |
| SHF-G5 | P1 | M | **No overlap constraint on `employee_shift_details`** (`gaps#20`). Resolver is "latest-effective-wins". | Add an exclusion constraint + friendly error; validate against closed/future rows. |
| SHF-G6 | P2 | M | **Week-off UI supports only whole weekdays** — model supports alternate Saturdays (`week_of_month`) and half-day week-offs (`is_half_day`) but the picker sends neither (`ShiftDefaults.tsx:306-315`). | Add "Every / 1st / 2nd / 3rd / 4th / alternate" and "half-day" options. |
| SHF-G7 | P2 | M | **No-shift fallback is a hardcoded Sat/Sun** week-off in the resolver (`calendar_resolver_service.py:243`). | Make it a tenant setting. |
| SHF-G8 | P2 | L 🗄️ | Shift swap / login swap (`gaps#2`), rotating shift templates, roster publish/approval, "Open shifts" KPI — all NOT-FOUND. | Defer; keep as backlog. |

### 2C. Suggestions

| ID | P | Size | Item |
|---|---|---|---|
| SHF-S1 | P1 | S | Roster legend: GEN / OFF / WFH / `—` = no shift; tooltip on a cell shows shift timing + location. |
| SHF-S2 | P2 | S | Roster header: show who is on which location for the day (counts by location). |
| SHF-S3 | P2 | S | Make the default shift (General) un-deletable and warn when editing a shift that has assigned employees (shows count — task 10 already computes it). |

### 2D. New implementation

| ID | P | Size | Item |
|---|---|---|---|
| SHF-N1 | P1 | L | **Roster v2**: drag-fill / copy-week, "repeat this week for N weeks", paste to selected employees, location + week-off editing in the same grid (covers SHF-G1/G2/G3). |
| SHF-N2 | P2 | M | Rotation templates (e.g. 2 morning / 2 evening / 3 off) applied via the bulk dialog. |

---

## 3. LEAVE

### 3A. Defects

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| LEV-D1 | P0 | M | **Balance bar is misleading** (notes: "this bar is not correct, including total"). "Entitled" = `policy.max_balance` (the *cap*, not the annual entitlement); blank cap → "—" and 0% bar; "Accrued" = `ledger_balance + used` (folds in Opening/CarryForward/Lapse/Encashment/Adjust). Leave-year start hard-coded 1-April in the summary (`modules/leave/service.py:1856`) while rows use their own `reset_month`. | `service.py:1840-1877`; FE `Employee/MyLeave.tsx:539-557`. Fix: Total = annual credit from the rule (or opening + accrued-to-date), Used, Pending, Available as separate numbers; compute the year window per rule; show "accrues from <date>" for unaccrued types. |
| LEV-D2 | P1 | S | **Auto-approve leave doesn't rebuild attendance.** `requires_approval=false` writes Availed rows but never calls `recompute_attendance_day` (only at `service.py:1772,2144,2407,2539`). | Call recompute after the auto-approve write. Add a test. |
| LEV-D3 | P1 | S | **Probation/eligibility message has no date** — "Employee is still in probation for this leave type" (`service.py:870-889`); `applicable_after_days` is ignored when `probation_end_date` is set; not exposed in `MyLeaveRuleOut` (`schemas.py:451-476`). | Return `eligible_from` with the violation and the rule. |
| LEV-D4 | P1 | S | **Seed oddity**: COF `effctv_dt` = 2026-12-08 (future) and SICK 2026-09-18 — `validate_type_in_force` (`service.py:843`) blocks them until then. | Fix seed dates (`seeding/data/new_instance/leave_type_masters.json`). |
| LEV-D5 | P1 | S | **Types exist but no policy rule credits them** (LEAVE-B1). CDP-0 template has 7 types (CL, COF, SICK, EL, ML, PL, LOP) but the Default policy has only a CL rule, so Sick/EL/etc. give "no policy". Task 194 (clone CDP-0 leave+shift defaults) is still ongoing and none of its changes are in this checkout. | Finish 194; add rules for SICK/EL (+ ML/PL gender-gated) to the seed; archive-filter the clone (`admin_organizations/service.py:~924`). |
| LEV-D6 | P2 | S | **Policy wizard start date** (W-LEAVE-7) — not reproduced; see VER-2. |
| LEV-D7 | P2 | S | **Cancelled notification only fires for approved requests** (`service.py:1098-1196`). | Fire for pending too (manager awareness). |

### 3B. Gaps

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| LEV-G1 | P0 | M | **From-date is not limited by eligibility** (notes: "If Earned leave starts after 3 days, From date should be after 3 days"). From `DateField` has no `min` (`MyLeave.tsx:807-813`); only a server message after the fact. | Return `eligible_from` per type in the my-leave rules payload (LEV-D3); set `min` on From; disable dates before it with a helper line "Available from 21-Oct-26". |
| LEV-G2 | P0 | S | **Leave-type selection is not intuitive.** Apply form's type is read-only ("Pick a tile above to change", `MyLeave.tsx:776-787`) by design (task 200). | Add a type dropdown *in the form* that is two-way synced with the tile selection; keep tile → form behaviour. |
| LEV-G3 | P1 | M | **Single approver, no fallback.** No manager → 422; manager without user → 422; no HR second level (`service.py:1040-1068`). Relieved manager strands pending requests (`gaps#42`). | Fallback to HR / department head; reassign-pending on manager change. |
| LEV-G4 | P1 | M | **Back-dated leave hard-coded to 0 days** for employees (`_DEFAULT_MAX_BACKDATED_LEAVE_DAYS = 0`, `service.py:720`). HR can record on behalf, bypassing it. | Tenant/type setting (`gaps#38`). |
| LEV-G5 | P1 | M | **Leave isn't aware of a locked payroll/attendance month** — no check (only ledger locks). Interacts with ATT-N1. | Apply the same period-close rule to apply / approve / cancel / HR-record. |
| LEV-G6 | P1 | M | **HR Manager team leave calendar** (task 157, ongoing, no boxes ticked). | Build as part of the HR dashboard (§5). |
| LEV-G7 | P2 | M 🗄️ | **Comp-off has no earning mechanism** (`gaps#1`); COF exists only as a type. | Per recommendation (a): assembler writes an Accrual row when a holiday/week-off is worked ≥ N minutes + expiry job; or (b) a credit table for exact lot expiry. Hide COF from the dropdown until built. |
| LEV-G8 | P2 | M 🗄️ | **Optional/Restricted holiday quota** (task 186, shelved; `gaps#37`): list N, employee picks M. Not built. | Revive 186 with an opt-in table. |
| LEV-G9 | P2 | M | **Sandwich-leave rules** not expressible (`gaps#13`); `unit = Hour` unsupported (`gaps#14`). | Add rule flag; keep Short Leave for hourly. |
| LEV-G10 | P2 | S | **Self-service encashment** — backend + HR-recorded only; no employee request (`encashment_service.py`). | Optional. |
| LEV-G11 | P2 | S | Approval workflow display vs runtime: Workflow Builder shows 3 stages, runtime is single-step (`gaps#29`). | Hide the extra stages or label as "future". |
| LEV-G12 | P2 | S | Task 160 backfill box unticked (maternity visible to male employee: code fixed, **data backfill outstanding**). | Run the gender backfill. |

### 3C. Suggestions

| ID | P | Size | Item |
|---|---|---|---|
| LEV-S1 | P1 | S | Show the preview/violations panel before the Submit button, with a fix hint (e.g. "Choose a date on/after 21-Oct-26"). |
| LEV-S2 | P2 | S | Leave tiles: show "Accrues monthly · next credit 01-Nov-26"; grey out zero-balance unpaid types (see task 228). |
| LEV-S3 | P2 | S | Duplicate-leave check message should show the conflicting request id/date. |

### 3D. New implementation

| ID | P | Size | Item |
|---|---|---|---|
| LEV-N1 | P1 | M | **Team leave calendar** (HR + manager): month grid, who is off, overlaps, holidays (task 157). |
| LEV-N2 | P2 | L | Comp-off earn + expiry (LEV-G7) and optional-holiday picker (LEV-G8). |
| LEV-N3 | P2 | M | Leave-year/ledger statement export for employee and HR. |

---

## 4. HOLIDAYS

### 4A. Defects

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| HOL-D1 | P1 | S | **"Remote Work" filter shows 0, hiding the 4 org-wide holidays** (HOLIDAYS-B1). | `hrAdmin/HolidayCalendarAdmin.tsx` location filter: a specific location should show *location + org-wide*. |
| HOL-D2 | P0 | M | **Org-wide holidays can be suppressed by a location calendar.** Resolver chain is assignment calendar → location calendar → all-locations calendar, lowest id wins — a **fallback, not a union** (`services/calendar_resolver_service.py:~146-198`). An employee with a location calendar gets only that calendar; national holidays on the org-wide one are lost unless duplicated. | Make resolution a union (org-wide + the employee's location/assigned calendar, de-dupe by date). Add tests; this directly changes attendance Holiday/WeekOff status and leave day counts. |
| HOL-D3 | P1 | S | **Stat cards ignore the type chips; chips behave as hide-toggles.** Clicking "Public" greys it and hides Public rows (HOLIDAYS-B2/B3). | `HolidayCalendarAdmin.tsx:233,496-516,586-589`. Make chips select-to-show, make cards follow the chips, rename "Gazetted" ↔ "Public" consistently. |
| HOL-D4 | P1 | S | **Three copies of the holiday-resolver logic**; the attendance copy doesn't filter archived rows (`attendance/service.py:648-710`, `home/service.py:54-110`, resolver service). | Delete the duplicates; call the resolver. |
| HOL-D5 | P2 | S | `gaps#22/23/30`: calendar carries both `year` and `effctv_dt/trmntn_dt`; one calendar can't hold two holidays on one date; Gazetted vs Public naming. | Decide and document. |

### 4B. Gaps

| ID | P | Size | Item | Evidence / action |
|---|---|---|---|---|
| HOL-G1 | P0 | M | **No year rollover / copy-forward** (HOLIDAYS-B9: 2025 empty, 2027 has 3). New orgs get only current+next year with 3 fixed national holidays (`admin_organizations/service.py:1055-1090`). | "Copy 2026 → 2027" with date shifting and review; reminder banner in December. |
| HOL-G2 | P1 | S | **CSV import has a backend but no UI** (`importHolidaysCsv` defined at `lib/api.ts:1636`, never called; admin only exports). | Add import with a dry-run preview. |
| HOL-G3 | P1 | M | **No view of "who is on which calendar".** Assignment is hidden in `employee_shift_details.holiday_calendar_master_id`; UI shows a location per row. Help text talks about "calendars" but there is no calendar object screen (HOLIDAYS-B9). | Calendar list with assigned-employee count + "assign employees/locations"; show the employee's effective calendar on their profile. |
| HOL-G4 | P2 | M 🗄️ | Restricted/Optional holidays are informational only — no employee opt-in (`gaps#37`, task 186). | See LEV-G8. |
| HOL-G5 | P2 | S | Only **Public** holidays are treated as holidays in attendance/leave (`calendar_resolver_service.py:195,380`). | Document in the legend (ATT-G1). |

### 4C. Suggestions / New

| ID | P | Size | Item |
|---|---|---|---|
| HOL-S1 | P2 | S | State-wise holiday templates are auto-added on work-location save (`state_holiday_service.py`) — surface this in the UI ("Added 14 holidays for Telangana") and allow review. |
| HOL-N1 | P1 | M | Upcoming holidays widget for the HR dashboard (§5). |

---

## 5. HR MANAGER HOME DASHBOARD — new implementation

Notes #7: "No dashboard for HR manager to track/view/approve pending requests". Confirmed: `hrManager/index.tsx` has no home view; `defaultView = "attendance"`. Only an employee-scoped "next holiday" exists (`modules/home/service.py`).

| ID | P | Size | Widget | Data source |
|---|---|---|---|---|
| DSH-N1 | P1 | M | **Pending approvals** — leave requests, regularization requests (with approve/reject inline or deep link) | `modules/leave` approval queue; `modules/attendance` `/requests` (inbox exists) |
| DSH-N2 | P1 | S | **Today**: present / absent / not checked in / on leave / WFH / late | `attendance/dashboard_service.py` summary |
| DSH-N3 | P1 | S | **Attention list**: missing clock-outs, unresolved regularizations, device conflicts | exceptions endpoint already exists (`dashboard_service.py:1015-1043`) |
| DSH-N4 | P2 | S | **On leave today / this week** (+ team leave calendar link) | leave module; LEV-N1 |
| DSH-N5 | P2 | M | **Probation ending** (next 30 days) | `employee.probation_end_date` (no home service yet) |
| DSH-N6 | P2 | S | **Birthdays & work anniversaries** (next 14 days) | employee DOB/joining date — new endpoint |
| DSH-N7 | P2 | S | **Upcoming holidays** (next 30 days, per the HR's own calendar) | resolver service |

Use shimmer skeletons and the 10-px spacing rule (project conventions); gate every endpoint with `RequirePermission`; scope by `principal.tenant_id`.

---

## 6. Decisions needed from you

| # | Question | My recommendation |
|---|---|---|
| Q1 | Late and status rules (ATT-D3): should an Absent or Half-day show "Late"? | Late only on Present/HalfDay; all late counts use present days. |
| Q2 | Same-day status (ATT-G3): keep the "Absent after grace-in" live flag from tasks 179/180? | Show "Not checked in / Late" until day close; stamp Absent only at close. |
| Q3 | Should a shift definition carry a default location (SHF-G3)? | Yes, optional default that pre-fills the assignment. |
| Q4 | Attendance period close (ATT-N1): cutoff = fixed day N of next month, or tied to payroll lock? | Tenant setting `attendance_cutoff_day`, **and** payroll lock overrides; audited HR reopen. |
| Q5 | Week-off per employee (SHF-G1): per-date OFF rows or a per-employee pattern? | Per-date OFF rows first. |
| Q6 | Is Comp-off / Optional-holiday quota in this release? | Defer; hide COF until built. |

## 7. Re-verify before work (could not be reproduced from code)

- **VER-1** W-SHIFTS-5: which endpoint accepted `termination < effective` (validators exist on shift, work-location and assignment paths).
- **VER-2** W-LEAVE-7: policy wizard start date; test typing vs picking in the segmented DateField.
- **VER-3** Week-off bar missing in the attendance graph: need the employee + range.
- **VER-4** Confirm the 30-Sep request was locked by a shift edit (check `is_locked` and the shift's `updated_at`).
- **VER-5** ATTENDANCE-B6 (Absent for B. Nagaraju) after SHF-D3 fix.

## 8. Housekeeping

- Task 41 (`done/`) still says `status: ongoing` and references a removed design; update.
- Tasks 187–192: attendance already uses `department_master_id`; refresh statuses. Free-text `EmployeeMaster.department` is still read in `employees/service.py:163,340,350`, `shifts/service.py:1007`, `roles/service.py:774,783`, `devices/enrollment.py:182`, `devices/router.py:600`.
- `models/employee_attendance_detail.py:70` comment ("never set true") is stale.
- Docs to update when any of the above ships: `docs/leave-and-attendance/{attendance,shifts,leave}/gaps.md` (mark resolved/open).

## 9. Suggested order

1. **P0 quick fixes:** SHF-D1, ATT-D2, ATT-G1 (legend), LEV-G2, LEV-G1 (+LEV-D3).
2. **P0 rules:** HOL-D2 (union), ATT-D1 (stop accidental lock + override), LEV-D1 (balance bar).
3. **P0 roster:** SHF-G1/G2/G3 as one "Roster v2" slice (DBML for week-off first).
4. **P1:** ATT-N1 period close (DBML), HR dashboard (§5), LEV-D5/194, HOL-G1/G2/G3, remaining P1 defects.
5. **P2:** backlog.

Out of scope here (in `issues.csv` but not attendance/shifts/leave/holidays): employees, payroll, roles, forms, hrAttributes, visitors, knowledge, org settings.
