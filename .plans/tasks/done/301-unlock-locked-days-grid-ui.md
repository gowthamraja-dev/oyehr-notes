---
task: 301
title: Unlock locked days — Regularization grid UI + 30-day window option
status: done
depends_on: [300]
---

# 301 — Unlock locked days — Regularization grid UI

## Scope
**Unlock N** on the selection bar and right-click menu (APPROVE + UPDATE ATTENDANCE, only when the selection holds locked cells), **Quick select → Locked days**, and `GridUnlockModal.tsx`
(list of the locked days, required reason, result with failed/skipped days and the "older than the shift window" warning). Applies through `unlockAttendanceDays` in batches via `chunkTargets`;
failed cells stay selected, the grid reloads. Also a **30 days** option in the shift editor's Regularization window (`ShiftDefaults.tsx`) so a month can be opened — the backend takes any integer.
Docs: `docs/attendance-range-regularization.md` ("The Regularization grid"), `gaps.md` #36, CLAUDE.md.

## Files
`frontend/src/dashboards/hrManager/{GridUnlockModal.tsx,RegularizationGrid.tsx}`, `frontend/src/lib/api.ts`, `frontend/src/dashboards/hrAdmin/AttendanceShifts_components/components/ShiftDefaults.tsx`.

## Acceptance criteria
- [ ] Selecting locked cells shows Unlock; unlocking clears the dots and the employee can regularize the day
- [ ] A day older than the window shows the warning; widening the window to 30 days first makes it requestable
- [ ] Hidden without APPROVE + UPDATE ATTENDANCE

## Progress (2026-10-28)
Built; `tsc` and eslint clean. NOT checked in a browser.

Moved to done on the user's instruction WITHOUT a browser check: the acceptance criteria above (Unlock shown for locked cells and clears the dots; out-of-window warning and the 30-day option; hidden without APPROVE + UPDATE ATTENDANCE) are UNVERIFIED in a browser. Only `tsc` and eslint were clean.

Completed: 2026-10-28
