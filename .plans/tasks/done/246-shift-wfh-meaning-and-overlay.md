---
task: 246
title: Decide + implement what 'WFH' means on the roster 
status: done
depends_on: [240]
---

# 246 — Decide + implement what 'WFH' means on the roster 

## Scope
Two different things are called WFH here: (1) a work **location** HR assigns on the shift row
(no schema flag marks it remote today); (2) an **approved WFH request**
(`attendance_request_details.request_type='WFH'`, status 'Approved') / the `WFH` attendance status.
**Blocked until the requester confirms which they mean** (plan §2 recommends: #1 primary, #2 as a
read-only overlay).
Options once decided:
- 2a read-only overlay: roster day gains `wfh_request: bool` from approved WFH requests overlapping
  the day (one batched query); grid shows a WFH marker; no write path.
- 2b first-class remote flag: add `work_mode` (`OnSite|Remote|Hybrid`) to `work_location_masters`.
  **Schema change → follow `hrms-dbml-first`: draft `.plans/shift-wfh-schema.dbml`, STOP for approval
  before any model/migration.** The shared hrms-dev DB can't be `alembic upgrade`d — hand-written,
  existence-guarded migration (see CLAUDE.md).

## Files
Depends on the decision; see above.

## Acceptance criteria
- [x] Meaning confirmed with the requester and recorded here
- [x] Chosen option implemented with tests; grid distinguishes WFH clearly

## Decision (24-Oct-26)
Chosen by the user: **WFH = a work location HR assigns (already works — location badge on the cell) +
a read-only overlay of approved WFH requests** (option 2a). No schema change, so `hrms-dbml-first`
did not apply; `work_mode` on `work_location_masters` (2b) was not built.

## Implementation notes
- `ResolvedDayOut.wfh_request: bool` (schemas.py). `list_shift_roster` adds one batched query
  (tenant, employees `IN`, `request_type='WFH'`, `status='Approved'`, active, not archived, overlapping
  the window) — roster is now 4 queries regardless of head-count (query-count test still constant).
  Same predicate as the leave overlap gate (`leave/service.py`).
- Grid (`ShiftScheduling.tsx`): blue "WFH" tag on the cell corner (week view) / dot (month view), title
  gains "Approved WFH", "Approved WFH days" KPI tile, legend entry (only when the window has any). Cell
  stays clickable; the overlay never alters the shift/location shown.
- Tests: `test_roster_marks_days_covered_by_an_approved_wfh_request` (window overlap, Pending / Rejected /
  OnDuty / inactive / archived / other-tenant excluded, shift+location untouched),
  `test_roster_wfh_overlay_adds_one_query_not_one_per_employee`; equivalence test updated. 177 passed
  (test_shifts + carve).
- Browser smoke 7/7 (headless Chrome, local DB): no markers current week; 26 Oct week shows Priya
  27–29 + Kabir 30 Oct–1 Nov, not Arjun's Pending; KPI 6 + legend; month view 5; WFH cell still opens modal.
