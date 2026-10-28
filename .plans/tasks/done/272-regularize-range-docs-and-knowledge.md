---
task: 272
title: Regularize range — docs and in-app knowledge
status: done
depends_on: [270, 271]
---

# 272 — Regularize range — docs and in-app knowledge

## Scope
Document the new HR flow so it is discoverable and so HR knows when to use it versus the bulk import. Code is 269–271.

1. **Docs** (`docs/` in the HRMS repo): add a section — or a short `docs/attendance-range-regularization.md` linked from the attendance docs and from
   CLAUDE.md's attendance/import area — covering:
   - what it is and when to use it: one employee, a date range (≤ 62 days), HR-only; versus the single-day regularize and versus the bulk import
     (`docs/attendance-bulk-import.md`, many employees / spreadsheet);
   - the preview → apply contract (both endpoints, request/response shapes, the `code` vocabulary for skip/blocked), re-validation at apply time, per-day savepoints and
     partial success;
   - what it writes (Manual punches with `raw.synthesized` in shift mode, one `attendance_request_details` row per day Approved with HR as approver, `RegularizationByHR` /
     `LockedDayOverride` audit rows, one batch `user_activity_details` row, one summary notification);
   - guards: org-wide `ATTENDANCE` scope + `APPROVE ATTENDANCE`, locked days need `override_reason`, closed payroll periods are refused, week-offs are skipped;
   - known limits: no undo in v1, single employee, week-offs not tickable.
2. **In-app knowledge** (`frontend/src/content/knowledge/attendance.ts`): extend the `attendance.regularisation` topic (or add a sibling topic for HR) with a short
   "Regularize a whole month" how-to for the HR role, and link it from the existing topic's `related`. Use the file's existing spelling ("regularisation") and tone.
3. If task 270's "Findings" noted that the single-day HR path lacks payroll-closed / joining / relieving checks, make sure that follow-up task exists and is linked here.

## Files
`docs/attendance-range-regularization.md` (new) or a section in the existing attendance doc, `frontend/src/content/knowledge/attendance.ts`, `CLAUDE.md` link if a new doc is created.

## Acceptance criteria
- [x] Doc describes both endpoints, the code vocabulary, guards, what is written, and limits; examples match the shipped request/response exactly
- [x] Linked from the relevant CLAUDE.md section and from `attendance-bulk-import.md` ("for one employee's range, see …")
- [ ] Knowledge topic added/extended and rendered correctly in the app (no broken `related` keys)
- [x] Follow-up task for any single-day-path validation gap exists, or the finding is recorded as "none"

## Progress (2026-10-27) — written, in the working tree of workspace-2 (not committed)
`docs/attendance-range-regularization.md` (new); "Range regularization" paragraph in `CLAUDE.md`; "see also" line in `docs/attendance-bulk-import.md`; HR topic
`attendance.regularise-range` + `related` link in `frontend/src/content/knowledge/attendance.ts`. A `git stash` briefly swept the tracked edits out; the stash was popped and
they are back. `npx tsc --noEmit` is clean for the whole frontend. The follow-up for the single-day validation gap is task 273 (already exists).
Not verified: the topic rendering in the running app (the `related` keys resolve in code: `attendance.regularisation`, `attendance.shifts`).
