---
task: 80
title: Manager Attendance dashboard — export button
status: done
depends_on: [73, 75, 77]
---

# 80 — Manager Attendance dashboard — export button

## Scope

Add the **Export attendance** action (design prompt §19) to `hrManager/Attendance.tsx`, calling
task 75's `exportAttendanceRegister` client with the table's **current** date/department/shift/
status/search state (task 76/77's filter state — no separate export-only filter UI, it exports
exactly what's currently on screen, unpaginated).

There is no existing CSV-download precedent anywhere in this frontend to follow — use the
standard browser pattern: fetch the CSV body as a `Blob` (task 75's `exportAttendanceRegister`
already returns one), `URL.createObjectURL(blob)`, a temporary off-DOM `<a download="attendance-
<date>.csv" href={url}>` clicked programmatically, then `URL.revokeObjectURL(url)` immediately
after. Do not attempt to render the CSV inline or navigate the page to the blob URL.

## UI

A button near the table's filter row (or the page header, near the date selector — pick whichever
reads as "acts on the whole current view" rather than looking like a table-row action). Disabled
with a spinner while the export request is in flight; on failure, a toast/inline error ("Export
failed — try again") rather than a silent no-op — the manager needs to know the click did
something. No `Period` (Day/Week/Month) is part of the export filename/params beyond `date`,
since task 70/73's register (and therefore the export) is always a single-date view regardless of
the analytics band's period selector (design prompt §3's "period ... should not unexpectedly
change the daily employee table" applies equally to export, which exports the table).

## Files

- `frontend/src/dashboards/hrManager/Attendance.tsx`

## Manual verification

Apply a department/status/search filter, click Export, confirm the downloaded CSV's row count
and content match the currently-filtered table (not the unfiltered full register), and that its
filename embeds the selected date.

## Acceptance criteria

- [x] Export always reflects the table's current filters, never a separate/forgotten filter set.
- [x] Loading and failure states are visible to the user, not silent.
- [x] Manually verified per above — downloaded file content matches the on-screen filtered table.
