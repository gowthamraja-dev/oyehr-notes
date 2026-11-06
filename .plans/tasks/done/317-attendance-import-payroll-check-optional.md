---
task: 317
title: Attendance import — payroll-period check becomes an option (off by default)
status: done
depends_on: []
---

# 317 — Payroll-period check is optional in the attendance import

## Scope
Today a row dated inside a payroll period that is processed / approved / locked is **always rejected** ("…already processed — reopen payroll first")
— `handler.validate_rows`, `closed_payroll_periods(db, tenant_id)` (`services/attendance_day_helpers.py`). For the main use of this import — back-filling
past months when an organisation is **onboarded**, with payroll run in another application — that refusal is noise or a blocker. Make it an option HR chooses,
**off by default**. Paths relative to `workspace-2/hrms/`. Only the attendance import changes; the same wording in `attendance/service.py`, `regularize_range.py`
and `unlock.py` (regularization, range regularization, unlock) is a different feature and stays as it is.

## Behaviour
1. New batch option **`respect_payroll`** (bool, default **false**). Added to `_OPTION_KEYS`, `parse_options` (accepts bool / "true"…, same `_as_bool`), stored in
   `import_batches.options`. Needs no extra scope beyond the existing import CREATE gate (the locked-day override keeps its org-wide scope + reason rule).
2. `validate_rows`:
   * `respect_payroll = true` → exactly today's behaviour (error, row rejected).
   * `respect_payroll = false` → no error. If the day falls inside a closed period, add the **warning**
     `Falls in payroll period 'Sep-26', which is already processed — attendance changes but payroll is not re-run`, so the review screen still shows it.
   Nothing else about the row changes (locked-day rule, shift rule, duplicates, `Skip`/`Merge`/`Update`).
3. Audit: the `attendance_audit_logs` row written at settle gets `new_value.payroll_period_ignored = "<period name>"` for such days (no new action name), so a later
   audit can tell which days were written inside a closed period. `user_activity_details` row at confirm carries the count.
4. Frontend (`ImportAttendance.tsx`, options step): a checkbox **"Refuse days that fall in a processed payroll period"**, unchecked by default, helper text
   "Leave unticked when you are loading history from another system — payroll already run is never re-run." `describeOptions` shows the choice on the confirm
   screen; the History tab shows it for old batches. Optional small preset in the same step, "Loading history for a new organisation", that ticks
   *Include locked days* (HR only) with a pre-filled reason "Onboarding migration" — the reason stays editable and the server rules are unchanged.
5. Wording: error text unchanged when the option is on; the troubleshooting section of `docs/attendance-bulk-import.md` and the "Validation rules" list are updated.

## Decision recorded (flag if you disagree)
The default flips from *refuse* to *allow with a warning*. Anyone running payroll **inside HRMS** must tick the box to keep the old protection. Mitigations: the review
screen lists every such row as a warning, the batch options and audit rows record the choice, and the API default is explicit in the docs. If you would rather keep the old
default for tenants that already have processed periods, the alternative is "default = true only when `closed_payroll_periods` is non-empty" — say so and it is a
one-line change in `parse_options` plus a `context` field on the `parse` response.

## Files
`backend/app/modules/attendance_import/handler.py` (`_OPTION_KEYS`, `parse_options`, the `closed` block in `validate_rows`, audit `new_value` in `_settle_day`),
`frontend/src/dashboards/shared/ImportAttendance.tsx`, `backend/app/tests/modules/test_attendance_import.py`, `docs/attendance-bulk-import.md`.

## Rules
Tenant filter stays on `closed_payroll_periods`. Stdlib `logging`: INFO when a batch is staged with `respect_payroll=false` and rows hit a closed period (count only). No migration.
Tailwind only; no `confirm()`.

## Acceptance criteria
- [x] Default (option omitted / false): a row inside a processed payroll period is `Valid` with the "payroll is not re-run" warning, and confirm writes it (`test_dates_in_a_processed_payroll_period_import_with_a_warning_by_default`, `test_writing_into_a_closed_period_is_audited_and_counted_on_the_confirm_activity_row`)
- [x] `respect_payroll=true`: the same row is `Rejected` with the old sentence
- [x] The existing payroll-refusal test now passes the option explicitly; new tests cover the default, a period that does not cover the day, option parsing (`true`/`yes`/`no`/omitted)
- [x] The audit row for such a day carries `payroll_period_ignored` (also on the punches' `raw`); days outside any closed period are not stamped
- [x] Another tenant's closed period never affects the file (tested with the option on and off)
- [x] The options step shows the checkbox unticked; the confirm screen and History describe the choice — implemented (`ImportAttendance.tsx`: checkbox, `describeOptions`, onboarding preset button), `tsc --noEmit` and eslint exit 0, but NOT seen in a browser (no frontend server was started) — confirmed working in the browser by the user, 2026-11-02
- [x] `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_file_import_engine.py`: 140 passed; ruff clean on the changed modules and tests; `tsc --noEmit` + eslint clean

## Progress (2026-10-30)
Built in `workspace-2/hrms`, NOT committed. Backend: `attendance_import/handler.py` (`respect_payroll` in `_OPTION_KEYS` / `parse_options`, error → warning in `validate_rows`, `parsed.payroll_period`, punch `raw.payroll_period_ignored`,
audit `new_value.payroll_period_ignored`, `stats.payroll_period_rows`, INFO log with a count only, `activity_detail`), `file_import/handlers.py` (new overridable `activity_detail(batch)`, default `{}`), `file_import/lifecycle.py`
(confirm's activity row includes it). Frontend: `dashboards/shared/ImportAttendance.tsx`. Docs: `docs/attendance-bulk-import.md` (options table, validation rules, activity/audit, troubleshooting).
Notes: (1) a batch from before this option has no `respect_payroll` key, and the screen describes it as "refused" — which is what it was; (2) the preset button ("Loading history for a new organisation — use these settings") only
shows to callers with org-wide attendance scope, sets policy Skip, payroll check off, include-locked ON with the reason "Onboarding migration" (kept if HR already typed a reason); the server rules are unchanged;
(3) other payroll refusals (regularization, range regularization, unlock) were deliberately left alone.
Remaining: one look at the options step in a browser, then move to `done/`.

Completed: 2026-11-02
