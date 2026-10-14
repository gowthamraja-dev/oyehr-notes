---
task: 73
title: Manager attendance dashboard — CSV export API
status: done
depends_on: [70]
---

# 73 — Manager attendance dashboard — CSV export API

## Scope

`GET /api/v1/attendance/register/export` — new endpoint (not in the original `api-and-pages.md`
sketch; flag in task 81). Server-generated CSV of the currently filtered register (design prompt
§19), so the browser never assembles or holds the full unfiltered dataset.

## Why a plain (non-encrypted) router

`EncryptedRoute` wraps JSON bodies as `{iv, ct}` — unworkable for a file download the browser is
meant to save via `Content-Disposition: attachment`. This module already has exactly this
precedent: the holiday CSV **import** endpoint (`POST /attendance/holiday-calendars/{id}/import`)
and the regularization attachment upload are both on the separate plain `_upload_router` in
`attendance/router.py` for the identical reason ("multipart isn't supported by EncryptedRoute").
Follow that pattern: a plain `APIRouter` (still behind `CurrentPrincipal` auth — plain-router only
means unencrypted body, not unauthenticated), reusing the module's existing `_upload_router` or a
new sibling plain router in the same file, tagged consistently with the rest of the module.

## Endpoint

`GET /attendance/register/export?date=2026-08-19&department=&shift_id=&status=&search=`

Same filter params as task 70's `/register` (minus `sort`/`direction`/`limit`/`offset` — export
always returns every matching row, sorted by the same default as task 70, in one response; no
pagination on an export). Same manager/admin/CDP scope, reusing task 69's scope-resolution
helper — an export must never include rows outside the caller's scope, exactly like the register.

### Response

`200 OK`, `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment;
filename="attendance-2026-08-19.csv"`. Columns, in order:

```
Employee Name,Employee ID,Department,Shift,Status,Clock In,Clock Out,Worked Hours,Late By (min),Regularization
```

- `Status` = the `effective_status` display label (task 68 / `vocabularies.md` §1's labels).
- `Worked Hours` = task 68's `format_worked_hours` output (`"Incomplete"`/`"Nh MMm"`/`"—"`), not
  raw minutes.
- `Clock In`/`Clock Out` = local time formatted in the employee's effective shift's work-location
  timezone (same `resolve_timezone` call `calendar_resolver_service.py` already exposes), not
  raw UTC — an HR person opening this CSV needs wall-clock times, not `Z`-suffixed instants.
- `Regularization` = `"Pending"` / `""` (blank when none), mirroring `has_pending_regularization`.

Empty result set (no rows match the filters) → still `200` with just the header row, not a `204`
or an error — an empty CSV is a valid, honest export of "nothing matched".

## Audit

Extend `AttendanceAuditLog.action`'s vocabulary (currently `ClockedIn | ClockedOut |
RegularizationSubmitted | RegularizationApproved | RegularizationRejected |
RegularizationCancelled`, per that model's own docstring) with a new value,
`AttendanceExported`, and write one row per export call: `employee_master_id` — there is no
single employee this action is "about"; leave it `NULL` if the column allows, or reconsider
whether this log is the right home for an export event before forcing a non-nullable FK to hold
a meaningless value (check `attendance_audit_logs.employee_master_id`'s nullability before
deciding — it is currently `NOT NULL` per the model, so either add a migration to make it
nullable for this one action, or store the *manager's own* `employee_master_id` as a reasonable
"who did this" value instead of forcing a target-employee semantic that doesn't fit; the latter
avoids a migration and is defensible since `performed_by_id`/`performed_by_role` already capture
"who", so `employee_master_id` here can degrade to "the actor's own employee id" for this one
action type — document that choice inline as a comment, it is the deviation).
`new_value` = `{"date": ..., "filters": {...}, "row_count": N}`.

Do **not** add an "Attendance viewed" audit action for the summary/register/exceptions/analytics
endpoints (69-72) — every other audit log in this codebase records mutations, not reads; adding
view-tracking here would be a new, unrequested-elsewhere convention and a write on every page
load. Note this explicitly as a deliberate omission in task 81's docs update.

## Files

- `backend/app/modules/attendance/router.py` — one new `GET /register/export` route on a plain
  (non-`EncryptedRoute`) router
- `backend/app/modules/attendance/service.py` — `export_register_csv(db, principal, date,
  department, shift_id, status, search) -> str` (the CSV text), reusing task 70's row-fetch
  logic (not the paginated wrapper — the unpaginated variant)
- `backend/alembic/versions/` — only if `attendance_audit_logs.employee_master_id` needs to
  become nullable; review before assuming this is required

## Tests

- Export respects every filter task 70's register accepts, producing exactly the rows the
  equivalent `/register` call (with a large `limit`) would return.
- Manager/CDP scope enforced — export never includes out-of-scope rows.
- CSV header row and column order match the spec above; a spot-checked data row's `Worked Hours`/
  `Status`/timezone-local clock times are correct.
- An `AttendanceExported` audit row is written with the right `performed_by_id`/`row_count`.
- Empty-result export still returns `200` with header-only CSV.

## Acceptance criteria

- [x] CSV generated server-side; browser never assembles it from a large unfiltered fetch.
- [x] Export respects the same filters as the register it exports.
- [x] Export action is audited.
