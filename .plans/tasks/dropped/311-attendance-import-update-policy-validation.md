---
task: 311
title: Attendance import "Update" policy — validation (diff the file against the day)
status: dropped
depends_on: []
---

# 311 — Attendance import `Update` policy: validation

## Scope
Add a third `existing_day_policy`, **`Update`**, and make `validate_rows` classify each row against what the day already holds. Writes
nothing — "Check file" (staging) shows the outcome; task 312 applies it. Paths relative to `workspace-2/hrms/`. Design:
`.plans/attendance-export-reupload-plan.md` (gaps 4–9). `Skip` / `Merge` behave exactly as today. Task 310 (reading the export) is
independent; use a CSV in the tests until it lands.

## Rules for a row under `Update`
Evaluated in this order, inside `AttendanceImportHandler.validate_rows` (after employee/date resolution and the in-file duplicate check):

1. **Diff first, before the closed-payroll and locked checks.** Otherwise untouched rows on locked days / processed payroll periods are
   rejected and flood the review screen.
2. Load, per chunk and in one tenant-filtered query (no N+1), each pair's **active** punches (`archive = false`, tenant filter,
   attached to the day's `employee_attendance_details` row) → current `first_in` / `last_out`.
3. **Day has punches, row has times** — new pair = (file In or current In, file Out or current Out): a blank cell means "keep the current
   value" (a file cannot delete a punch). Compare to the **minute** in the employee's shift zone (`resolve_timezone(resolved_shift)`).
   * equal → `Skipped`, warning `Unchanged`;
   * different → continue to the normal checks (closed payroll, locked + override, future, in ≠ out, night-shift next-day OUT, ≥ 60 s apart)
     and become `Valid` with warning `Changes 09:05–18:10 → 09:30–18:10`.
4. **Day has punches, row has no times at all** → `Skipped`, warning `No times in the file — day left as it is`. **Never** synthesise
   "present for the shift" here (`_resolve_times` would). If the Status text is a skip kind (Absent / Leave / Week off / Holiday) while the
   day currently has punches, the warning says `Status change not imported — use regularization or leave`.
5. **Day has no punches** → today's behaviour (new punches; no times + skip status → skipped; no times + no status → present for shift).
6. **Times given + a skip Status** (HR typed times onto an `Absent` row) → the times win, warning `Status says Absent but times were
   given — the times are imported`. This precedence applies only under `Update`; `Skip`/`Merge` keep "Status skips the row".
7. **Time zone parity** — the daily log writes `Clock In/Out` in `scoped.time_zone` (work-location zone); the importer reads in the shift
   zone. Find where they can differ and make the comparison use the same zone the export used (resolve it the same way
   `attendance_export/data.py` does), or prove they are always equal. The "untouched export = all Skipped" test below decides.

`parsed` for a changing row gains `{"update": true, "expected": {"first_in": iso|null, "last_out": iso|null}, "before": {...}, "after": {...}}`
(UTC ISO instants; `expected` is what validation saw — task 312 re-checks it at commit). `validate_rows` increments
`batch.stats["unchanged"]` / `["to_update"]` (the engine commits per chunk, so resume does not double count).

`parse_options`: accept `Update`; reject anything else with the existing 422 text updated to list three values. `override_locked` /
`override_reason` rules are unchanged and apply to changed rows only.

## Files
`backend/app/modules/attendance_import/handler.py` (`EXISTING_DAY_POLICIES`, `parse_options`, `validate_rows`, `_resolve_times` caller),
`backend/app/modules/attendance_import/parsing.py` (if a skip-with-times helper is needed), `backend/app/tests/modules/test_attendance_import.py`.

## Rules
Scope every query by `batch.care_delivery_program_master_id`. Stdlib `logging` (WARNING where a guard rejects). No migration.

## Acceptance criteria
- [ ] `existing_day_policy=Update` is accepted; an unknown policy is still a 422
- [ ] A row identical to the day (to the minute) is `Skipped` "Unchanged" — including on a **locked** day and inside a **processed payroll period** (no error)
- [ ] A row with an edited In and/or Out is `Valid` with a before → after warning; blank In or Out keeps the current side
- [ ] An edited row on a locked day is rejected without `override_locked` and valid with it + reason; in a processed payroll period it is still rejected
- [ ] A punched day with blank times is `Skipped` and is never turned into shift times; a skip Status on such a day adds the "not imported" hint
- [ ] Times typed onto an `Absent`/no-punch day under `Update` are `Valid` with the "times win" warning; under `Skip` the same row is still skipped by Status
- [ ] Untouched round trip: stage a day set, build the daily log with the real exporter, stage it back under `Update` → every row `Skipped`, zero `Valid` (covers time-zone parity, minute precision, night shifts)
- [ ] `stats.unchanged` / `stats.to_update` are correct after validation, and still correct after a simulated resume
- [ ] Cross-tenant: an Employee ID from another CDP is rejected as before
- [ ] `uv run pytest app/tests/modules/test_attendance_import.py` green

Dropped: 2026-11-02 — not started; shelved by the user ("leave it for now"). Moved out of `ongoing/` rather than deleted; move it back to restart. Design: `.plans/attendance-export-reupload-plan.md`.
