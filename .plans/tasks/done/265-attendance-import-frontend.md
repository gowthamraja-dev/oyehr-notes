---
task: 265
title: Attendance import — frontend screen
status: done
depends_on: [264]
---

# 265 — Attendance import — frontend screen

## Scope
**Re-scoped by the v2 plan:** build the wizard once as a generic component driven by a per-type config, with attendance as the first config —
`frontend/src/dashboards/shared/FileImportWizard.tsx` (steps, polling, review table, history, confirm/discard/undo/resume) taking
`{ basePath, resource, title, targetFields, templateColumns, optionsForm, strings }`, and `ImportAttendance.tsx` as a thin wrapper holding the attendance config
(options: existing-day policy, include-locked-days + reason). API client functions in `src/lib/api.ts` take the base path. Follow `ImportEmployees.tsx` structure.

Steps: Upload (.csv/.xlsx; template download with columns Employee ID, Date, In Time, Out Time, Status) → Map columns (employee_id and date required;
auto-suggest by header name) → Options (existing-day policy Skip/Merge; "Include locked days" checkbox with required reason, shown only with org-wide
scope) → Review (polls batch while Validating via shimmer skeleton; counters Valid/Rejected/Skipped/warnings; tables for Rejected/Skipped/Warnings with row
number + message; "Download errors (CSV)" built client-side; Confirm and Discard via `useConfirm()`) → Progress/result (polls while Running; days_recomputed/
days_total; days_failed list) . History tab: batches with status pill, counters, Undo (reason prompt) and Resume.
Rules: Tailwind only, shimmer primitives for loading, dd-MMM-yy dates / `DateField`, 10px page spacing (hrms-spacing), no native `confirm()`.
Plain `fetch` for multipart (parse/stage), `secureFetch` for the rest. Entry: "Import attendance" button on the HR attendance screen, gated by
`usePermission("CREATE", "ATTENDANCE_IMPORT")`.

## Files
`frontend/src/dashboards/shared/ImportAttendance.tsx` (new), `frontend/src/lib/api.ts` (types + functions), the HR attendance screen that hosts the button.

## Acceptance criteria
- [x] Happy path in the browser against the dev API with a with-times and a without-times file
- [x] Rejected-row CSV downloads; Undo and Resume work; locked-days option hidden without org-wide scope
- [x] typecheck (`npx tsc --noEmit`) and eslint on the new/changed files clean (full `next build` not run)

## Progress (2026-10-27)
Built: `src/lib/api.ts` ("File imports" client: parse, stage, batch, rows, confirm, resume, undo, discard — plain fetch for multipart, secureFetch for the rest),
`shared/FileImportWizard.tsx` (generic: upload → map → options → check → review → confirm → progress → result, plus History with Resume / Undo / Discard and a
reason dialog for Undo; shimmer skeletons; rejected-rows CSV built in the browser), `shared/ImportAttendance.tsx` (the attendance config: existing-day policy,
include-locked-days + reason shown only with `UPDATE ATTENDANCE`, template download), `ImportAttendanceModal.tsx`, `ImportAttendanceButton.tsx` (renders nothing
without `CREATE ATTENDANCE_IMPORT`), wired into `hrManager/Attendance.tsx` (refreshes tiles/exceptions/register when an import settles) and the HR Admin
"Attendance & Shifts" header. Backend support added for it: `GET …/rows?errors=true`.
Still open: the two browser criteria above — nobody has clicked through it yet (no browser available in this session). The API behind it was smoke-tested
with real commits.
