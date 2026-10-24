---
task: 249
title: Work Locations screen — "Remote (WFH) site" switch
status: done
depends_on: [248]
---

# 249 — Work Locations screen — "Remote (WFH) site" switch

Part of `.plans/shift-wfh-plan.md`. Backend contract comes from task 248 (`is_remote` on the work-location
create / patch / out, with its rules and error codes).

## Scope
HR marks which work location is the tenant's remote (work-from-home) site, on the existing Work Locations screen.

## Contract used
`WorkLocationOut.is_remote: bool`; `POST/PATCH /attendance/work-locations` accept `is_remote`. Errors:
409 = another live site already holds it (names it); 422 = org-default site, or punch mode not `NoCheck`.

## Files
- `frontend/src/lib/api.ts` — `is_remote` on the work-location types and payloads.
- The Work Locations form / list component under `frontend/src/dashboards/` (find it via `listWorkLocations` /
  `updateWorkLocation` usage).
- Knowledge-centre / help text if the screen has any.

## Behaviour
- Switch "Remote (WFH) site" on the site form. Helper text: employees who work from home are moved to this site;
  only one per organisation; it must use "No check" for app (and web) clock-in so people can punch from home.
- Turning it on with a non-`NoCheck` mode: either set the mode to No check in the form when HR confirms, or show
  the 422 message — do not silently change punch settings. (Prefer an inline notice that the mode will switch to
  "No check", applied in the same PATCH.)
- 409 → show which site currently holds it, with a button to open that site.
- The org-default site's switch is disabled with an explanation. While a site is remote, its punch-mode fields
  can't leave "No check" (disabled with a reason).
- List: a "Remote" chip on the remote site; a quiet banner when the tenant has none ("Employees can't be moved
  to a remote site until one is set").
- Standards: Tailwind only, shimmer skeleton for any loading state, `useConfirm` not native confirm, spacing per
  `hrms-spacing`.

## Acceptance criteria
- [x] HR can turn the remote switch on / off on a site; the list shows the chip
- [x] 409 and 422 cases render clear messages; org-default site can't be set
- [x] Punch-mode fields are locked to "No check" on the remote site
- [x] `tsc` + ESLint clean on changed files; headless-browser smoke against a local DB: set remote → chip shows →
      second site refused with the holder named → turn off → another site can take it

## Implementation notes (24-Oct-26)
- `lib/api.ts`: `is_remote` on `WorkLocation` and `WorkLocationInput` (so the patch type too).
- `LocationFormModal.tsx`: new "Remote (work-from-home) site" card above App clock-in (`remote-site-card`, `remote-site-toggle`).
  Turning it on sets app **and** web check mode to No Check in the same save and locks both radio groups ("Locked to No
  Check while this is the remote site"); turning it off unlocks them and leaves the saved modes alone, like the backend.
  Org-default site: switch disabled with an explanation. Another site already remote: switch disabled, holder named
  (`remote-site-holder`) with an "Open <site>" button (confirms before discarding unsaved changes). A warning shows when
  app clock-in is off for the remote site, and on create it says to switch app clock-in on after saving. `is_remote` is
  sent on create and update.
- `index.tsx`: Remote chip next to Default, a quiet "No remote site is set" note when the list is non-empty and none is
  remote (`no-remote-site-note`), `otherRemoteSite` passed to the modal, modal keyed by location so "Open" remounts it.
- The stale-holder case (someone else set it meanwhile) isn't prevented client-side: the server's 409 message
  ("'<name>' is already the remote site. Turn that off first.") shows in the modal's error area and the modal stays open.
  The 422s (default site, non-NoCheck) can't be reached from this form because the UI prevents them.
- Verification: `tsc` + ESLint clean on the changed files. Headless-browser smokes against a local DB (never the shared
  one): 22/22 (banner → toggle on → modes locked to No Check → saved, chip + banner gone → DB check; default site disabled;
  another site disabled with holder + "Open" works; turn off unlocks, modes stay; stale-holder 409 shown, row untouched)
  and 3/3 for Add Location with the switch on (new site saved remote, No Check, app clock-in still off).
- Docs: Work Locations row in `attendance/api-and-pages.md`. Screenshots in the session scratchpad
  (`40`–`44-*.png`).
