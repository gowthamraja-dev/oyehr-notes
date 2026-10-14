---
task: 108
title: Empty work-locations guidance → Organization Settings address (frontend)
status: done
depends_on: [107]
---

# 108 — Empty work-locations guidance → Organization Settings address (frontend)

## Scope

Task 107 makes a complete organization address auto-populate one default
`work_location_masters` row (`is_org_default: true`, now present on `WorkLocationOut`/
`WorkLocationDetailOut`). This task is the UI half: everywhere the app shows an empty work
locations list, point the user at *why* it's empty and *where* to fix it — the "Address"
section of Organization Settings → Company Profile — instead of a silent empty dropdown, and
visually distinguish the default location once it exists so nobody accidentally deletes an
org's own address.

**In scope:**
1. Empty-state message + in-app navigation link in the **Work Locations admin screen**
   (`frontend/src/dashboards/hrAdmin/WorkLocations_components/`) when the list is empty.
2. A lighter-weight empty-state message (text only, no deep link — see "Navigation scope"
   below) in the two existing dropdown consumers that currently render nothing when the list
   is empty: `BulkAssignShiftModal.tsx` (work-location `<select>`, lines 191-205) and
   `HolidayCalendarAdmin.tsx` (both location `<select>`s, lines 496-499 and 705-712).
3. A "Default" badge on the org-default location row in the Work Locations list, with its
   Archive action disabled (tooltip explaining why) — matching the backend's 409 guard from
   task 107 so the UI never lets a user attempt an action the API will reject.
4. The default location's address fields become read-only in `LocationForm.tsx` (name, code,
   time zone, geofence radius stay editable) with a note that they're synced from
   Organization Settings, since task 107 overwrites them on every org-address save — letting
   a user hand-edit them would be silently clobbered on the next org save, which is confusing
   without an explanation.

**Explicitly NOT in scope:**
- Any backend change — task 107 already ships `is_org_default` and the 409 guard this task
  reads/relies on.
- Building the org address form itself — `OrgContactAddress.tsx`/`OrgSettings.tsx` already
  collect and validate (`isAddressValid()`, `OrgSettings.tsx:529-538`) address line 1,
  country, state, city, and pincode before the whole Company Profile panel can save; nothing
  here changes that validation.
- Threading `navigate` through `BulkAssignShiftModal` — see "Navigation scope" below.

## Navigation scope (read before wiring links)

The dashboard shell already supports in-app view switching: each top-level view's `render`
receives `(me, navigate)` where `navigate: (key: string) => void` jumps to another nav key
(`frontend/src/dashboards/types.ts:22`, e.g. `MiniHolidayCalendarCard` uses it today,
`frontend/src/dashboards/hrAdmin/index.tsx:395`). Organization Settings is nav key
`"orgSettings"` (`hrAdmin/index.tsx:413-417`); Work Locations is `"deptLoc"` (`hrAdmin/index.tsx`
line ~465-468, per task 100).

- **Work Locations screen** (`deptLoc`, a top-level view) — wire it up properly: change its
  `views` entry in `hrAdmin/index.tsx` from `render: (me) => <WorkLocations me={me} />` to
  `render: (me, navigate) => <WorkLocations me={me} navigate={navigate} />`, thread `navigate`
  down to wherever the empty state renders (likely
  `WorkLocations_components/index.tsx` or `components/LocationsList.tsx`), and call
  `navigate("orgSettings")` from the CTA button.
- **`HolidayCalendarAdmin`** is also a top-level view (`holidays` key,
  `hrAdmin/index.tsx:459-463`) — same treatment: add `navigate` to its `render` signature and
  prop, use it for its empty-state CTA.
- **`BulkAssignShiftModal`** is a shared modal opened from multiple places (not itself a
  top-level view) — do **not** prop-drill `navigate` through every caller for this. Its
  empty-state message is plain text guidance only, no clickable in-app link: *"No work
  locations configured yet. Go to Organization Settings → Company Profile → Address to set
  one up."* If a future task wants this modal to navigate too, that's a separate, larger
  change (the modal would need a callback prop plumbed from every place that renders it).

## Files

**Edit:**
- `frontend/src/lib/api.ts`: add `is_org_default: boolean` to the `WorkLocation` type
  (line 1261-1274) — it's already returned by both list and detail endpoints per task 107.
- `frontend/src/dashboards/hrAdmin/index.tsx`: update the `deptLoc` and `holidays` entries in
  `views` (per "Navigation scope" above) to pass `navigate` through.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/index.tsx` and
  `components/LocationsList.tsx`: accept/forward a `navigate` prop; when the (unfiltered,
  active) location list is empty, render an empty state instead of an empty table — reuse the
  existing "No X configured yet." text style (`text-[12.5px] text-ink-400 px-1 py-2`, the
  convention already used for shifts at `BulkAssignShiftModal.tsx:182`), plus a button/link
  styled like the screen's other primary actions: *"No work locations yet. Complete your
  organization's address to create your default location."* with a
  **"Go to Organization Settings"** button calling `navigate("orgSettings")`.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/components/LocationsList.tsx`:
  for the row where `location.is_org_default` is true, render a small "Default" pill (same
  pill style as the existing Active/Archived status pill) next to the name, and disable that
  row's Archive action (`disabled` + `title="This is your organization's default location — "
  "update it from Organization Settings → Company Profile → Address instead."` on the
  button), so the UI matches the backend's 409 rather than showing a raw error toast after
  the fact.
- `frontend/src/dashboards/hrAdmin/WorkLocations_components/components/LocationForm.tsx`:
  when editing a location with `is_org_default: true`, render the address block (address
  line 1/2, area, landmark, country/state/district/city cascade, pin code) as read-only
  (disabled inputs, same visual treatment `OrgContactAddress.tsx` uses for `locked`) with a
  caption: *"Synced from Organization Settings → Company Profile → Address."* Name, code,
  time zone, geofence radius, and effective/termination dates remain editable as normal.
- `frontend/src/dashboards/shared/BulkAssignShiftModal.tsx`: add an empty-state line right
  after/aligned with the work-location `<select>` (lines 191-205), matching the shifts
  empty-state at line 182 (`text-[12.5px] text-ink-400 px-1 py-2`), text per "Navigation
  scope" above — plain text, no link.
- `frontend/src/dashboards/hrAdmin/HolidayCalendarAdmin.tsx`: add the same style empty-state
  line near both location `<select>`s (lines 496-499 filter, 705-712 modal) when `locations`
  is empty — this one **can** use `navigate("orgSettings")` per "Navigation scope" since
  `HolidayCalendarAdmin` is itself a top-level view once its `render` signature is updated.

## Acceptance criteria

- [~] A tenant with zero work locations and an incomplete/missing org address sees, on the
      Work Locations screen, the empty-state message and a working "Go to Organization
      Settings" button that switches the shell to the `orgSettings` view. Code verified
      (type-checked, matches the same conditional-render pattern as the rest of the screen)
      but NOT visually observed live — both dev tenants available (`test`, `beta`) already had
      at least one work location, and deliberately archiving their real locations to force an
      empty list was judged too invasive for a shared dev DB. Re-check live if a genuinely
      empty tenant becomes available.
- [x] After completing and saving the org address there (line 1, country, state, city,
      pincode — the existing required fields), returning to Work Locations shows exactly one
      location, badged "Default", with the address just entered. Verified live on the `test`
      tenant.
- [x] The Default location's Archive action is disabled with an explanatory tooltip; a
      non-default location's Archive action is unaffected. Verified live.
- [x] Editing the Default location: address fields are visibly read-only with the "Synced
      from…" caption; name/code/time zone/geofence radius/dates remain editable and save via
      the existing `PATCH` flow. Verified live — also extended to the map-picker section
      (`lttd`/`lgtd` are synced too, since task 107 overwrites them on every org-address save
      the same as the address fields; "Pick on map" is hidden and captioned for the default
      location, not just the text address fields the task doc called out).
- [~] `BulkAssignShiftModal`'s work-location dropdown shows the plain-text empty-state message
      (no link) when `workLocations` is empty, and it disappears once a location exists. Code
      verified only (tenant had no shifts configured to open the modal with).
- [~] `HolidayCalendarAdmin`'s location filter and modal dropdown both show the empty-state
      message with a working `navigate("orgSettings")` link when `locations` is empty. Code
      verified only (nav entry point not located during this session; component compiles and
      renders in isolation via `npm run build`).
- [x] `npx tsc --noEmit` / `npm run build` clean.
- [x] Manually verified in the browser (dev server) for the core mechanic (default-location
      creation, badge, disabled archive, read-only synced address) — the empty-state paths
      themselves are code-reviewed/type-checked but not visually exercised, per the notes above.

**Implementation note:** the actual `WorkLocations_components/` layout differs from what this
task doc assumed — the list is inline in `index.tsx` (no separate `LocationsList.tsx`), and
the form is `components/LocationFormModal.tsx` (not `LocationForm.tsx`). Implementation
followed the as-built structure rather than the doc's guessed filenames.

Completed: 2026-09-16
