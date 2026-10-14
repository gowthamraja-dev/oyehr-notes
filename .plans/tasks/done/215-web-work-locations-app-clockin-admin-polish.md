---
task: 215
title: Web Work Locations admin — app clock-in create path, list columns, NetworkPanel polish
status: done
depends_on: [211]
---

# 215 — Web Work Locations admin: app clock-in create path, list columns, NetworkPanel polish

## Scope
The HR-admin UI for app clock-in already exists (`LocationFormModal.tsx` toggle, geofence and
accuracy inputs, `NetworkPanel.tsx`). This task fixes the gaps the task-211 audit found. It is
**web only**, with no backend changes. Paths are under
`workspace-2/hrms/frontend/src/dashboards/hrAdmin/WorkLocations_components/`.

1. **Create path.** In `components/LocationFormModal.tsx:430-448`, hide or disable the
   "Switched on" app clock-in checkbox while `locationId === null`, with the hint "Save the
   location and add an approved network first". The backend would refuse it anyway, and today
   the value is silently dropped.
   The backend create schema `WorkLocationIn` (`backend/.../attendance/schemas.py:26-36`) also
   drops `max_location_accuracy_mtrs`, and the backend is out of scope. So when the form has an
   accuracy value, send a follow-up `PATCH /attendance/work-locations/{newId}` with
   `{max_location_accuracy_mtrs}` right after the create POST returns the new id (the update
   schema accepts it). If that PATCH fails, show the error in the modal.
2. **List columns.** In `index.tsx:88-95,131`, add "App clock-in" (On/Off pill) and "Networks"
   (from `approved_network_count`, already in the type) columns. Show a warning badge when the
   location is enabled with 0 networks, or has unrecognised SSIDs. If the backend list doesn't
   return an unrecognised count, skip the badge and note it.
3. **NetworkPanel.**
   - Show `last_seen_at` for the "Seen but not approved" rows, using the `hrms-date-format`
     skill (dd-MMM-yy).
   - Replace the hand-rolled `animate-pulse` skeleton (`:15-23`) with the `Shimmer` primitives.
   - Guard Remove with `useConfirm()` (`hrms-confirm-dialog` skill).
4. Follow the `hrms-spacing` and `hrms-date-format` skills for anything new.

## Files
- `WorkLocations_components/index.tsx`
- `WorkLocations_components/components/LocationFormModal.tsx`
- `WorkLocations_components/components/NetworkPanel.tsx`

## Acceptance criteria
- [ ] The app clock-in checkbox can't be ticked when creating a location.
- [ ] An accuracy limit entered on create is saved (check by reopening the location).
- [ ] The list shows the App clock-in state and network count per location.
- [ ] NetworkPanel shows the last-seen date, uses Shimmer, and confirms before Remove.
- [ ] `npm run build` and lint pass, and the screen is smoke-tested in a browser.

Implemented in workspace-2/hrms commit `959dbae` on `feature/gowtham_WebPunchPolicy` (pushed; PR to `main`). `tsc` clean, lint adds nothing new. The unticked checks above were **not** browser-verified. Moved to done at the user's request.

Completed: 2026-10-12
