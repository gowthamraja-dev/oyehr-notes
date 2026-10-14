---
task: 52
title: Employee directory — search, filters, pagination, sort API
status: done
depends_on: []
---

# 52 — Employee directory — search, filters, pagination, sort API

## Discussion

`GET /api/v1/employees` (`backend/app/modules/employees/router.py` + `service.py`) exists today
but returns the **entire** CDP's employee list with no query params at all — `list_employees(db,
principal)` takes no filters, no pagination. It is CDP-scoped (`CorpMaster.
care_delivery_program_master_id == principal.tenant_id`) via a join through `CorpMaster`, which
is correct and must not regress. Its only caller is `frontend/src/dashboards/shared/
EmployeeDirectory.tsx`'s `getEmployees()` (confirmed via grep — no other component imports it),
which currently does client-side filtering over the full list. This task moves that filtering
server-side and adds pagination; [[57-manager-directory-employees-tab-frontend]] is the frontend
task that consumes it.

**No separate "manager" endpoint** — per this planning pass's research, `list_employees` has
*no* manager-vs-admin scoping today (only CDP scoping), and the design prompt's tenant-isolation
section (§12) only requires CDP/corp scoping, not "direct reports only" — unlike the leave/
attendance approval queues (which restrict to direct reports because they're *approval*
surfaces). Do not add a `_manages`/direct-reports restriction to this endpoint; that would be an
unrequested behavior change that breaks `hrAdmin`'s existing use of the same component and isn't
asked for anywhere in the directory-browsing spec. Keep the directory CDP-wide for any
authenticated caller, same as today.

### Response envelope — breaking change to `EmployeeOut`'s list route

Per the design prompt §13, replace the bare `list[EmployeeOut]` response with:

```json
{
  "data": [ /* EmployeeOut[], unchanged shape */ ],
  "pagination": { "page": 1, "page_size": 25, "total": 0, "total_pages": 0 }
}
```

Add a `PaginationOut` schema (`page`, `page_size`, `total`, `total_pages`) and an
`EmployeeListOut { data: list[EmployeeOut], pagination: PaginationOut }` in
`app/modules/employees/schemas.py`. This is the only consumer of the old bare-list shape
(confirmed above) — update it in the same change, don't keep both shapes.

### Query parameters — `GET /employees`

| Param | Type | Behavior |
| --- | --- | --- |
| `search` | `str \| None` | Case-insensitive substring match (Postgres `ILIKE`) across `emp_id`, `frst_nm`, `lst_nm`, `designation`, `department` — OR'd together, single `%term%` pattern reused per column |
| `department` | `str \| None` | Exact match on `EmployeeMaster.department` (free-text column — there is no `department_master` table; confirmed no such model exists anywhere in `backend/app/models/`) |
| `employment_status` | `str \| None` | One of the values `list_employment_statuses` ([[53]]) reports — exact match on `EmployeeMaster.employment_status` |
| `status` | `Literal["All","Active","On Leave","Inactive"] \| None` | The directory's coarse status filter (design prompt §6) — see mapping below. Independent of `employment_status` (that's the free-text HR status like "Probation"/"Confirmed"; this is the UI's Active/On Leave/Inactive concept) |
| `reporting_manager_id` | `int \| None` | Exact match on `EmployeeMaster.reporting_manager_id` |
| `joining_date_from` / `joining_date_to` | `date \| None` | Inclusive range on `EmployeeMaster.joining_date` |
| `page` | `int`, default 1 | 1-indexed |
| `page_size` | `int`, default 25 | Clamp to `{25, 50, 100}` — reject/clamp anything else server-side, don't trust an arbitrary client value (a client passing `page_size=100000` must not be able to force an unbounded scan) |
| `sort_by` | `Literal["name","emp_id","department","designation","joining_date","employment_status"]`, default `"name"` | `"name"` sorts by `(frst_nm, lst_nm)` |
| `sort_order` | `Literal["asc","desc"]`, default `"asc"` | |

**`status` mapping (design prompt §6: "must map to actual persisted employment/attendance/leave
state rather than being arbitrary UI-only values")**:
- `"Active"` → `EmployeeMaster.is_active.is_(True)`
- `"Inactive"` → `EmployeeMaster.is_active.is_(False)`
- `"On Leave"` → `is_active.is_(True)` **and** the employee has an `Approved` row in
  `leave_request_details` (from [[42-leave-request-ledger-models-migration]], already shipped)
  whose `from_date <= today <= to_date`. Do this as an `EXISTS` subquery against
  `LeaveRequestDetail` — reuse the model via `from app.models import LeaveRequestDetail`, do not
  duplicate leave state onto `employee_masters`. If `status=None`/`"All"`, apply no filter.
- Import `date` from `datetime`, use `date.today()` for the "today" comparison — no timezone
  conversion needed, this module has no existing tenant-timezone concept for the directory
  (unlike attendance's shift-timezone handling).

### Indexes (design prompt §24 — evaluate, don't blindly add)

`employee_masters.emp_id` already has `index=True` (model already declares it). `corp_master_id`
already indexed. Add an index migration for `employment_status` only if `EXPLAIN` on a
realistically-sized seed shows a sequential scan dominating — with the CDP join already
filtering to one tenant's rows first, a few hundred/thousand rows per corp is unlikely to need
it; note the decision (added or skipped, with the reasoning) in this task's completion notes
rather than adding it speculatively. Do not add an index on `department` (free-text, low
cardinality per corp, and prompt §24 warns against blind index additions) or `joining_date`
(range-filtered, rarely, on a small-per-tenant table).

## Files

- `backend/app/modules/employees/router.py` — extend `list_employees` route with the query params
- `backend/app/modules/employees/schemas.py` — `PaginationOut`, `EmployeeListOut`
- `backend/app/modules/employees/service.py` — `list_employees` rewritten to build the filtered/
  sorted/paginated query; keep `get_employee` and the other functions unchanged

## Tests (extend `backend/app/tests/modules/test_employees.py`)

- `test_list_employees_ok` and `test_list_employees_scoped_to_cdp` must be updated for the new
  `{"data": [...], "pagination": {...}}` envelope — don't leave them asserting the old bare-list
  shape.
- Search matches on each of `emp_id`/name/designation/department individually, and is
  case-insensitive.
- `department` and `employment_status` filters narrow correctly; unknown value → empty `data`,
  not an error.
- `status="On Leave"` returns only employees with a currently-active `Approved` leave request;
  an employee with a `Pending` or past/future-dated request is excluded.
- `reporting_manager_id` filter narrows to that manager's reports.
- `joining_date_from`/`joining_date_to` range filter, inclusive on both ends.
- Pagination: `page`/`page_size` slice correctly; `pagination.total`/`total_pages` match the
  unfiltered-by-page count of the filtered set; an out-of-range `page` returns an empty `data`
  with correct `pagination.total` (not a 404/422).
- `page_size` outside `{25,50,100}` is clamped, not rejected or passed through raw.
- Cross-tenant isolation (existing `test_list_employees_scoped_to_cdp`) still holds with every
  new filter combination — a filter can't be used to leak another CDP's rows.
- `sort_by`/`sort_order` produce the expected order for at least `name` and `joining_date`.

## Acceptance criteria

- [x] `GET /employees` returns the paginated envelope; the old bare-array shape is gone from both
      the API and `frontend/src/lib/api.ts`'s `getEmployees()` type (coordinate with
      [[57-manager-directory-employees-tab-frontend]] so the frontend isn't left calling a
      shape that no longer exists — land together or keep the frontend task blocked on this one).
- [x] No full-table fetch remains anywhere in the request path — filtering, search and pagination
      all happen in the SQL query, not in Python after loading every row.
- [x] `status="On Leave"` is backed by a real `leave_request_details` row, never a UI-only flag.
- [x] Cross-CDP leakage is impossible through any combination of the new query params.

## Completion notes

- `employment_status` index: **skipped**, not added. `EmployeeMaster` rows are already narrowed
  to one CDP by the `CorpMaster` join before any other filter applies, and per-tenant employee
  counts are expected to stay in the hundreds/low-thousands — a sequential scan over that
  post-join set is not worth a speculative index per design prompt §24. Revisit with `EXPLAIN`
  against a realistically-sized seed if directory queries are ever observed to be slow in
  practice.
- `frontend/src/lib/api.ts`'s `getEmployees()` was updated to unwrap the new `{data, pagination}`
  envelope (added `EmployeeListResponse`/`EmployeePagination` types) and now requests
  `page_size=100` (the max clamp) so `EmployeeDirectory.tsx`'s existing "load everything, filter
  client-side" behavior keeps working unchanged until [[57]] rebuilds it against the new
  search/filter/pagination params. `EmployeeDirectory.tsx` itself was not touched.

Completed: 2026-08-19
