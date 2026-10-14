---
task: 75
title: Manager attendance dashboard — frontend API client
status: done
depends_on: [69, 70, 71, 72, 73]
---

# 75 — Manager attendance dashboard — frontend API client

## Scope

Add typed client functions to `frontend/src/lib/api.ts` for the five new endpoints (69-73),
following the exact conventions already used by the neighboring attendance functions in that
file (`getEmployeeAttendanceToday`/`getEmployeeAttendanceDaily` around line 933-957): `secureFetch`
(these are all `EncryptedRoute` endpoints except export, task 73, which is plain `fetch` — same
distinction the file already makes for `addRequestAttachment`'s plain `fetch` at line ~1356), a
named response type per endpoint, `_detailMessage(data, "...")` on failure, token from wherever
the surrounding functions source it in this file.

## Functions to add

- `getManagerAttendanceSummary(params: { date: string; period?: "day"|"week"|"month";
  department?: string; shiftId?: number }): Promise<AttendanceAnalytics>` → `GET
  /api/v1/attendance/analytics`
- `getManagerAttendanceRegister(params: { date, department?, shiftId?, status?, search?, sort?,
  direction?, limit?, offset? }): Promise<AttendanceRegisterPage>` → `GET
  /api/v1/attendance/register`
- `getManagerAttendanceExceptions(params: { date, type?, department?, shiftId?, search?, limit?,
  offset? }): Promise<AttendanceExceptions>` → `GET /api/v1/attendance/exceptions`
- `getEmployeeAttendanceAnalytics(employeeId: number, period, date):
  Promise<EmployeeAttendanceAnalytics>` → `GET /api/v1/attendance/employees/{id}/analytics`
- `exportAttendanceRegister(params): Promise<Blob>` → `GET /api/v1/attendance/register/export`,
  plain `fetch` (not `secureFetch` — matches task 73's plain-router decision), returning the raw
  response body for the caller to turn into a downloadable file (see task 80 for how the download
  itself is triggered — this function only fetches the CSV, it does not touch the DOM)

Response types mirror the backend schemas from tasks 69-72 field-for-field — do not rename or
reshape fields translating them into TypeScript; keep camelCase-vs-snake_case as the rest of this
file already does (it keeps the backend's `snake_case` field names as-is in most existing types
here, e.g. `TodayAttendance`'s `attendance_date`/`first_in_at` — match that, don't introduce a
new camelCase convention for just these new types).

## Files

- `frontend/src/lib/api.ts` — new section, e.g. `// ── Attendance: manager dashboard
  (summary/register/exceptions/export) ──`, placed near the existing manager regularization-inbox
  section (~line 1368) since it's the same persona/module

## Acceptance criteria

- [x] All five functions compile and match their backend contracts exactly (verify against the
      actual response bodies tasks 69-73 produce, not just this task file's sketches — the
      backend tasks are the source of truth if anything drifted during implementation).
- [x] `npm run build` (or the project's equivalent typecheck) passes with no new `any` leaking
      into these types.
- [x] No existing exported function in `api.ts` is renamed or altered.
