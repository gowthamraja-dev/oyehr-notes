---
task: 319
title: Attendance import — match people by device enrollment number
status: done
depends_on: []
---

# 319 — Match people by device enrollment number (not only `emp_id`)

## Scope
The importer resolves **Employee ID → `employee_masters.emp_id`** only. A biometric log or register (`SEP-Attendance.csv`, `DeviceLogs`) carries the terminal's **enrollment number**,
which the codebase is explicit is *not* `emp_id` — `EmployeeDeviceMapping` (`models/employee_device_mapping.py`) exists for exactly this, and `webhooks/service.py` refuses to guess the mapping
because a wrong guess "silently attributes a punch to the wrong person". We saw it in the data: marketing `NT-100` is M M Shariff while biometric code 100 is Syed Khader. This task adds the
safe path: **resolve through the mapping table**. Paths relative to `workspace-2/hrms/`. Independent of 318 (works for the plain template too), but is what makes a device log usable.

## Behaviour
1. New option **`match_by`**: `emp_id` (default, today) | `device_enrollment`. UI: on the options step, "Match people by: *Employee ID* / *Device number*"; for *Device number* a **device dropdown**
   listing the tenant's `attendance_device_masters` (name + serial) plus "Any device (tenant-wide numbers)". When the file has a serial-number column mapped (task 318's `device_serial`) the
   matching device is selected automatically and the dropdown is read-only.
2. Resolution in `validate_rows` (one batched, tenant-filtered query per chunk, no N+1): for each (number, date) find the active, non-archived `employee_device_mappings` row where
   `enrollment_no = number`, `care_delivery_program_master_id = batch tenant`, device = the chosen/serial-matched one **or** `NULL` (tenant-wide) — a device-specific row beats a tenant-wide one — and
   `effctv_dt <= date <= trmntn_dt` (open ends allowed). Then apply the same employee checks as today (active, not archived, joining/relieving bounds).
3. Failures are per row, with the person's name from the file where there is one: `Device number 76 (P SRINIVAS) is not mapped to an employee — add it under Devices`;
   `Device number 12 maps to two employees on this date — fix the mapping`. Never fall back to `emp_id` silently.
4. Leading zeros and padding: the number is compared as text after trimming; `02` and `2` are **different** numbers unless a mapping row says otherwise (the engine already keeps leading zeros for CSV; an
   `.xlsx` that Excel has turned into `2` is the user's to fix — say so in the row message when `02`/`2` would match).
5. "Download unmapped numbers" on the review screen (the wizard already builds the rejected-rows CSV in the browser): distinct number + file name + count, so HR can create the mappings. Creating mappings is the
   existing Devices screen's job — find its route (`modules/devices/`) and link to it; do not build a second mapping editor here.
6. The batch stores `options.match_by` / `options.device_id`; `reference_id` stays `employee_masters.id`, so commit, settle and undo are untouched. `dedupe_key` stays `<employee_id>:<date>`.

## Files
`backend/app/modules/attendance_import/handler.py` (`parse_options`, the employee-resolution block of `validate_rows`), a small resolver in `attendance_import/device_numbers.py` (new),
`frontend/src/dashboards/shared/ImportAttendance.tsx` (+ device list fetch, existing devices API in `lib/api.ts` if present), `backend/app/tests/modules/test_attendance_import.py`, `docs/attendance-bulk-import.md`.

## Rules
Every query filters by the batch's CDP — a mapping or device from another tenant must never resolve (test it). The device dropdown lists only the caller's tenant. No new table. Stdlib `logging`
(WARNING on ambiguous/unmapped counts, no names). Tailwind only.

## Acceptance criteria
- [x] With `match_by = device_enrollment`, a number mapped to employee A resolves to A; `match_by = emp_id` still resolves by `emp_id` exactly as before (and ignores the mapping table)
- [x] An unmapped number is rejected with the "not mapped … add it under Device Integration" sentence (and the file's name for the person), never matched by `emp_id` (a number equal to a real `emp_id` is still rejected)
- [x] A device-specific mapping wins over a tenant-wide one; a mapping outside its `effctv_dt` / `trmntn_dt` window is not used; the "two employees" guard rejects the row (tested on the resolver — the table's unique index makes it unreachable through real rows)
- [x] Another tenant's mapping or device is never used (two-CDP tests, incl. a mapping row in OUR tenant that points at THEIR employee); a serial from another tenant is a 422 "Unknown device"
- [x] `02` does not match `2`, and the message names the other spelling
- [x] The review screen offers the unmapped-numbers CSV — implemented (generic `issueExports` hook in the wizard + the attendance config); the parsing regex is verified against the backend's real messages (4 shapes), `tsc --noEmit` and eslint exit 0, but NOT seen in a browser — confirmed working in the browser by the user, 2026-11-02
- [x] `uv run pytest app/tests/modules/test_attendance_import.py app/tests/modules/test_file_import_engine.py`: 155 passed; ruff clean on the changed modules and tests

## Progress (2026-10-30)
Built in `workspace-2/hrms`, NOT committed. Backend: `attendance_import/device_numbers.py` (new resolver: one batched tenant-filtered query per chunk, dated, tiered, exact-text), `attendance_import/handler.py` (`match_by` / `device_serial` options validated in `parse_options`,
`device_id` derived and stored; `validate_rows` resolves by number when asked, date parsed first), `attendance_import/parsing.py` (optional `employee_name` target field, "Name (for messages)", hints `name` / `employee name` / `user name`…). Frontend: `ImportAttendance.tsx`
(`MatchBy` radios + device dropdown from `getDevices()`, clears `device_serial` when switching back, `describeOptions` line, unmapped-numbers download), `FileImportWizard.tsx` (generic optional `issueExports`). Docs: `docs/attendance-bulk-import.md` ("Matching people by device number", options table).
Deviations from the plan: (1) the option is **`device_serial`**, not `device_id` — the Devices API identifies terminals by serial; the server resolves it (tenant-filtered, archived terminals allowed because a removed terminal's history is what gets migrated) and stores `device_id`;
(2) the "Name (for messages)" column is a new optional target field (row data keeps only mapped columns); it is never matched on and never logged; (3) the link to the mapping screen is text — "add it under Device Integration" — because that screen lives in the HR Manager dashboard and the import also runs from HR Admin;
(4) auto-selecting the terminal from a `Serial Number` column in the file belongs to task 318 (raw device logs) and is not done here; (5) tenant-wide mappings are the only ones used when no terminal is chosen — deliberately, so "any device" can never attribute a number that really belongs to one terminal.
Remaining: one look at the options step and the review screen in a browser (together with task 317's), then move to `done/`.

Completed: 2026-11-02
