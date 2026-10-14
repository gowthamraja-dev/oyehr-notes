---
task: 186
title: Optional holidays as a quota'd leave type (list N, employee picks M)
status: shelved
depends_on: []
---

# 186 — Optional holidays as a quota'd leave type (list N, employee picks M)

## Scope

HR lists e.g. 6 optional holidays in the holiday calendar; each employee may take only 2.
Model it as a **leave type with a policy quota**, not a new "selection" table, so the existing
balance, approval, cancellation/reversal, attendance and year-close machinery all apply as-is:

- **The N holidays** = `holiday_details` rows with `holiday_type IN ('Optional','Restricted')`
  (both types already exist, nothing reads them — `calendar_resolver_service.py:195` treats them
  as Working, which is correct: a request on one counts as 1 day).
- **The M quota** = a `leave_policy_details` row for that leave type: `accrual_frequency='Yearly'`,
  `accrual_quantity=2`, `accrual_timing='Pre'`, `reset_month=1`, `carry_forward=false`,
  `encashable=false`. Different groups can get different quotas through the existing provider
  mappings.
- **The employee's choice** = their leave request(s) of that type. No per-employee opt-in table.

**This task adds:** one nullable column to tag the leave type, the date gate on apply, guard
rails on policy save, a self-service "my optional holidays" list, and the admin and employee UI.

**Out of scope:** birthday, anniversary and marriage leaves (they will reuse `date_rule` with new
values in a later task). Changing how Optional/Restricted days are counted in attendance. Picking
holidays up front without a leave request.

**Which clone:** decide when picking this up. Leave work has lived in top-level `hrms/` (see the
memory note). Check both clones' `git status -sb` before starting.

## Design

### 1. Schema — `leave_type_masters.date_rule`
- `date_rule: Mapped[str | None] = mapped_column(String(30))`. Values: `NULL` (no rule, today's
  behaviour) | `'OptionalHoliday'`. Kept as a string, not a boolean, so later occasion rules
  (`'Birthday'`, `'Anniversary'`) extend the same column. Don't key off `code`: codes are set by
  each tenant.
- Additive and nullable, so no backfill. Autogenerate the migration, review it, apply it through
  `uv run python scripts/migrate.py upgrade heads` (never a bare `alembic upgrade head`). Watch
  for the broken-chain note in `leave_request_detail.py`'s docstring.
- Update the `LeaveTypeMaster` docstring to explain the column.

### 2. Shared resolver — no second holiday matcher
`calendar_resolver_service._resolve_holiday` (line ~145) has the calendar fallback chain:
assignment calendar → location calendar → all-locations calendar, lowest id wins. Split it into
`_resolve_calendar(db, tenant_id, target_date, resolved_shift) -> HolidayCalendarMaster | None`
plus the existing Public lookup. Add:

```python
def resolve_optional_holiday(db, tenant_id, employee_id, target_date) -> HolidayDetail | None:
    """The Optional/Restricted holiday on target_date in the employee's resolved calendar."""
```
It filters `holiday_type IN ('Optional','Restricted')` and `archive IS false`, using the same calendar
resolution, so a location-B holiday never counts for a location-A employee.

### 3. Apply gate — `modules/leave/service.py`
Add `validate_optional_holiday_dates(db, tenant_id, employee, leave_type, day_rows, from_half, to_half)`
and call it from `_evaluate_apply_gates` after `day_rows` are built (near the
`max_consecutive_days` check, line ~1352) with code `optional_holiday_date`. The preview endpoint
picks it up automatically. It only applies when `leave_type.date_rule == 'OptionalHoliday'`.
Reject (422, with a `logger.warning` that logs the failing values) when:
- any half-day is requested: "Optional holidays are taken as full days";
- any day row with `day_fraction > 0` is not an Optional/Restricted holiday in the employee's
  resolved calendar: "<date> is not an optional holiday in your calendar";
- every row is 0 (the optional holiday falls on the employee's week-off): "<date> is already a
  week-off for you".

The balance gate (unchanged) enforces "only M". The overlap gate (unchanged) stops a second
request for the same date.

### 4. Policy-save guard rails — `policy_service.py` / `service.py` create/update policy detail
If the detail's leave type has `date_rule='OptionalHoliday'`, reject (422) unless:
- `accrual_frequency == 'Yearly'`, and
- `reset_month == 1`. The default fallback is April (`resolve_leave_year`, line 778), but
  holiday calendars run January–December. With April, the N holidays fall across two leave years
  and an employee could take 2 + 2.

Recommend `prorate_on_joining=false` in the UI hint. Proration gives a mid-year joiner something
like 0.83 days, which can't be used. Hint only, not enforced.

Also reject switching an existing leave type *to* `date_rule='OptionalHoliday'` while it has a
policy detail that breaks the rules above (same message).

### 5. Self-service list — `GET /api/v1/leave/me/optional-holidays?year=`
On the existing encrypted `router` (`EncryptedRoute`, line 66), ungated (the caller's own data),
scoped to `principal.tenant_id` and the caller's own employee. Returns the Optional/Restricted
holidays in the caller's resolved calendar for the year, each with:
`holiday_detail_id, holiday_date, name, holiday_type, leave_type_master_id` (the tenant's active
OptionalHoliday type, or null) `, status: 'Available' | 'Pending' | 'Taken' | 'Past'`. The
status comes from the caller's non-cancelled requests of that type covering the date. Also
returns `quota`, `used`, `remaining` from the existing balance calculation. Read-only; the apply
gate stays the authority.

### 6. Frontend
- `dashboards/hrAdmin/Leave_components/LeaveTypes.tsx`: a "Date rule" select (`None` /
  `Optional holiday only`). When it's set, show the hint: "Set the policy to Yearly, leave year
  starting January, no proration". Add `date_rule` to the leave-type types in `lib/api.ts`.
- `dashboards/Employee/MyLeave.tsx`: when the selected type has `date_rule='OptionalHoliday'`,
  replace the from/to date fields and half-day toggles with a picker listing
  `/leave/me/optional-holidays`. Only `Available` rows are selectable. Show
  "`used` of `quota` used" above it. Submit `from_date = to_date = holiday_date`. Use
  `secureFetch`, a shimmer skeleton from `components/ui/Shimmer.tsx` while loading, and dd-MMM-yy
  dates (`hrms-date-format`).

## Files
- `backend/app/models/leave_type_master.py`: `date_rule` column and docstring
- `backend/alembic/versions/<new>_leave_type_date_rule.py`: autogenerated, then reviewed
- `backend/app/services/calendar_resolver_service.py`: `_resolve_calendar` split, `resolve_optional_holiday`
- `backend/app/modules/leave/schemas.py`: `date_rule: Literal['OptionalHoliday'] | None` on
  `LeaveTypeIn` / `LeaveTypeOut` / the update schema; `MyOptionalHolidaysOut`
- `backend/app/modules/leave/service.py`: create/update leave type, `validate_optional_holiday_dates`,
  the `_evaluate_apply_gates` wiring, `list_my_optional_holidays`
- `backend/app/modules/leave/policy_service.py` (and/or the policy create/update in `service.py`): guard rails
- `backend/app/modules/leave/router.py`: `GET /me/optional-holidays`
- `backend/app/tests/modules/test_leave_optional_holiday.py`: new
- `frontend/src/lib/api.ts`, `frontend/src/dashboards/hrAdmin/Leave_components/LeaveTypes.tsx`,
  `frontend/src/dashboards/Employee/MyLeave.tsx`
- `docs/leave-and-attendance/leave/`: a short section on optional holidays (the config recipe
  and why `reset_month=1`)

## Acceptance criteria
- [ ] Migration adds a nullable `leave_type_masters.date_rule`; it applies cleanly via
      `scripts/migrate.py upgrade heads`. Existing leave types are unaffected (NULL).
      *(2026-10-06: `d8f3b6a91c27` is hand-written and existence-guarded like `c5e2a7d41f93`;
      downgrade/upgrade/re-run verified on a throwaway pg:18. NOT yet applied to shared hrms-dev —
      needs the user's go-ahead; DDL: `ALTER TABLE leave_type_masters ADD COLUMN date_rule varchar(30);`)*
- [x] Leave type create/update round-trips `date_rule`; an unknown value → 422.
- [x] With 6 Optional holidays and a quota of 2: applying on 2 of them succeeds and the 3rd is
      rejected by the balance gate.
- [x] Applying the OH type on a normal working day, or on a **Public** holiday → 422 `optional_holiday_date`.
- [x] An Optional holiday in another location's calendar (not the employee's) → 422.
- [x] An Optional holiday in **another tenant's** calendar → 422 (no cross-tenant leak).
- [x] A half-day request → 422. An Optional holiday falling on the employee's week-off → 422.
- [x] A second request for the same holiday → rejected by the existing overlap gate.
- [x] Cancelling an approved OH request returns the day to the balance, and the date shows `Available` again.
- [x] Leave types without a `date_rule` behave exactly as before (existing leave tests stay green).
- [x] Policy detail save for an OH type with `reset_month != 1` or a non-Yearly frequency → 422.
- [x] `GET /leave/me/optional-holidays`: correct statuses and quota/used/remaining; 401 without a
      token; never returns another tenant's or another employee's data. Encrypted round-trip test
      included.
- [x] Preview (`POST /leave/requests/preview`) lists the `optional_holiday_date` violation.
- [ ] Admin can set the date rule on the Leave Types screen; the employee sees a holiday picker
      for the OH type on My Leave and can apply and cancel from it.
      *(Built; tsc + eslint clean. Browser check not done — the hrms/ API uses shared hrms-dev,
      which doesn't have the column yet.)*
- [x] New code logs INFO on success and WARNING on each guard (stdlib `logging`, `%s` placeholders).
- [x] Doc section added under `docs/leave-and-attendance/leave/`.

## Configuration recipe (for the doc and for smoke-testing)
1. Holiday calendar for the year: add the 6 days with type **Optional**.
2. Leave type: code `OH`, paid, `allow_half_day=false`, `max_consecutive_days=1`,
   `requires_approval` as the org prefers, **Date rule = Optional holiday only**.
3. Policy detail for `OH`: Yearly, quantity 2, Pre, `reset_month=1`, no carry forward, not
   encashable, no proration.

## Build notes (2026-10-06, top-level `hrms/` on `feature/gowtham_AttendanceDateRange`, uncommitted)
- Tests: `app/tests/modules/test_leave_optional_holiday.py` — 24 pass on a throwaway pg:18
  (seeds its own LEAVE_REQUEST status rows). The wider leave/attendance/calendar suites show the
  same 157 pre-existing failures with and without this change (no new failures).
- Also changed beyond the file list: `LeavePolicies.tsx` — adding a rule for an OH type now
  defaults to quantity 2, January, no proration, so the editor doesn't trip the 422.
- The app's own Alembic chain already had two heads (`c3a8e6f1d470`, `c5e2a7d41f93`) before
  this task; the new revision chains off `c5e2a7d41f93` and doesn't merge them.

## Shelved (2026-10-07)
The user chose not to add `leave_type_masters.date_rule` to hrms-dev for now. A read-only check
on 2026-10-07 confirmed the column was never applied there (hrms-dev still stamped
`8012104013b3`), so no drop was needed. Every part of this task hangs off that column, so the
whole change was reverted from `hrms/`. The full change, including the new migration and test
file, is saved as `186-optional-holiday-leave-quota.patch` beside this file. To resume:
`git -C hrms apply .plans/tasks/ongoing/186-optional-holiday-leave-quota.patch`, then add the
column on hrms-dev (`ALTER TABLE leave_type_masters ADD COLUMN date_rule varchar(30);`) before
the API runs the code. No-schema alternatives considered: a tenant setting in
`care_delivery_program_parameter_details`, matching on the leave code, or dropping the date
check. Until then, an "optional holiday" leave can only be a plain 2-day Yearly leave type, with
nothing enforcing the dates.
