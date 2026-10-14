---
task: 100
title: Work Locations admin screen (frontend) + nav/RBAC wiring
status: done
depends_on: []
---

# 100 — Work Locations admin screen (frontend) + nav/RBAC wiring

## Scope

**Key finding that shapes this task: the backend is already fully built.** `WorkLocationMaster`
(`backend/app/models/work_location_master.py`, table `work_location_masters`), its migration
(`backend/alembic/versions/c634b889524f_attendance_admin_config_tables.py`), Pydantic schemas
(`backend/app/modules/attendance/schemas.py` — `WorkLocationIn/Patch/Out/DetailOut`,
`WorkLocationAddressIn/Out`), full CRUD service (`backend/app/modules/attendance/service.py`
lines 143-281) and encrypted router (`backend/app/modules/attendance/router.py` lines 87-111,
`GET/POST /api/v1/attendance/work-locations`, `GET/PATCH/DELETE …/{id}`) all exist and are
already covered by tests (`backend/app/tests/modules/test_attendance.py`,
`backend/app/tests/modules/test_authz.py` lines 355-387 — CRUD, CDP-scoping, timezone
validation, cross-corp rejection, archive-as-delete, permission gate). `EmployeeShiftDetail`
already carries `work_location_master_id` and the shift bulk-assign flow
(`frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`) already lets HR pick a location —
so "wire it into Employee/Shift" is already done structurally. **Do not re-build any of the
above.** The only real gap: nobody can create/edit/archive a `work_location_masters` row —
`frontend/src/lib/api.ts` only has `listWorkLocations()` (read-only), and there is no admin UI.
This task closes exactly that gap.

**In scope:**
1. Frontend API client: add `createWorkLocation`, `getWorkLocation`, `updateWorkLocation`,
   `archiveWorkLocation` to `frontend/src/lib/api.ts`, plus the missing request/response types.
2. A new "Work Locations" admin screen under `frontend/src/dashboards/hrAdmin/` — list, add,
   edit, archive.
3. Nav/view wiring in `frontend/src/dashboards/hrAdmin/index.tsx`.
4. A one-line accuracy fix to the RBAC resource docstring in
   `backend/app/modules/roles/permissions.py` (see "RBAC decision" below) — **doc comment
   only, do not touch the `RESOURCES` grid data itself.**

**Explicitly NOT in scope** (already done, or a separate future task):
- Any backend model/migration/service/router/schema change — none needed.
- A `department_masters` table or a "Departments" CRUD UI. `EmployeeMaster.department` is
  still a plain free-text column and `department_master_id` is still the documented
  nullable-`BigInteger` forward-reference placeholder (CLAUDE.md "`*_master_id` fields whose
  master table doesn't exist yet"). Out of scope here — don't build it as a drive-by.
- Adding a location field to `ShiftMaster` itself — shifts are location-independent by design
  (see the model's docstring: "start_time/end_time are clock faces at the work location, not
  UTC" — the location comes from the *assignment* (`EmployeeShiftDetail`), not the shift).
- Geofence radius visualization (a circle overlay on the map). `MapPickerModal` is plain
  Leaflet with no radius-circle support today — out of scope for v1; the radius is just a
  numeric input.

## RBAC decision (read before wiring nav)

`backend/app/modules/roles/permissions.py` gates the actual work-location endpoints on the
`ATTENDANCE` resource (`READ, CREATE, UPDATE, APPROVE` — no `DELETE` cell; the archive route
is gated on `_UPDATE`, matching the module's stated convention of gating deletes on the
nearest cell). But the module's own reference-table docstring (lines 47 & 54) currently lists
"Departments & Locations" under `SETTING` instead. `frontend/src/dashboards/hrAdmin/index.tsx`
line 39 already has an unbuilt nav slot for this: `{ key: "deptLoc", label: "Departments &
Locations", ..., resource: "SETTING" }` (falls through to the generic `<Placeholder>` today
because `"deptLoc"` isn't in `CUSTOM_VIEWS`).

**Decision: repurpose this exact nav slot for Work Locations, and change its `resource` from
`"SETTING"` to `"ATTENDANCE"`.** Reasoning: nav visibility must match live API enforcement —
today a user with `SETTING` READ but not `ATTENDANCE` would see a nav item whose every action
403s, and a user with `ATTENDANCE` access but not `SETTING` wouldn't see the page at all. Since
"Departments" has no backend to show yet (see "explicitly not in scope" above), rename the
label to just **"Work Locations"** rather than building a combined screen for a master that
doesn't exist. Update the `permissions.py` docstring table to reflect "Work Locations" under
`ATTENDANCE` (drop it from the `SETTING` line) so the reference table stays accurate — this is
a comment-only edit, the `RESOURCES` tuple itself doesn't change.

If a future task builds `department_masters`, it can add its own nav entry then — don't block
on it now.

## Files

**Edit:**
- `frontend/src/lib/api.ts` — extend the `WorkLocation` type (it's currently missing `lttd`,
  `lgtd`, `geo_fence_radius_mtrs`, `effctv_dt`, `trmntn_dt`, which `WorkLocationOut` already
  returns) and add:
  - `WorkLocationAddress` type (mirrors `WorkLocationAddressOut`: `id`, `address_line1`,
    `address_line2`, `area`, `landmark`, `city_master_id`, `pin_code`, all nullable except id).
  - `WorkLocationDetail` type (`WorkLocation & { address: WorkLocationAddress | null }`, mirrors
    `WorkLocationDetailOut`).
  - `WorkLocationInput` type mirroring `WorkLocationIn`: `corp_master_id: number`, `name: string`,
    `code?: string | null`, `time_zone: string`, `lttd?: number | null`, `lgtd?: number | null`,
    `geo_fence_radius_mtrs?: number | null`, `effctv_dt?: string | null`,
    `trmntn_dt?: string | null`, `address?: WorkLocationAddressInput | null` (address input
    fields = same shape minus `id`).
  - `WorkLocationPatchInput = Partial<WorkLocationInput>`.
  - `createWorkLocation(input: WorkLocationInput): Promise<WorkLocationDetail>` — POST
    `/api/v1/attendance/work-locations`, mirror `createShift`'s body/error pattern exactly
    (`secureFetch`, `_detailMessage(data, "Failed to create work location")`).
  - `getWorkLocation(id: number): Promise<WorkLocationDetail>` — GET
    `/api/v1/attendance/work-locations/${id}`.
  - `updateWorkLocation(id: number, patch: WorkLocationPatchInput): Promise<WorkLocationDetail>`
    — PATCH `/api/v1/attendance/work-locations/${id}`, mirror `updateShift`.
  - `archiveWorkLocation(id: number): Promise<void>` — DELETE
    `/api/v1/attendance/work-locations/${id}`, mirror `archiveShift`'s error message
    (`"Failed to archive work location"` — check whether the backend returns a structured
    conflict like `archiveLeaveType`'s 409 case; if `attendance/service.py`'s
    `archive_work_location` can 409 on an in-use location, use `_detailMessage` instead of a
    flat throw so that reason surfaces, matching `archiveLeaveType`'s pattern).
  - Corporation dropdown: **reuse `listLeaveCorps()`** (`GET /api/v1/leave/corps` → `{id,
    name}[]`) already defined at `frontend/src/lib/api.ts` — do not add a new corp-listing
    endpoint/function.
  - Address city cascade: **reuse the existing `getCountries`/`getStates`/`getDistricts`/
    `getCities`/`GeoOption` functions** (same file, used today by `OrgContactAddress.tsx`) —
    do not add new geography endpoints.
  - Time zone list: **reuse `getCountryLocale(countryId).timezones`** (same file) to populate
    a Time Zone `<select>` scoped to the chosen country (default India / `Asia/Kolkata`) instead
    of a free-text field — matches how `time_zone` is already validated server-side.

- `frontend/src/dashboards/hrAdmin/index.tsx`:
  - Update the `deptLoc` nav item (line 39): label → `"Work Locations"`, `resource` →
    `"ATTENDANCE"`. Keep the `key` as `"deptLoc"` (avoids touching unrelated call sites that
    might reference the key) — a stray `label` says what the user actually sees.
  - Add `deptLoc: { title: "Work Locations", fullBleed: true, render: (me) => <WorkLocations
    me={me} /> }` to the `views` object (same shape as the `holidays`/`attShifts` entries —
    the screen owns its own filter-rail + content layout).
  - Add `"deptLoc"` to the `CUSTOM_VIEWS` set (otherwise it silently falls back to
    `<Placeholder>` — see `index.tsx` line ~474).
  - Import `WorkLocations` from `./WorkLocations_components`.

- `backend/app/modules/roles/permissions.py` — docstring-only: move "Departments & Locations"
  wording so "Work Locations" is listed under the `ATTENDANCE` row (line 47) and drop it from
  the `SETTING` row (line 54); leave "Departments" out of both until that master exists.

**Create** (new folder, mirroring the `AttendanceShifts_components/` structure — the closest
existing analog for a tenant-scoped master-data list+form screen with its own filter rail):
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/index.tsx` — top-level
  orchestration: fetch on mount, own `useConfirm()` (from the shared confirm-dialog hook per
  the `hrms-confirm-dialog` convention — never `window.confirm`), gate the "Add Location"
  button and each row's Edit/Archive actions on `usePermission("CREATE"|"UPDATE", "ATTENDANCE")`
  (`@/contexts/roles-context`, same hook `ImportEmployees.tsx` uses).
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/hooks/useWorkLocations.ts` — data
  hook mirroring `AttendanceShifts_components/hooks/useShifts.ts`: loads via
  `listWorkLocations()`/`getWorkLocation()`, exposes `{ loading, loadError, locations, filter,
  setFilter, refresh }`.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/components/LocationsList.tsx` —
  table list (not cards, matching `ShiftsList.tsx`'s grid pattern): columns Name, Code,
  Corporation, City, Time zone, Geofence radius, Status (active/archived pill), actions. Filter
  pills at top (e.g. Active/Archived/All) like `ShiftsList.tsx`.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/components/LocationForm.tsx` — the
  add/edit panel: Name*, Code, Corporation* (`listLeaveCorps()` dropdown), Time zone (country →
  timezone cascade per above), a "Pick on map" button opening `MapPickerModal`
  (`../MapPickerModal`, props `{ open, onClose, onConfirm, initialLttd, initialLgtd }` — on
  confirm, set `lttd`/`lgtd` from the result and prefill address fields from `result.geocode`
  if present, same pattern `OrgContactAddress.onMapConfirm` uses), Geofence radius (meters,
  numeric), Effective/Termination dates (`DateField` from
  `frontend/src/components/ui/DateField.tsx` per the `hrms-date-format` convention — never a
  bare `<input type="date">`), and an address block (address line 1/2, area, landmark,
  Country→State→District→City cascade + pin code) built the same way
  `OrgContactAddress.tsx`'s `Select`/`TextInput` helpers work (don't import
  `OrgContactAddress` itself — it's coupled to CDP/contacts props — replicate the small
  cascade logic locally, same as that file does).
  - Archive confirm wording (via `useConfirm()` in `index.tsx`, passed down or called from
    here): `` `Archive "${location.name}"? It will no longer be assignable to shifts or
    employees.` `` — matching `ShiftDefaults.tsx`'s archive-confirm phrasing convention.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/components/Skeleton.tsx` —
  `WorkLocationsSkeleton`: `animate-pulse` placeholders mirroring the list's header + ~5 rows,
  same structure as `AttendanceShifts_components/components/Skeleton.tsx`'s
  `AttendanceShiftsSkeleton`. Rendered by `WorkLocations_components/index.tsx` while
  `loading` is true — never a spinner or "Loading…" text (per repo convention).

## Acceptance criteria

- [ ] `uv run pytest` (backend) still green — no backend behavior changed, only a docstring
      comment; this just confirms nothing was accidentally touched.
- [ ] HR Admin with `ATTENDANCE` CREATE/READ/UPDATE can: open "Work Locations" from the nav,
      see the existing/seeded locations in a list (not a blank Placeholder), add a new location
      (name + corp + time zone required; code/geo optional), edit one, pick a lat/long via the
      map picker, and archive one (with the styled confirm dialog, not a native `confirm()`).
- [ ] A user without `ATTENDANCE` access does not see the nav item (resource gate matches the
      API's actual 403 behavior — verify by comparing against a role with `SETTING` only, which
      should now show *not* seeing this item, confirming the resource fix took effect).
- [ ] A location created for tenant A is not visible/editable from tenant B's session (CDP
      scoping is already enforced server-side in `attendance/service.py`; this is just
      confirming the new UI doesn't do anything client-side that bypasses it, e.g. no
      cross-tenant id ever appears in a dropdown).
- [ ] The newly-created location immediately shows up in `BulkAssignShiftModal`'s location
      dropdown and in `HolidayCalendarAdmin`'s "Applies to" dropdown without any change to
      those files (both already call `listWorkLocations()`).
- [ ] Loading state is the shimmer skeleton, not a spinner/"Loading…" text.
- [x] `frontend` type-checks (`npm run build` or equivalent) with the new/extended types in
      `api.ts`.

Completed: 2026-09-07

Verified live (seeded 'test' tenant, HR Admin login): add → appears in list with resolved
corp name; edit → prefills all fields via `getWorkLocation`; archive → styled confirm dialog
(not native `confirm()`), row removed; the newly-created location immediately appeared in
Holiday Calendar's "Applies to" dropdown with zero changes to that file. `uv run pytest
app/tests/modules/test_attendance.py app/tests/modules/test_authz.py` — 118 passed. `npx tsc
--noEmit` and `npm run build` both clean. The nav-resource fix (`SETTING` → `ATTENDANCE`) and
permission gating (`usePermission("CREATE"/"UPDATE", "ATTENDANCE")`) were verified by code
inspection rather than a live cross-role test.
