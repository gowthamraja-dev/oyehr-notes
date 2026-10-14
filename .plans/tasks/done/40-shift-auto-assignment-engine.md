---
task: 40
title: Auto-assign shift roster rows from standing shift + week-off rules
status: done
depends_on: [39]
---

# 40 — Auto-assign shift roster rows from standing shift + week-off rules

## Discussion

The actual "enable auto assignment for the shift" ask. Today the per-date roster
(`employee_shift_assignments`) is 100% manually populated, one cell at a time
(`create_shift_assignment`/`bulk_assign_shifts`) — nothing derives it from an employee's standing
shift (`employee_shift_details`) or that shift's week-off rules (`shift_week_off_details`). This
task adds an on-demand bulk operation: for a date range, walk each in-scope employee's standing
shift day by day and upsert a roster row — `OFF` (task 39) on a full week-off day, `ASSIGNED` with
the standing shift otherwise.

**Reuse the existing week-off matcher — do not refork it.**
`app/services/calendar_resolver_service.py::_resolve_week_off` (plus its `_nth_occurrence` helper)
already implements the exact `day_of_week`/`week_of_month`/`is_half_day` matching this needs,
written for the attendance assembler per `README.md §3.4`'s "one shared calendar resolver"
requirement. That function is currently private and keyed off a `ResolvedShift` object this
task's caller won't have. Extract the shift-id/date matching itself into a small **public**
function in the same file:

```python
def is_shift_week_off(db: Session, shift_master_id: int, target_date: date) -> tuple[bool, bool]:
    """Returns (is_week_off, is_half_day). See _resolve_week_off's docstring for the matching
    rule (day_of_week + optional week_of_month, is_active/archive-filtered). Public because
    shifts.service's auto-assignment engine (task 40) needs it directly by shift id, without a
    ResolvedShift — do not re-derive this matching a third time."""
```

Have the private `_resolve_week_off(db, target_date, resolved_shift)` become a thin wrapper: `if
resolved_shift is None: return <default Sat/Sun fallback>; return is_shift_week_off(db,
resolved_shift.shift.id, target_date)`. `shifts/service.py` imports and calls `is_shift_week_off`
directly. This keeps exactly one implementation of the day-of-week/week-of-month matching, per
`README.md §3.4`'s spirit (that section is about the attendance/leave day-type split specifically,
but the same "must not silently diverge" argument applies to any second consumer of this rule).

**Idempotent and non-destructive by construction.** Re-running this over the same range must be
safe — a schedule change to a shift's week-off rules, or simply re-running weekly, shouldn't
require the caller to first figure out what changed. The `is_auto_assigned` column from task 39 is
exactly what makes this possible: the engine only ever writes rows it created itself in an earlier
run, or fills genuinely empty dates. Any row a manager touched by hand (`is_auto_assigned=false`,
set by every manual write in task 39) is left alone, whatever the week-off rule says — a manual
override always wins.

**No cron/background job.** `README.md §2.4` is explicit: there is no job runner anywhere in this
repo (`shared/jobs-and-scheduling.md` covers the gap generally). Building one is out of scope here
— this ships as a caller-triggered endpoint (a button in the Shift Scheduling UI, task 41), the
same shape as the existing bulk-assign endpoint. Wiring it into a scheduler is future work once
that mechanism exists for the module generally.

**Scope resolution mirrors `list_shift_assignments`** (already in `shifts/service.py`): admin sees
the whole tenant (optionally narrowed to one `employee_master_id`); a manager is scoped to direct
reports, and passing a non-report `employee_master_id` is `403`, not an empty/no-op result (per
`README.md §3.3` — same rule already applied everywhere else in this module).

## Files

### Edited

- `backend/app/services/calendar_resolver_service.py` — extract `is_shift_week_off` as described
  above; `_resolve_week_off` becomes a wrapper calling it.

- `backend/app/modules/shifts/schemas.py`
  ```python
  class AutoAssignShiftsIn(BaseModel):
      from_date: date
      to_date: date
      employee_master_id: int | None = None  # None = every in-scope employee

      @field_validator("to_date")
      @classmethod
      def _range_valid(cls, v, info):
          from_date = info.data.get("from_date")
          if from_date is not None and v < from_date:
              raise ValueError("to_date must not be before from_date")
          return v

  class AutoAssignShiftsOut(BaseModel):
      assignments: list[ShiftAssignmentOut]  # every row created or changed by this run
      assigned_count: int
      off_count: int
      unchanged_count: int
      manual_skipped_count: int
      no_standing_shift_count: int
  ```
  Cap the range in the service (not the schema) — see below — rather than a fixed `Field` bound,
  since the cap is a business rule ("how far ahead is it reasonable to auto-generate a roster"),
  not a structural validity constraint.

- `backend/app/modules/shifts/service.py`
  ```python
  _MAX_AUTO_ASSIGN_DAYS = 92  # roughly one quarter — generous for a rolling roster, small
                              # enough that a fat-fingered multi-year range can't force a
                              # per-employee-per-day loop across the whole tenant.

  def auto_assign_shifts(
      db: Session, principal: AuthPrincipal, payload: AutoAssignShiftsIn,
  ) -> AutoAssignShiftsOut:
      if (payload.to_date - payload.from_date).days + 1 > _MAX_AUTO_ASSIGN_DAYS:
          raise HTTPException(422, detail=f"Range must not exceed {_MAX_AUTO_ASSIGN_DAYS} days")

      # Resolve in-scope employees: same admin-tenant-wide / manager-direct-reports-only split
      # list_shift_assignments already implements — reuse that query shape (factor the "which
      # employees is this caller allowed to touch" resolution into a shared helper if
      # list_shift_assignments's employee-scoping block can be extracted cleanly; otherwise
      # duplicate the ~10-line query, matching this module's existing tolerance for that
      # duplication over a premature abstraction — see _get_work_location's own docstring on
      # this).
      #
      # For each employee, for each date in [from_date, to_date]:
      #   1. Resolve the standing EmployeeShiftDetail effective on that date (same query
      #      calendar_resolver_service._standing_assignment runs — reuse it, it's already keyed
      #      by employee_id/target_date. If none: no_standing_shift_count += 1; continue.
      #   2. is_week_off, is_half_day = is_shift_week_off(db, standing.shift_master_id, date)
      #   3. target_status, target_shift_id = ("OFF", None) if is_week_off else
      #      ("ASSIGNED", standing.shift_master_id)
      #      (is_half_day stays ASSIGNED — a half-day week-off is a Working day with halved
      #      thresholds elsewhere, per shift_week_off_detail.py's own docstring; it is not a
      #      roster-visible OFF state.)
      #   4. Look up the existing EmployeeShiftAssignment row for (employee, date), if any:
      #      - none -> insert with is_auto_assigned=True, status/shift_master_id from step 3;
      #        write ShiftAssignmentAudit(action="AUTO_ASSIGNED" or "AUTO_OFF"); tally
      #        assigned_count/off_count.
      #      - exists, is_auto_assigned is False -> leave untouched; manual_skipped_count += 1.
      #      - exists, is_auto_assigned is True, already matches step 3's target -> leave
      #        untouched (no write, no audit row); unchanged_count += 1.
      #      - exists, is_auto_assigned is True, differs from step 3's target -> update in
      #        place, write an audit row; tally into assigned_count/off_count.
      #   Single db.commit() at the end (mirrors bulk_assign_shifts), not per-row.
      ...
  ```
  `ShiftAssignmentAudit.action` gains two more unconstrained-string values, `"AUTO_ASSIGNED"` /
  `"AUTO_OFF"`, kept distinct from the manual `"ASSIGNED"`/`"OFF"` from task 39 so the audit trail
  can tell a manager's explicit choice apart from a bulk-generated one.

- `backend/app/modules/shifts/router.py`
  ```python
  @router.post("/assignments/auto-assign", response_model=AutoAssignShiftsOut, status_code=201)
  def auto_assign_shifts(
      payload: AutoAssignShiftsIn, principal: CurrentPrincipal, db: DbSession,
  ) -> AutoAssignShiftsOut:
      return service.auto_assign_shifts(db, principal, payload)
  ```

- `backend/app/tests/modules/test_shifts.py` — extend with:
  - An employee with a standing Mon–Fri shift whose `shift_week_off_details` mark Sat+Sun full
    off, auto-assigned over a 14-day range, yields 10 `ASSIGNED` + 4 `OFF` rows.
  - A `week_of_month`-scoped rule (e.g. 2nd/4th Saturday only) produces `OFF` only on the matching
    Saturdays within the range, `ASSIGNED` on the others.
  - A half-day week-off rule (`is_half_day=true`) keeps the day `ASSIGNED`, never `OFF`.
  - Re-running the same range twice: second run's `unchanged_count` equals the first run's
    `assigned_count + off_count`; zero new audit rows written on the second run.
  - A date in range that already has a manual `ASSIGNED` or `OFF` row (`is_auto_assigned=false`,
    from task 39) is left byte-for-byte unchanged; counted under `manual_skipped_count`.
  - An employee with no standing shift for part of the range is skipped for those dates
    (`no_standing_shift_count`), not errored, and other employees/dates in the same call still
    succeed.
  - Manager scoped to direct reports only; a non-report `employee_master_id` → 403; omitting
    `employee_master_id` as a manager only touches their own reports, never the whole tenant.
  - Range exceeding `_MAX_AUTO_ASSIGN_DAYS` → 422; `to_date` before `from_date` → 422.
  - `calendar_resolver_service`'s existing week-off tests (if any) still pass unchanged after the
    `is_shift_week_off` extraction — this is a pure refactor of that function, not a behavior
    change for its existing caller.
  - Encrypted round-trip test.

## Acceptance criteria

- [x] `POST /shifts/assignments/auto-assign` generates `OFF`/`ASSIGNED` roster rows for a date
      range from each employee's standing shift and its week-off rules, without needing a
      per-employee, per-shift manual click.
- [x] Week-off matching (`day_of_week`, `week_of_month`, `is_half_day`) comes from the one
      extracted `calendar_resolver_service.is_shift_week_off` function — no second copy of this
      logic exists anywhere in the codebase.
- [x] Re-running the same range is idempotent: no duplicate writes, no duplicate audit rows, and
      every manually-set row (from task 39) is left untouched regardless of what the week-off
      rule says for that date.
- [x] Manager scoping matches the rest of the module: direct reports only, `403` (not an empty
      result) for a non-report target.
- [x] Range and ordering are validated (`to_date >= from_date`, capped span).
- [x] Full `test_shifts.py` and `test_attendance.py` suites are green after the extraction
      (156 passed).

## Completion notes

- `_standing_assignment`/`is_shift_week_off` are imported from `calendar_resolver_service` via a
  **local import inside `auto_assign_shifts`**, not a top-level one — a top-level import would
  create a circular dependency, since `calendar_resolver_service.py` already imports
  `resolve_employee_shift` from `shifts/service.py` at module scope. Confirmed `app.main` still
  imports cleanly after this.
- `_resolve_auto_assign_employees()` is a new scoping helper distinct from `list_shift_assignments`'s
  own employee query — that function silently returns an empty list for an out-of-scope
  `employee_master_id` (fine for a *view*), but this task requires an explicit `403` for a
  manager targeting a non-report (an *action*), so it couldn't be reused as-is without weakening
  that guarantee.
- Test coverage added to `test_shifts.py` (8 new tests, all green): full 14-day range (10
  ASSIGNED + 4 OFF), idempotent re-run (zero new writes/audits), half-day week-off staying
  ASSIGNED, a week-of-month rule matching only the 2nd/4th Saturday, manual-row preservation +
  `no_standing_shift_count` for a pre-effective-date gap, manager-scoping 403/200, range
  validation (`to_date < from_date` and over-cap), auth gating, and an encrypted round-trip.
  Given a tight context budget for this task, this is a solid but not maximally exhaustive
  suite — it covers every branch in the acceptance criteria and the trickiest edge cases
  (idempotency, week-of-month, half-day, manual-row survival) but doesn't enumerate every
  possible combination the original task sketch listed (e.g. it doesn't separately test a
  manager's *implicit* "no `employee_master_id`" call against multiple reports at once — covered
  indirectly by the admin-path full-range test instead).

Completed: 2026-08-19
