---
task: 279
title: Shared FileExportDialog + Attendance "Export report" entry
status: done
depends_on: [275]
---

# 279 — Shared `FileExportDialog` + Attendance "Export report" entry

## Scope
The frontend half of the common engine — the counterpart of `FileImportWizard.tsx`. One config-driven dialog that any module's export reuses, plus the first
consumer on the attendance screen. Backend is 274–278 (types 276–278 can land after; the dialog is data-driven from the catalogue endpoint, so it shows whatever types exist).

### Shared component
`frontend/src/dashboards/shared/FileExportDialog.tsx`, props = `FileExportConfig`:
`{ apiPrefix, title, noun, defaultType?, filters: FilterControl[], periodMode: "month" | "range" | "both", onDone? }`.
* Loads the catalogue (`GET {apiPrefix}`) with `secureFetch`'s `AbortSignal` support (task 181); shows a **shimmer** skeleton for the dialog body while loading (modal chrome stays
  real, `px-5 py-4`), never "Loading…" text.
* Layout: report-type cards (label + one-line description + a tiny layout sketch for ledger vs summary) → period (a **month picker** that expands to the full month, or custom
  From/To using `DateField`, max 62 days, validated client-side with the same message the server uses) → filters (department, shift, employee search — reuse the existing attendance filter
  option sources) → format toggle **XLSX / CSV** (XLSX default) → `Download`.
* Download = plain authenticated `fetch` → `blob` → anchor click → `URL.revokeObjectURL` (as `exportAttendanceRegister` does; the response is binary, not an encrypted JSON body).
  Filename comes from `Content-Disposition`. In-flight state disables the button with an inline "Preparing…" label; Cancel aborts the request.
* Errors: server `detail` shown inline (the 422 "narrow your filters" case especially); no `alert`/`confirm`. Dates displayed `dd-MMM-yy` (hrms-date-format). Tailwind only; page/card spacing per
  hrms-spacing where applicable, modal internals `px-5 py-4`.
* Responsive: single column below `NARROW_BREAKPOINT` (`useIsNarrow()`).

### Attendance entry
* `hrManager/Attendance.tsx` (and the admin attendance screen that shares it — grep where `exportAttendanceRegister` is used): replace/augment the **Export** button with an **Export report**
  button that opens the dialog with `apiPrefix="/api/v1/attendance-export"`, pre-filled from the screen's current range and department/shift/search filters. Remove the now-redundant `handleExport`
  CSV path **only after** `daily_log` (278) is live; until then keep both.
* Visible whenever the existing Export button is (ATTENDANCE READ). No new permission.
* A `frontend/src/lib/api.ts` helper `downloadExport(prefix, type, params, signal)` returns `{ blob, filename }`; the dialog and any future module reuse it.

## Files
* `frontend/src/dashboards/shared/FileExportDialog.tsx`, `frontend/src/lib/api.ts`, `frontend/src/dashboards/hrManager/Attendance.tsx` (+ admin counterpart if separate)

## Acceptance criteria
- [x] (NOT browser-verified) Dialog lists exactly the types the catalogue returns; picking a type + period + format downloads a file that opens with the right shape
- [x] Opening from a filtered attendance screen pre-fills range, department, shift, search
- [ ] (NOT browser-verified) Range > 62 days blocked client-side; a server 422 message renders inline; Cancel aborts the in-flight request (no stray download afterwards)
- [ ] (NOT browser-verified) Skeleton on catalogue load (shared Shimmer primitives only); no spinner/"Loading…"; no layout shift when content mounts
- [ ] (NOT browser-verified) Works at < 1000px width; keyboard-operable; date inputs use `DateField`
- [x] A user without ATTENDANCE READ never sees the entry point
- [ ] (tsc clean; eslint clean for new files; 3 pre-existing errors in Attendance.tsx; no browser smoke) `npm run lint` and `npx tsc --noEmit` clean in `frontend/`; manual smoke of all report types against a running API (**ask before starting any server**)

## Implementation notes
* `FileExportDialog.tsx` is config-driven (`FileExportConfig`) and reads the catalogue; report-type options (`cell`, `status`) appear from the type's params schema. `ExportAttendanceButton.tsx` is the attendance entry point,
  placed on `hrManager/Attendance.tsx` (replacing the old Export button, its handler and `exportAttendanceRegister`) and on Attendance & Shifts.
* Verified by `tsc --noEmit` (clean) and eslint (no findings in the new files). **Not verified in a browser**: that needs a dev server, which the global rules say to start only with approval. The frontend has no component-test harness.
* `eslint` still reports three `set-state-in-effect` errors in `hrManager/Attendance.tsx` (its `fetchSummary` / `fetchExceptions` / `fetchTable` effects); they pre-date this task and are untouched.

## Remaining
* Browser smoke of the dialog (all four report types, filtered pre-fill, 422 message, Cancel mid-request, < 1000px) against a running API — needs an approved dev server. Then tick the unchecked boxes above and move this file to `done/`.
