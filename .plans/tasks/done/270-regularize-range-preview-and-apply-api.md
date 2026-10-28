---
task: 270
title: Regularize range — preview and apply endpoints
status: done
depends_on: [269]
---

# 270 — Regularize range — preview and apply endpoints

## Scope
Let HR regularize many days of one employee in one action. No schema change (so no DBML gate): it reuses `attendance_request_details`, `attendance_punch_details`,
`employee_attendance_details` and `attendance_audit_logs` through `_regularize_one` from 269. UI is 271. Single employee only in v1.

Both endpoints go on the attendance router (`backend/app/modules/attendance/router.py`) beside `regularize_on_behalf`, gated by
`RequirePermission("APPROVE", "ATTENDANCE")` (`_APPROVE`) **plus** `sees_whole_org(db, principal, "ATTENDANCE")` (else `PermissionDenied` / 403, like
`regularize_on_behalf`). Employee resolved with `_require_employee_in_tenant` (another tenant's id → 404). Every query filters `principal.tenant_id`.
Use the same router class as the existing JSON attendance endpoints (check whether it is an `EncryptedRoute` and add an encrypted round-trip test if so).

### 1. `POST /api/v1/attendance/employees/{employee_id}/regularize-range/preview` — read-only, writes nothing
Request:
```json
{ "from_date": "2026-10-01", "to_date": "2026-10-31", "mode": "shift", "in_time": null, "out_time": null }
```
`mode` is `"shift"` (present for the scheduled shift) or `"custom"` (`in_time` / `out_time` as `HH:MM`, read in the employee's shift time zone, both required;
a night shift whose OUT < IN rolls to the next morning — reuse the import's rules). `to_date >= from_date`, span ≤ **62 days**, otherwise 422.

Response `200`: `{ employee_id, days: [DayPlan], summary: {regularize, needs_override, skip, blocked} }` with
```
DayPlan = { date, weekday, current: {status, first_in_at, last_out_at, is_locked}, shift_name,
            proposed_in_at, proposed_out_at, action: "regularize"|"skip"|"blocked", code|null, message|null, needs_override }
```
Day classification (evaluate in this order, first match wins):
- `blocked` — `FUTURE_DATE` (judged in the shift's tz), `BEFORE_JOINING` / `AFTER_RELIEVING`, `PAYROLL_CLOSED` (date inside a period from `_closed_periods`; message
  "reopen payroll first"), `NO_SHIFT` (`resolve_effective_shift` is None → message "assign a shift first"), `PENDING_REQUEST` (a Pending Regularization already exists for the date).
- `skip` — `WEEK_OFF`, `HOLIDAY`, `LEAVE` (from the day's existing `employee_attendance_details` `day_type` / status — **confirm the exact column/values before coding**),
  `ALREADY_PRESENT` (Present with both a clock-in and clock-out). Week-offs are NOT tickable in v1 (a worked week-off creates Pending overtime).
- otherwise `regularize` (Absent, missing clock-out, no row yet, etc.). `needs_override = existing row is_locked`.
Every `message` is a ready-to-display plain-English sentence.

### 2. `POST /api/v1/attendance/employees/{employee_id}/regularize-range` — apply
Request:
```json
{ "dates": ["2026-10-01", "2026-10-02"], "mode": "shift", "in_time": null, "out_time": null,
  "reason_code": "Biometric error", "note": "Device down 1-14 Oct, per IT", "override_reason": null }
```
- `dates`: explicit list (1..62, de-duplicated) — the server never expands a range or trusts the preview; it **re-classifies each date at apply time** with the same logic.
- `reason_code` ∈ `REGULARIZATION_REASONS`; `note` required and non-blank (same rule as `HrRegularizationIn`); `override_reason` required only when at least one
  selected date is locked, ≤ 500 chars; a locked date without it comes back `failed` / `LOCKED`.
- Per date, in `db.begin_nested()`: build a `HrRegularizationIn(punch=Both, requested_in_at, requested_out_at, reason_code, note, override_reason)` and call
  `_regularize_one(..., notify=False)`. In `shift` mode pass `raw_extra={"synthesized": True}` for the punches. A date the classifier says is `skip`/`blocked`,
  or that raises `HTTPException`/`PermissionDenied`, is recorded as `failed` (or `skipped`) with its code; the rest still apply. Single `db.commit()` at the end.
- After the loop: exactly **one** `in_app` summary notification to the employee ("HR regularized N days in Oct-26") instead of one per day, and one
  `log_activity` row for the batch (`action_path=".../regularize-range"`, dates, reason, note, `lock_override_reason` when used). Per-day audit rows
  (`RegularizationByHR` / `LockedDayOverride`) already come from `_apply_approved_regularization`.
- Response `200` (also on partial success): `{ applied, skipped, failed, results: [{date, outcome: "applied"|"skipped"|"failed", code, message, request_id, status, payable_day_fraction}] }`.
  HTTP errors only for whole-request problems: 422 bad body / empty or >62 `dates` / missing note, 403 without org-wide scope, 404 other tenant's employee.

### Logging (this repo: stdlib `logging`, `%s` placeholders — see its CLAUDE.md; `structlog` is not installed on this branch)
`logger = logging.getLogger(__name__)`; INFO "Range regularization by HR: tenant=… employee=… applied=… skipped=… failed=…" on completion; WARNING at each guard that refuses a
day or the whole call. Never log the note text or times.

### Out of scope (decisions already taken)
Undo of a range (approved requests have no cancel today — separate task if HR wants it), ticking week-offs, multi-employee selection, a CSV path.

### Findings
(From 269, confirmed 2026-10-27) The single-day paths (`_validate_regularization`, used by both the employee's own request and HR on-behalf) check **none** of payroll-closed,
before-joining or after-relieving; only the WFH path checks joining/relieving (`service.py` ~1794). The range flow adds all three (via `closed_payroll_periods` from
`app/services/attendance_day_helpers.py`, plus the employee's `joining_date` / `relieving_date`). Retrofitting the single-day path is task 273.

## Files
`backend/app/modules/attendance/{router,schemas,service}.py`, `backend/app/tests/modules/test_attendance.py` (or a new `test_attendance_regularize_range.py` using the shared
`conftest.py` fixtures), `backend/app/tests/modules/test_authz.py` for the gate.

## Acceptance criteria
- [x] Preview writes nothing (row counts in requests/punches/attendance/audit tables unchanged after a call)
- [x] Preview classifies: Absent → regularize; missing clock-out → regularize; Present → skip `ALREADY_PRESENT`; week-off/holiday/leave → skip; no shift, future, closed payroll period, before joining, after relieving, pending request → blocked with the right code and message; locked → `needs_override`
- [x] Apply in `shift` mode creates Manual IN/OUT punches at shift start/end with `raw.synthesized = true`, day recomputes to Present with no late/early minutes, `is_regularized` true
- [x] Apply in `custom` mode uses the given clock times in the shift tz (night-shift OUT rolls to next morning)
- [x] Partial success: one bad date does not roll back the others; response lists each date's outcome
- [x] Locked day: without `override_reason` → that date `failed` / `LOCKED`; with it → applied, day stays locked, audit action `LockedDayOverride` carries the reason
- [x] Apply re-validates: a date that became blocked between preview and apply is reported, not written
- [x] 401 without token; 403 for a reporting manager (no org-wide scope) and for a role without APPROVE ATTENDANCE; 404 for another tenant's employee; 422 for >62 days, empty `dates`, blank note, `to_date < from_date`
- [x] Employee receives one summary notification, not one per day
- [x] Encrypted round-trip test (if the router is an `EncryptedRoute`)
- [x] `uv run pytest` green for the touched modules

## As built (2026-10-27)
New module `backend/app/modules/attendance/regularize_range.py` (`preview`, `apply`, shared `_classify`); schemas appended to `attendance/schemas.py`; two routes on the existing
encrypted `router`; `in_app.by_hr_range` (one summary notification); `_regularize_one` from 269 does each day under `db.begin_nested()`. Tests: 34 in the new
`tests/modules/test_attendance_regularize_range.py` + 6 gate cases in `test_authz.py`; the attendance, import, recompute, WFH, authz and roles suites pass (620) except one
failure that also fails on a clean `origin/main` (`test_employee_daily_pagination_matches_my_daily_shape`, extra `remarks` key).

Decisions made while building (for 271's UI and 272's docs):
- `summary.needs_override` is a **subset** of `summary.regularize` (a locked candidate counts in both).
- Extra codes beyond the sketch: `INVALID_TIMES` (custom out not after in on a non-night shift → blocked) and, in apply results only, `LOCKED` (no override reason) and `REJECTED`
  (any other per-day refusal; `message` carries the server's text). Apply maps 423 → `LOCKED`, 409 → `PENDING_REQUEST`, 400 → `NO_SHIFT`.
- "Future" is judged on the UTC date, the same rule `_validate_regularization` applies, so preview and apply cannot disagree.
- Only a **full-day** approved leave skips (`LEAVE`); a half-day leave day stays a candidate. Days with other statuses (HalfDay, short day, no row, no clock-out, lone clock-in) are all candidates.
- A day with a real clock-in and no clock-out gets only a clock-out (`punch=Clock-out`, `proposed_in_at` null); the real IN is kept. Custom mode applies the clock-out time only to such a day.
- Preview needs the same gate as apply (APPROVE ATTENDANCE + org-wide scope) — it exposes other people's attendance.
- Not covered by an automated test: a worked week-off ticked by HR (not offered in v1).

Completed: 2026-10-27
