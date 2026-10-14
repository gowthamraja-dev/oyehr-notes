---
task: 53
title: Employee directory — filter metadata and Headcount/Role/Organization aggregate APIs
status: done
depends_on: []
---

# 53 — Employee directory — filter metadata and Headcount/Role/Organization aggregate APIs

## Discussion

The design prompt's filter drawer and its Headcount/Role/Organization tabs (§13 "Directory
metadata", §14–§16) need reference-data and aggregate endpoints that don't exist anywhere today.
Checked and ruled out as existing sources: `hr_attributes` module is for tenant-defined custom
attribute mappings (unrelated); `master_data` module only serves the nhforms builder's parameter
catalogue (unrelated). There is no `department_master` table — `EmployeeMaster.department` is a
free-text `String(120)` column (confirmed in `backend/app/models/employee_master.py`) — so
"departments" here means **distinct values actually present in the data**, not rows from a
reference table, matching the design prompt's "do not invent fields merely because they appear
in a mockup" rule.

All five endpoints below are CDP-scoped exactly like `list_employees` — join `EmployeeMaster` →
`CorpMaster` → filter `CorpMaster.care_delivery_program_master_id == principal.tenant_id`. Add
them to the existing `employees` router (`prefix="/employees"`, already `EncryptedRoute`) as new
paths, not a new router — this is directory reference data for the same resource.

### `GET /employees/departments` → `list[DepartmentOption]`

`DepartmentOption { name: str, employee_count: int }`. `SELECT department, count(*) ... GROUP BY
department` scoped to the CDP, `department IS NOT NULL`, ordered by name. This replaces
`shared/EmployeeDirectory.tsx`'s current client-side department-count `useMemo` (see
[[57-manager-directory-employees-tab-frontend]]) — that logic only works because it derives
counts from an already-fully-loaded list, which task 52 makes impossible (paginated results).

### `GET /employees/employment-statuses` → `list[str]`

Distinct non-null `EmployeeMaster.employment_status` values present in the CDP, sorted. Purely
for populating the filter dropdown — the actual filter/enforcement lives in [[52]].

### `GET /employees/reporting-managers` → `list[ManagerOption]`

`ManagerOption { id: int, name: str, designation: str | None }` — every employee in the CDP who
has at least one direct report (`EXISTS (SELECT 1 FROM employee_masters r WHERE
r.reporting_manager_id = employee_masters.id)`), for the filter dropdown and any "reports to"
picker. Do not return every employee in the CDP as a candidate manager — that list can be large
and most employees have no reports.

### `GET /employees/headcount` → `HeadcountOut`

Design prompt §14. Shape:

```json
{
  "total": 0,
  "active": 0,
  "inactive": 0,
  "on_leave": 0,
  "by_department": [ { "department": "Engineering", "count": 0, "share": 0.0 } ]
}
```

`active`/`inactive`/`on_leave` reuse the exact same predicates as [[52]]'s `status` filter (the
"On Leave" `EXISTS` against `leave_request_details` — do not duplicate that predicate as a
second hand-written copy; factor it into a small shared helper both `list_employees` and this
endpoint call, e.g. `_on_leave_today_subquery()` in `service.py`). `share` is `count / total`
(0.0 when `total == 0`, not a `ZeroDivisionError`). This is a live query, not a cached/
precomputed figure — the design prompt explicitly forbids hardcoding the mockup's `812` value
except as demo/seed data.

### `GET /employees/roles` → `list[RoleAggregateOut]`

Design prompt §15. `RoleAggregateOut { designation: str, employee_count: int, active_count: int
}`. Group by `EmployeeMaster.designation` (also free-text — no `designation_master` table
exists either, same reasoning as department) within the CDP, `designation IS NOT NULL`. **Do
not** add an "open/vacant positions" field — the prompt explicitly says only include it "if
backed by recruitment/position data," and no recruitment/position model exists in this codebase
to back it.

### `GET /employees/organization` → `OrganizationNodeOut`

Design prompt §16. A tree rooted at whichever employees in the CDP have `reporting_manager_id IS
NULL` (or point outside the CDP, which shouldn't happen but treat defensively as a root rather
than raising). Shape:

```json
{ "id": 1, "name": "…", "designation": "…", "department": "…", "direct_report_count": 0,
  "reports": [ /* same shape, recursive */ ] }
```

Build this as one query fetching every `(id, name-parts, designation, department,
reporting_manager_id)` row for the CDP, then assemble the tree in Python (a CDP's employee count
is small enough that N+1 recursive queries would be wasteful and a single fetch + in-memory
grouping by `reporting_manager_id` is both simpler and cheaper). Cap recursion depth defensively
at, say, 20 levels and break cycles (a `reporting_manager_id` cycle is bad data, not something
that should hang the request) — track visited ids while walking down.

## Files

- `backend/app/modules/employees/router.py` — five new `GET` routes
- `backend/app/modules/employees/schemas.py` — `DepartmentOption`, `ManagerOption`,
  `HeadcountOut`, `DepartmentHeadcountOut`, `RoleAggregateOut`, `OrganizationNodeOut`
- `backend/app/modules/employees/service.py` — five new functions, plus the shared
  `_on_leave_today_subquery()` helper referenced by [[52]] (coordinate: whichever of [[52]]/[[53]]
  lands first adds the helper, the other reuses it)

## Tests (extend `backend/app/tests/modules/test_employees.py`)

- `departments`: counts match seeded data; an employee with `department=None` isn't counted
  under any bucket.
- `employment-statuses`: distinct values only, sorted, CDP-scoped.
- `reporting-managers`: only appears for an employee that actually has ≥1 report; an employee
  with zero reports is absent even if they have a `designation`/are otherwise a manager by title.
- `headcount`: `active + inactive == total`; `on_leave` employee also counted in `active`, not
  double-subtracted; `share` sums to ~1.0 across `by_department` (allow float tolerance); `total
  == 0` returns `share: 0.0` for every bucket, not a 500.
- `roles`: grouping and counts correct; no `open_positions`-shaped field anywhere in the response.
- `organization`: a 3-level chain (root → manager → report) nests correctly; an employee whose
  `reporting_manager_id` points at another CDP's employee (shouldn't happen, but simulate it) is
  still returned as a root rather than crashing or leaking the other CDP's node; a manual cycle
  (`A.reporting_manager_id = B.id`, `B.reporting_manager_id = A.id`) doesn't hang the request.
- Cross-tenant isolation on every one of the five endpoints — none should ever surface another
  CDP's employees/departments/roles.

## Acceptance criteria

- [x] All five endpoints are live, CDP-scoped, and return real aggregates computed from
      `employee_masters` (+ `leave_request_details` for "on leave") — no hardcoded counts.
- [x] Department/role aggregation is purely on the free-text columns that actually exist; no new
      `department_master`/`designation_master` table is introduced.
- [x] The "on leave" predicate is defined exactly once and shared between this task and [[52]].
- [x] `GET /employees/organization` terminates even on cyclic or cross-CDP-dangling
      `reporting_manager_id` data.

## Completion notes

- `GET /employees/organization` returns `list[OrganizationNodeOut]` (a forest), not a single
  `OrganizationNodeOut` object as the doc's `→` shorthand literally reads — the task's own test
  requirements (a cross-CDP-dangling manager "still returned as a root", a cycle that must not
  hang) only make sense if the endpoint can return zero, one, or several root nodes. A single
  object can't represent that, so the response model was made a list; every other endpoint's
  `→ list[...]`/`→ SingleOut` annotation was followed literally.
- `_on_leave_today_subquery()` was added to `employees/service.py` (this task landed after
  [[52]], so it extracted the predicate [[52]] had inlined, per the "whichever lands first adds
  the helper" note) and is now the sole implementation, used by both `list_employees`'s
  `status=On Leave` filter and `get_headcount`'s `on_leave` count.
- Router ordering: the five new literal-path routes (`/departments`, `/employment-statuses`,
  `/reporting-managers`, `/headcount`, `/roles`, `/organization`) were inserted before
  `/{employee_id}`, matching the existing `/add-form` placement — FastAPI matches routes in
  registration order and `/{employee_id}: int` would otherwise 422 on these paths before ever
  reaching them.

Completed: 2026-08-19
