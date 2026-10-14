---
task: 12
title: Split backend attendance module into attendance + shifts, update frontend routes
status: done
depends_on: []
---

# 12 — Split backend attendance module into attendance + shifts, update frontend routes

## Scope

`docs/leave-and-attendance/` is already split by domain (attendance/leave/shifts), but the
backend code isn't — everything (work locations, holiday calendars, shifts, week-offs,
employee-shift assignment) lives in one `backend/app/modules/attendance/` module
(`router.py` 203 lines, `service.py` 877 lines, `schemas.py` 325 lines). This task carves the
shift-owned half out into a new `backend/app/modules/shifts/` module and updates the frontend
API client to call its new routes.

No `backend/app/modules/leave/` module exists yet, so this task only splits attendance↔shifts —
nothing to do for leave. No DB schema change — this is router/service/schema/test
reorganization only, no Alembic migration.

**Does NOT cover**: extracting a shared "employee scoping" helper module (see decision below —
deliberately deferred until a `leave` module actually needs it), splitting `frontend/src/lib/
api.ts` into per-domain files (deliberately kept as one file, only URLs change), or building any
biometric-device / leave endpoints (out of scope, unrelated to this split).

### Key decision — new URL prefix `/shifts`, not keeping shift routes under `/attendance`

This is a breaking path change, made deliberately so the frontend route-update step is real:

| Old (`attendance`, today) | New (`shifts`) |
| --- | --- |
| `GET/POST /attendance/shifts` | `GET/POST /shifts` |
| `PATCH/DELETE /attendance/shifts/{id}` | `PATCH/DELETE /shifts/{id}` |
| `GET/PUT /attendance/shifts/{id}/week-offs` | `GET/PUT /shifts/{id}/week-offs` |
| `GET/POST /attendance/employee-shifts` | `GET/POST /shifts/employee-shifts` |
| `PATCH /attendance/employee-shifts/{id}` | `PATCH /shifts/employee-shifts/{id}` |
| `GET /attendance/team/employee-shifts` | `GET /shifts/team/employee-shifts` |

`/attendance/work-locations*`, `/attendance/holiday-calendars*`, `/attendance/holidays*` are
unaffected — they stay in `attendance` under the same paths.

### Key decision — no shared helper module (yet)

`_require_employee`, `_require_caller_employee`, `_require_manager_or_admin` (in the current
`attendance/service.py`) are, in current usage, called only by what becomes shift-owned code
(employee-shift assignment + team-roster endpoints). **Move** them (don't duplicate, don't
extract to a new shared service) directly into `shifts/service.py` as-is. `_require_admin` and
`_now` are trivial one-liners needed by both modules — duplicate a fresh copy in each rather than
sharing. If a future `leave` module needs the same manager-scoping predicate, extract a shared
helper *then* — not speculatively now.

### Key decision — duplicate, don't cross-import, two small FK validators

`shifts.assign_employee_shift` / `update_employee_shift` validate optional
`work_location_master_id` / `holiday_calendar_master_id` FKs by calling attendance's
`_get_work_location` / `_get_holiday_calendar` (each ~10 lines: fetch by id, 404 if missing,
CDP-scope check via `corp_masters`). **Duplicate** these two into `shifts/service.py` rather than
importing from `attendance.service`, so the two modules have zero service-layer dependency on
each other. (`attendance.get_resolved_holidays` importing the `EmployeeShiftDetail` **model** to
resolve an employee's holiday calendar via their shift stays as-is — that's a shared-model
import via `app.models`, not a service-to-service coupling, and models aren't moving out of
`app/models/`.)

### Key decision — frontend: update URLs in place, don't split `api.ts`

Only 9 functions in `frontend/src/lib/api.ts` are affected: `listShifts`, `createShift`,
`updateShift`, `archiveShift`, `getShiftWeekOffs`, `replaceShiftWeekOffs`, `assignEmployeeShift`,
`updateEmployeeShift`, `listTeamEmployeeShifts`. Change each one's URL string from
`/attendance/...` to `/shifts/...` and retitle the two section-comment headers (currently
`// ── Attendance: shifts ──` and `// ── Manager: employee shift assignment ──`). No
signature/name changes — `ShiftScheduling.tsx` and `hrAdmin/AttendanceShifts.tsx` only import
these functions by name and never need to change.

## Files

### New
- `backend/app/modules/shifts/__init__.py` — empty, matches `attendance/__init__.py`.
- `backend/app/modules/shifts/schemas.py` — move `ShiftIn`, `ShiftPatch`, `ShiftOut`,
  `WeekOffRuleIn`, `WeekOffRuleOut`, `WeekOffsIn`, `WeekOffsOut`, `EmployeeShiftIn`,
  `EmployeeShiftPatch`, `EmployeeShiftOut`, `TeamEmployeeShiftsOut`, plus the
  `MISSING_PUNCH_POLICIES`/`REGULARIZATION_APPROVERS`/`LATE_MARK_RESET_CYCLES` constants —
  verbatim from `attendance/schemas.py`. No cross-import to attendance's schemas needed (FK
  fields on the Employee* schemas are plain `int`).
- `backend/app/modules/shifts/service.py` — move `_get_shift`, `_week_off_count`,
  `_assigned_count`, `_shift_out`, `_validate_shift_times`, `list_shifts`, `create_shift`,
  `update_shift`, `archive_shift`, `list_week_offs`, `replace_week_offs`, `_employee_shift_out`,
  `list_employee_shifts`, `assign_employee_shift`, `update_employee_shift`, `_display_name`,
  `list_team_employee_shifts`, `_require_employee`, `_require_caller_employee`,
  `_require_manager_or_admin` (all moved verbatim from `attendance/service.py`), plus fresh
  copies of `_require_admin`, `_now`, `_get_work_location`, `_get_holiday_calendar` (duplicated
  per the decisions above — same query shape as the attendance originals, re-homed here).
- `backend/app/modules/shifts/router.py` — single
  `router = APIRouter(prefix="/shifts", tags=["shifts"], route_class=EncryptedRoute)` (no
  `_upload_router`/`include_in` — nothing shift-owned uses multipart). Routes: `GET/POST /` and
  `PATCH/DELETE /{shift_id}` for shifts, `GET/PUT /{shift_id}/week-offs`,
  `GET/POST /employee-shifts`, `PATCH /employee-shifts/{assignment_id}`,
  `GET /team/employee-shifts`.
- `backend/app/tests/modules/test_shifts.py` — new file with the shifts section, the
  employee-shift-assignment section, the manager-scoping section, and
  `test_encrypted_team_employee_shifts_roundtrip`, all moved from `test_attendance.py`, using
  `/api/v1/shifts...` URL constants. Duplicate the shared test scaffolding it needs: `_login`,
  `_auth`, `admin_token` fixture, `_corp`, `_emp`, `_other_cdp`, and the 4 encryption helpers
  (`_OAEP`, `_public_key`, `_encrypt`, `_decrypt`).

### Edited
- `backend/app/modules/attendance/router.py` — delete the shift-owned route functions (`/shifts`,
  `/shifts/{id}`, `/shifts/{id}/week-offs`, `/employee-shifts`, `/employee-shifts/{id}`,
  `/team/employee-shifts`); keep `router` + `_upload_router` + `include_in` exactly as today for
  the remaining work-location/holiday endpoints.
- `backend/app/modules/attendance/service.py` — delete everything moved to `shifts/service.py`.
- `backend/app/modules/attendance/schemas.py` — delete everything moved to `shifts/schemas.py`.
- `backend/app/api/router.py` — add
  `from app.modules.shifts.router import router as shifts_router` and
  `api_router.include_router(shifts_router)` next to the existing attendance include.
- `backend/app/tests/modules/test_attendance.py` — delete the shifts/employee-shift-assignment/
  manager-scoping sections and `test_encrypted_team_employee_shifts_roundtrip`; split the two
  mixed parametrized tests (`test_endpoints_require_authentication`,
  `test_endpoints_require_admin`, which currently parametrize over both attendance and shift
  paths in one function) down to their attendance-only path subset; update the module docstring
  to reflect the narrower scope.
- `frontend/src/lib/api.ts` — update the 9 URL strings listed above from `/attendance/...` to
  `/shifts/...`; retitle the two section headers.
- `docs/leave-and-attendance/shifts/api-and-pages.md` (and `shifts/admin-configuration.md` /
  `shifts/manager-scheduling.md` if they mention exact paths) — update documented endpoint paths
  from `/attendance/...` to `/shifts/...` to match the code once it lands.

## Acceptance criteria

- [x] `backend/app/modules/shifts/` exists with `__init__.py`, `router.py`, `service.py`,
      `schemas.py` per the Files section; `backend/app/modules/attendance/` no longer contains
      any shift-owned code.
- [x] `backend/app/api/router.py` mounts the new `shifts_router`; app boots with no import errors
      (`docker compose up --build -d api`). **Now verified live**, in a later session: the
      `hrms-api-1` container has been running continuously against this module split for hours
      (`docker compose ps`), including through a live `WatchFiles` reload triggered by an
      unrelated edit to `app/modules/shifts/schemas.py` during tasks 18-20 — the reload completed
      cleanly and the container kept serving `/api/v1/shifts/...` requests afterward. The original
      AWS-CodeArtifact/`nhforms` build blocker no longer applies to this box.
- [x] `GET/POST /api/v1/shifts`, `PATCH/DELETE /api/v1/shifts/{id}`,
      `GET/PUT /api/v1/shifts/{id}/week-offs`, `GET/POST /api/v1/shifts/employee-shifts`,
      `PATCH /api/v1/shifts/employee-shifts/{id}`, `GET /api/v1/shifts/team/employee-shifts` all
      respond correctly. **Now verified live** against the running dev API (encrypted round-trip,
      real JWTs, real dev DB — not the pytest test client): `GET /shifts` (200), `GET`/`PATCH`
      `/shifts/{id}` and `GET`/`PUT /shifts/{id}/week-offs` (organic traffic observed in
      `docker compose logs api`, all 200), `GET /shifts/employee-shifts?employee_master_id=283`
      (200, real rows), `GET /shifts/team/employee-shifts?from=&to=` (200, real rows), plus
      `POST`/`PUT`/`GET`/`DELETE /shifts/assignments` exercised directly as the seeded manager
      account (`multirole@test.com`) — `201`/`200`/`200`/`204`.
- [x] `GET/POST /api/v1/attendance/work-locations*` and `/api/v1/attendance/holiday-calendars*`/
      `/holidays*` still work unchanged — confirmed via `test_attendance.py`'s full pass.
- [x] No cross-module imports exist between `attendance/service.py` and `shifts/service.py`
      (grep confirms) other than shared `app.models` imports.
- [x] `cd backend && uv run pytest app/tests/modules/test_attendance.py app/tests/modules/test_shifts.py -v`
      — both pass (18 + 31 = 49/49), including the split parametrized auth-gating tests and both
      encrypted round-trip tests.
- [x] `uv run pytest` (full suite) passes — 165 passed; the only 2 failures
      (`test_engagement_email.py::test_send_email_ok`,
      `::test_send_email_resolves_template_variables`) are pre-existing and unrelated (a
      `ChatRoom`/`ChatMessage` lookup issue in the engagement module — confirmed via
      `git status` that this file was never touched by this task).
- [x] `frontend/src/lib/api.ts`'s 9 functions call `/shifts/...` paths (grep confirms no
      remaining `/attendance/shifts`, `/attendance/employee-shifts`, or `/attendance/team`
      references); `ShiftScheduling.tsx` and `hrAdmin/AttendanceShifts.tsx` were not touched —
      they only import these functions by name.
- [x] In the running app: HR Manager "Shift Scheduling" screen and HR Admin "Attendance & Shifts"
      screen — shift list/create/update/archive/week-offs/assign-shift all still work end-to-end
      against the new `/shifts/...` routes. **Verified by API traffic, not a browser
      click-through** (browser automation was declined this session): the HR Admin screen's exact
      backing calls were seen as real, organic traffic in `docker compose logs api` (`PATCH
      /shifts/{id}`, `PUT /shifts/{id}/week-offs`, both 200) while this session was in progress;
      the Manager roster screen's exact backing calls (`POST`/`PUT`/`GET`/`DELETE
      /shifts/assignments`) were exercised directly above. Pixel-level rendering was not checked.
- [x] `docs/leave-and-attendance/shifts/api-and-pages.md` documents the new `/shifts/...` paths,
      not the old `/attendance/...` ones (the one remaining `/attendance/employee-shifts` mention
      is a deliberate historical quote of a prior doc's stale claim, not a current-state claim).

Completed: 2026-08-17
