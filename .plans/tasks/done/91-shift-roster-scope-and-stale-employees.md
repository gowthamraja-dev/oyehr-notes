---
task: 91
title: Shift roster — relieved/inactive direct reports never drop off
status: done
depends_on: []
---

# 91 — Shift roster — relieved/inactive direct reports never drop off

## Scope

Two related logic bugs in `list_shift_roster` (`backend/app/modules/shifts/service.py:772-821`),
which backs the HR Manager "Weekly roster" grid
(`frontend/src/dashboards/hrManager/ShiftScheduling.tsx`, via `GET /shifts/employee-shifts/roster`).
That page's own copy says "Direct reports" (stat tile, line 198) and "No direct reports found
for your account" (line 278) — the data it actually gets does not honor that framing in two ways:

**1. `principal.is_admin` bypasses manager scoping entirely — matches convention, but had no
`relieving_date` bound either.**
```python
if principal.is_admin:
    query = (
        select(EmployeeMaster)
        .join(CorpMaster, EmployeeMaster.corp_master_id == CorpMaster.id)
        .where(
            CorpMaster.care_delivery_program_master_id == principal.tenant_id,
            EmployeeMaster.is_active.is_(True),
        )
    )
else:
    caller = _require_caller_employee(db, principal)
    query = select(EmployeeMaster).where(EmployeeMaster.reporting_manager_id == caller.id)
```
`ShiftScheduling.tsx` is only mounted in the HR Manager dashboard
(`frontend/src/dashboards/hrManager/index.tsx:80`), so on that specific page any `is_admin=true`
caller sees the whole tenant while the UI still labels it "Direct reports" — worth noting, but
**not changed by this task**: `is_admin` unrestricted-access is the load-bearing, consistently
applied convention across this entire module (`_require_manager_or_admin`'s docstring: "Admin:
unrestricted"; same pattern in `assign_employee_shift`, `update_employee_shift`,
`list_employee_shifts`, `_resolve_auto_assign_employees`), and the existing test suite already
depends on admin being able to inspect *any* employee's roster regardless of reporting line
(`test_list_shift_roster_admin_scope_and_shape`, the `_resolve_via_roster` helper used by
several `set_employee_shift_for_day` tests). Special-casing this one endpoint to strip that
would contradict the rest of the module and require rewriting already-correct tests to work
around a design choice, not a bug. What actually was a bug in this branch: it filtered
`is_active` but not `relieving_date`, so an employee mid-notice-period was not excluded —
fixed below alongside the manager branch's filter.

**2. Neither branch filters out relieved/deactivated direct reports — the actual bug.**
The `else` branch (the manager path, hit by every non-admin user — the only caller
`ShiftScheduling.tsx` actually exercises) has no `is_active` or `relieving_date` filter at all —
an employee who left the company but still has `reporting_manager_id == caller.id` keeps
appearing on the roster forever, fully editable, indistinguishable from a current report. Over
time this is what makes "my team" on this page balloon into "basically everyone who ever
reported to me" — this is the "it just lists all the employees" symptom for an ordinary
(non-admin) manager, which is what the page is actually for.

`_resolve_auto_assign_employees` (`service.py:824-852`) and `list_team_employee_shifts`
(`service.py:591-631`) have the same `reporting_manager_id == caller.id` query with the same
missing `is_active`/`relieving_date` filter — fix all three call sites the same way so the
"which of my reports are current" rule isn't defined three different times.

**Out of scope**: `list_shift_roster`'s `department`/`role` query filters, and the frontend
grouping UI — those are unaffected by this bug.

## Changes

**1. `backend/app/modules/shifts/service.py`** — add a shared helper (near `_require_caller_employee`,
~line 102) rather than repeating the filter three times:
```python
def _active_direct_reports_query(caller_id: int):
    return select(EmployeeMaster).where(
        EmployeeMaster.reporting_manager_id == caller_id,
        EmployeeMaster.is_active.is_(True),
        or_(EmployeeMaster.relieving_date.is_(None), EmployeeMaster.relieving_date > date.today()),
    )
```
Use it in the `else` branch of `list_shift_roster` (line 789), in
`_resolve_auto_assign_employees`'s manager branch (line 848-852, and its single-employee lookup
at 843-847 should also reject a relieved report, not just "not your direct report"), and in
`list_team_employee_shifts` (line 599-607). Apply the same `relieving_date` bound to the
`is_admin` branches at lines 778-786 and 829-840 (they already filter `is_active`, just add the
`relieving_date` half) so admin and manager scoping agree on what "current" means.

**2. `is_admin` branch: kept, not removed.** Add the same `relieving_date` bound used in
`_active_direct_reports_query` (so a still-`is_active` employee whose notice period is running
also drops off admin's view once `relieving_date <= today`) — otherwise unchanged. If a
manager-only view of this endpoint is ever wanted (i.e. `ShiftScheduling.tsx`'s "Direct reports"
copy should be literally true even for an `is_admin` caller), that's a frontend/product decision
about what the HR Manager dashboard should show an admin-flagged user, not a backend scoping bug
— out of scope here.

## Files
- `backend/app/modules/shifts/service.py`
- `backend/app/tests/modules/test_shifts.py`

## Tests
`backend/app/tests/modules/test_shifts.py`:
- A direct report with `is_active=False` (or `relieving_date` in the past) does not appear in
  `list_shift_roster` for the manager they report to, `list_team_employee_shifts`, or as an
  auto-assign target (`POST /shifts/employee-shifts/auto-assign` with no explicit
  `employee_master_id`).
- Explicitly targeting a relieved employee's id in auto-assign (`employee_master_id` param) is
  rejected the same way targeting a non-report is rejected today.
- An `is_admin` caller's `list_shift_roster` result also excludes an employee whose
  `relieving_date` has passed (the admin branch's new bound), while an employee whose
  `relieving_date` is in the future (still serving notice) still appears.

## Acceptance criteria
- [ ] Relieved/inactive direct reports are excluded from the manager-scoped roster, the
      team-shifts list, and auto-assign's implicit employee set, via one shared query helper
      (`_active_direct_reports_query`, not three separate copies of the filter).
- [ ] The admin branch of `list_shift_roster` and of `_resolve_auto_assign_employees`'s
      whole-tenant listing also excludes employees past their `relieving_date`, matching the
      manager branch's definition of "current."
- [ ] The `is_admin` unrestricted-access convention itself is preserved (not removed) — admin can
      still explicitly target any employee by id, and existing admin-scoped roster tests continue
      to pass unchanged.
- [ ] `uv run pytest app/tests/modules/test_shifts.py -q` passes, including the new cases above.

Completed: 2026-09-02
