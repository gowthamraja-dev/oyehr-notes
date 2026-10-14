---
task: 162
title: employee_masters.leave_policy_master_id + resolution order (employee → department → employee type → CDP)
status: done
depends_on: [161]
---

# 162 — Column + migration + new resolution order

**Where:** top-level `hrms/` (`feature/gowtham_LeaveMasters`). Decisions D1–D5 are in 161.

## Scope
- **Model:** add `employee_masters.leave_policy_master_id`, typed
  `Mapped[int | None] = mapped_column(ForeignKey("leave_policy_masters.id"), index=True)`.
  NULL means not pinned.
- **Migration:** hand-written and existence-guarded (the shared hrms-dev DB is stamped at an
  orphan revision; see `domain-model.md` §5.2.5). It uses `ADD COLUMN IF NOT EXISTS` + FK + index.
  Downgrade drops them.
  **Applying it to the shared DB needs the user's go-ahead.** It is additive and nullable, so
  other branches are unaffected, but the test suite needs the column to exist.
- **Resolution** (`app/services/leave_policy_resolution_service.py`):
  - Replace priority-first ranking with a **fixed level order**:
    `EMPLOYEE_PIN (column) > EmployeeMaster mapping (legacy) > DepartmentMaster > EmployeeTypeMaster > CorpMaster > CareDeliveryProgramMaster`.
    Within a level: `priority`, then newest `effctv_dt`, then highest id.
  - **The pin is a candidate.** If `employee.leave_policy_master_id` points at a policy that is
    live on `as_of` and in the tenant, it wins, as a synthetic `MappingCandidate` with
    `provider_type="EmployeeLeavePolicy"`, `mapping=None`, labelled "Employee's own policy". If the
    policy isn't live, it is skipped, with a note: "Pinned policy X is archived/inactive — using …".
  - **Keep the batch paths' fixed query count.** `resolve_details_for_employees` and
    `provider_keys_for_employees` load the pinned policies in one query.
  - A mapping-only helper, `resolve_from_mappings(db, tenant_id, employee, as_of)` (levels 2→5,
    ignoring the pin), is what 163 and 164 use to compute the value to pin.
- **Explainer / `/me/policy` schemas:** a candidate can now have no mapping. `ResolutionCandidateOut`
  gets `mapping_id: int | None` and `provider_type="EmployeeLeavePolicy"`. The frontend
  `PolicyResolutionPanel` renders it as "Employee's own policy" with no priority.
- **Assignments UI** (`PolicyAssignments.tsx` + `assignment_service`): stop offering the
  `EmployeeMaster` provider for new assignments (422 on create; existing ones stay editable and
  archivable). The hint says: "To give one employee a specific policy, set it on the employee."
  Update the precedence text (L474-ish) to **Employee › Department › Employee Type › Corp › All
  employees**.

## Files
- `backend/app/models/employee_master.py`, plus a new `alembic/versions/<rev>_employee_leave_policy_master_id.py`
- `backend/app/services/leave_policy_resolution_service.py`
- `backend/app/modules/leave/schemas.py`, `assignment_service.py`
- `frontend/src/lib/api.ts`, `dashboards/shared/PolicyResolutionPanel.tsx`,
  `dashboards/hrAdmin/Leave_components/PolicyAssignments.tsx`
- Tests: `test_leave_policy_resolution.py` (level order, pin, dead pin falls through, within-level
  priority, batch path), `test_leave_policy_assignments.py` (explainer shows the pin; EmployeeMaster
  create is refused)
- Docs: `ledger.md` §7.1 (the winner rules), `domain-model.md` §5.2.3, and the 161 doc

## Progress (30-Sep-26)
- The column, FK and index were **applied to hrms-dev** with the user's approval, via migration
  `7a4c2e8f1b36`'s `upgrade()` in one transaction. All rows are NULL.
- Resolution: `PROVIDER_LEVEL` replaces `PROVIDER_SPECIFICITY`. `PINNED = "EmployeeLeavePolicy"`.
  `MappingCandidate.mapping` is None for the pin. Added `_live_pinned_policies`,
  `resolve_from_mappings(_for_employees)`, and a dead-pin note in `explain()`. `PROVIDER_TYPES`
  is unchanged in content, but no longer derived from the specificity map.
- Tests changed because the old expectations assumed priority-first:
  - `test_scenario_7_…` now expects Department to win.
  - The winner-takes-all, batch and explain tests expect CLINICAL.
  - `_dr_ananya` and the `/me/policy` Doctor test swap which provider each policy is on, so the
    same policy still wins by level.
- New tests: level beats priority, pin wins, dead pin (×4) falls through with a note, a
  fixed-query-count batch, the explainer showing the pin, and the retired EmployeeMaster provider.
- Frontend: candidate types allow a null `mapping_id`/`priority`. The panel renders
  "Employee's own policy". The assignment modal no longer offers Employee except when editing a
  legacy row. The precedence hint is rewritten.
- Docs: `ledger.md` §7.1 (steps + worked example), `admin-configuration.md`, and `domain-model.md`.

## Acceptance criteria
- [x] A pinned, live policy wins over every mapping, and a dead pin falls through to the mappings.
- [x] Department beats Employee Type beats Corp beats CDP, **whatever their priorities**. Priority
      only orders mappings within one level.
- [x] `resolve_details_for_employees` still uses a fixed number of queries (assert with a query counter).
- [x] The explainer shows "Employee's own policy" as the selected candidate when pinned.
- [x] Creating an `EmployeeMaster` assignment returns 422 with the hint.
- [x] `uv run pytest app/tests/modules/test_leave*.py` is green (342 passed with test_gender), and tsc/lint are clean.

Completed: 2026-09-30
