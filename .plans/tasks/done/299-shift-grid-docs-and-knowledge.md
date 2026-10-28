---
task: 299
title: Shift grid bulk assign — docs and CLAUDE.md knowledge
status: done
depends_on: [295, 296, 297, 298]
---

# 299 — Shift grid bulk assign: docs and knowledge

## Scope
Record what was built so the next session does not re-derive it:

- `docs/leave-and-attendance/shifts/manager-scheduling.md` §4 — the grid is now selectable (Excel-style), bulk-assigns through the cells endpoints, filters/paging are server-side;
  correct the sentences that say there is no multi-cell assign.
- `docs/leave-and-attendance/shifts/api-and-pages.md` — the two new routes (`.../cells/preview`, `PUT .../cells`), the new roster params (`page`, `page_size`,
  `work_location_master_id`, `shift_master_id`) and the meta fields.
- `docs/attendance-range-regularization.md` — one line pointing at the shared grid shell, since both screens now share it.
- `workspace-2/hrms/CLAUDE.md` — a short paragraph next to "Regularization grid": the shared `SelectableGrid`, the `targets` pattern on both screens, "apply goes through the
  existing day writer — never a second writer".
- Update `.plans/` notes if a plan doc lists this as a gap.

## Files
The docs above; `workspace-2/hrms/CLAUDE.md`.

## Acceptance criteria
- [x] Docs match the code as shipped (routes, params, limits, skip reasons)
- [x] CLAUDE.md section added and links the docs
- [x] No stale "no bulk / no multi-cell" statements left in the shifts docs

Docs written from the shipped code (routes, params, caps, skip reasons read from router.py / schemas.py / service.py). SHF-G2 in .plans/attendance-shifts-leave-holidays-todo.md marked done. Shift-grid UI claims come from task 298 notes; browser behaviour was verified by the user, not re-run here.

Completed: 2026-10-28
