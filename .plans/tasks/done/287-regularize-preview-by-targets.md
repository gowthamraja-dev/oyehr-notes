---
task: 287
title: Regularize bulk preview accepts arbitrary cells (targets)
status: done
depends_on: []
---

# 287 — Regularize bulk preview accepts arbitrary cells (targets)

## Scope
`POST /attendance/regularize-range/bulk/preview` today takes `employee_ids` + one `from_date`/`to_date` rectangle (`RegularizeBulkPreviewIn`). The grid selects arbitrary cells, so
add an alternative body `targets: [{employee_id, dates[]}]` — the same shape `RegularizeBulkIn` (apply) already takes. Exactly one of (`employee_ids`+range) or `targets` must be given.
Same classifier (`regularize_range._classify`), same limits (50 employees, 1,000 employee-days PER REQUEST — the UI chunks, task 291), same 404-on-any-foreign-id rule, same gates
(APPROVE ATTENDANCE + org-wide scope). Apply is unchanged. Existing callers keep working until task 293 removes the old UI.

## Files
`backend/app/modules/attendance/schemas.py`, `regularize_range.py` (`preview_bulk`), `router.py` if the body type changes, `backend/app/tests/modules/test_regularize_range.py`.

## Acceptance criteria
- [ ] A `targets` preview returns the same per-day plan as the rectangle form for the same cells
- [ ] Both forms given, or neither -> 422; > 1,000 employee-days or > 50 employees -> 422
- [ ] A foreign-tenant employee id 404s the whole call; non-HR caller 403
- [ ] Existing rectangle tests still pass unchanged

## As built (2026-10-28)
`RegularizeBulkPreviewIn` (schemas.py) now takes either `employee_ids`+`from_date`+`to_date` or `targets`; `dates_by_employee()` feeds `regularize_range.preview_bulk`. Caps apply to either form. 6 new tests in `test_attendance_regularize_bulk.py`.

Completed: 2026-10-28
