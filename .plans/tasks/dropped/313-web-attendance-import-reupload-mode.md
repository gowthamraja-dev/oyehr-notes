---
task: 313
title: Web — re-upload mode in the Import attendance wizard
status: dropped
depends_on: [310, 311]
---

# 313 — Web: re-upload mode in the Import attendance wizard

## Scope
Make the existing **Import attendance** wizard (`frontend/src/dashboards/shared/ImportAttendance.tsx` on `FileImportWizard.tsx`, opened by
`ImportAttendanceButton` from the HR Manager register and the HR Admin Attendance & Shifts page) handle an edited export. Paths relative to
`workspace-2/hrms/`. Design: `.plans/attendance-export-reupload-plan.md`. Needs 310 (the `detected` hint, `header_row`) and 311 (the `Update`
policy and its row warnings); it only does real writes once 312 is in. No new page and no new endpoint.

## Behaviour
1. **Detection banner.** When `parse` returns `detected.export_type === "daily_log"`, show an info strip on the mapping step: "This looks like
   an exported Daily log. Only the days you changed will be updated." and **preselect** `existing_day_policy = "Update"`. Not detected → default
   stays `Skip` and the third option still exists for a hand-built file.
2. **Options step** (`renderOptions`): add the third radio `Update` — "Days that already have punches are corrected to the times in the file
   (unchanged days are left alone)". Add it to `POLICY_LABEL` and `describeOptions`. When `Update` is chosen, add a one-line note that
   blank In/Out cells keep the current value and that Status edits are not imported. The locked-days checkbox + reason stays as is.
3. **Review step** (generic wizard — extend, do not fork): add a **Changed** group for rows with a `Changes … → …` warning, listing
   employee id, date, and the before → after text (the message already carries it); count **Unchanged** from `stats.unchanged` (these are
   `Skipped` rows — show as "Unchanged", not "Skipped", when the policy is `Update`). Rejected / warnings / ready groups unchanged. Show the
   real sheet row (`row_number + header_row`) wherever a row number appears, including the rejected-rows CSV download the wizard builds
   in the browser. Rows with `Status change not imported` get a muted note, not an error colour.
4. **Confirm / result**: confirm text reads "Update N days (M unchanged left alone)"; the result screen shows `days_updated`; "Needs attention"
   already lists failed days — make sure the stale-day message from 312 shows there. History tab: an Update batch shows its policy and
   Undo's reason prompt mentions that original punches will be restored.
5. **Entry points** (optional, small): in the Export report dialog (`FileExportDialog`, Daily log selected) a hint line "Edit the file and
   re-upload it with Import attendance" — text only, no new control.

## Rules
Tailwind only; dates `dd-MMM-yy`; shimmer primitives from `components/ui/Shimmer.tsx` for any new loading state (no hand-rolled `animate-pulse`);
`useConfirm()` not `window.confirm`; 10px page spacing; modal chrome `px-5 py-4`; the two multipart calls stay plain `fetch`, the rest `secureFetch`
(`lib/api.ts` "File imports"). Gate on the existing `usePermission("CREATE", "ATTENDANCE_IMPORT")` — no new permission.

## Files
`frontend/src/dashboards/shared/ImportAttendance.tsx`, `frontend/src/dashboards/shared/FileImportWizard.tsx` (generic review/changed group, sheet-row display,
optional `detectedBanner` / `reviewGroups` config props), `frontend/src/lib/api.ts` (types: `detected`, `header_row`, stats keys),
`frontend/src/dashboards/shared/FileExportDialog.tsx` (hint line, if kept).

## Acceptance criteria
- [ ] `tsc --noEmit` and eslint clean
- [ ] Uploading an exported daily log shows the banner and `Update` preselected; uploading the plain template shows neither
- [ ] After "Check file" an edited export shows Changed rows with before → after, an Unchanged count, and no rejections for untouched rows
- [ ] Rejected-rows CSV and row labels use the real sheet row numbers (checked with an XLSX that has a meta block)
- [ ] `Skip` and `Merge` flows look and behave as before (screens compared)
- [ ] Result screen shows days updated; Undo prompt wording updated
- [ ] Checked in a browser against a running app (needs 310–312 deployed; the shared dev API may not have them yet — say so if it cannot be run)

Dropped: 2026-11-02 — not started; shelved by the user ("leave it for now"). Moved out of `ongoing/` rather than deleted; move it back to restart. Design: `.plans/attendance-export-reupload-plan.md`.
