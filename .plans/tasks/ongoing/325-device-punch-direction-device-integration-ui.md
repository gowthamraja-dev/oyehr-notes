---
task: 325
title: Device punch direction — Device Integration screen
status: ongoing
depends_on: [324]
---

# 325 — Device punch direction: Device Integration screen

## Scope
Let HR set and see a terminal's direction in the Device Integration section: choose it when adding a terminal and when editing one, and show it on the device list. The API contract is task 324 (`punch_direction`: `"Auto" | "In" | "Out"` on `DeviceOut`, `DeviceCreate`, `DeviceUpdate`; `PATCH /api/v1/devices/{serial}`).
Does NOT cover backend rules (324), re-tagging old punches, or any change to the attendance import screen. Paths relative to `workspace-2/hrms/`.

## Files
- `frontend/src/lib/api.ts` — `AttendanceDevice.punch_direction`, `DeviceInput.punch_direction?`; `createDevice` / `updateDevice` already send the input object, so no new function.
- `frontend/src/dashboards/hrManager/DeviceForms.tsx` — `DeviceFormModal`, the add AND edit form (one component, `mode: "add" | "edit"`).
- `frontend/src/dashboards/hrManager/AttendanceDevices.tsx` — the badge on the device table row.
- `frontend/src/dashboards/hrManager/DevicePanels.tsx` — a "Scan direction" row in the device detail panel. Its bulk "Add several" sheet sends no `punch_direction`, so those terminals start on Auto.

## Behaviour
- A three-way radio group on the add and edit forms, default `Auto`, with these labels:
  - "Auto — use the terminal's own in/out signal"
  - "Entry terminal — every scan is a clock-in"
  - "Exit terminal — every scan is a clock-out"
  plus one line: "Applies to new punches only. Earlier punches keep the direction they were stored with."
- The device list/card shows a small badge "Entry" or "Exit" for those two settings, nothing for Auto.
- Editing saves through `updateDevice(serial, { punch_direction })`; on failure show the existing error pattern (`Could not save the changes.`).
- Reuse the shared UI components of that screen; Tailwind only, no new `.module.css`; the page's existing loading state is kept (no new shimmer needed, no layout shift).
- Page spacing and radius follow what that page already uses (read the JSX; see `hrms-spacing`).

## Acceptance criteria
- [x] Add form sends `punch_direction` (default `Auto`); the Entry / Exit badge shows on the device row once the list reloads after save
- [x] Edit form shows the saved value (`device.punch_direction ?? "Auto"`) and saves a change through `updateDevice`; the list reloads through the existing `onSaved` path
- [x] An older API response without the field is treated as `Auto` (the field is optional in the type; `punchDirectionBadge` returns null)
- [x] `npx tsc --noEmit` and eslint on the four changed files exit 0
- [ ] Seen in a browser — NOT done: no frontend server was approved or started. Unseen: the three-way radio group (layout at 640px and wider), its selected state, the badge next to the device name, and the new detail-panel row

## Progress (2026-11-02)
Built in `workspace-2/hrms`, NOT committed. `lib/api.ts`: `PunchDirection`, `punchDirectionBadge`, optional `punch_direction` on `AttendanceDevice` and `DeviceInput`. `DeviceForms.tsx`: a "Scan direction" radio group (three cards, `role="radiogroup"` / `role="radio"`, Tailwind only) between Auth mode and Connection, seeded from the device, sent with every save. Note: the edit form already sent its whole payload to `PATCH /devices/{serial}`, so the new field simply rides along.
