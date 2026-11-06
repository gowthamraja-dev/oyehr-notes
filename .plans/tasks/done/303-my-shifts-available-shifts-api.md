---
task: 303
title: My Shifts — available shifts for a shift change request API
status: done
depends_on: []
---

# 303 — My Shifts: available shifts API

## Scope
`GET /api/v1/shifts/me/available?date=YYYY-MM-DD` — the options for the "Requested Shift" dropdown
on the mobile Request Shift Change form (one date; see `.plans/my-shifts-mockup.jpeg`). Self-service, **ungated**, encrypted `/shifts` router,
read-only, no schema change.

Not covered: submitting/listing/cancelling requests (tasks after schema approval).

### Contract
Response `MyAvailableShiftsOut { date, current_shift, shifts: list[AvailableShiftOut] }`; each shift: `shift_master_id`, `name`, `code`, `color`, `start_time`,
`end_time`, `is_night_shift`, `is_current` (the employee is already on this shift on that date). The
response also carries the caller's `current_shift` for the date (the form's read-only "Current Shift" box),
null when unassigned. Ordered by `start_time`, then `name`.

Rules (proposal — confirm with schema open question 3):
- Tenant's shifts only: `care_delivery_program_master_id == principal.tenant_id`, `is_active`,
  not `archive`, and the shift's `effctv_dt`/`trmntn_dt` window covers the date.
- Include the current shift but flag it `is_current = true` (the form disables it) — do not silently
  omit, so the list matches what the employee sees on the calendar.
- Date validation: not in the past → 422 (today is allowed — the form defaults to today; the submit task
  owns the "already punched in today" refusal, not this read).
- Current shift comes from `resolve_effective_shift` (the shared resolver); don't re-query assignments.
- No per-employee allow-list exists; don't invent one.

## Files
- `backend/app/modules/shifts/schemas.py` — `AvailableShiftOut`.
- `backend/app/modules/shifts/service.py` — `list_my_available_shifts`.
- `backend/app/modules/shifts/router.py` — register before `/me/{target_date}`.
- `backend/app/tests/modules/test_my_shifts.py`.
- Endpoint catalogue in `hrms-mobile-api-integration` skill + `docs/leave-and-attendance/shifts/api-and-pages.md`.

## Acceptance criteria
- [x] Lists only live shifts of the caller's tenant whose window covers the date
- [x] Archived / inactive / expired / other-tenant shifts never appear
- [x] `is_current` true only for the shift already assigned on that date
- [x] Past date → 422; today allowed
- [ ] Encrypted round-trip; tenant-scoping test
- [x] Route does not shadow `/me/{target_date}`

## Progress (2026-10-29)
Built in `workspace-2/hrms` on `feature/gowtham_shift_grid_bulk`, NOT committed. Tests: `backend/app/tests/modules/test_my_shifts.py` (47 pass against the local `hrms-test-pg`). API only — not exercised from the mobile app or a browser.
Tenant scoping is tested (another tenant's shift never listed, archived / inactive / expired / not-yet-effective excluded). No encrypted round-trip test for this GET specifically.

Completed: 2026-10-29
