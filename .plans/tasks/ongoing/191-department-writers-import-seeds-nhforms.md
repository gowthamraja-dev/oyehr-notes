---
task: 191
title: Stop writing employee_masters.department — import, seeds, nhforms EMPDP
status: ongoing
depends_on: [187]
---

# 191 — Writers: employee import, seed scripts, nhforms registration (`EMPDP`)

Work in **`workspace-2/hrms/`**, plus the **`../nhforms`** package repo for the EMPDP change.
Part of the "drop `employee_masters.department`" series (187–192). After this task nothing writes the
legacy column, so task 192 can drop it.

## Current writers
- **nhforms registration** (the "Add employee" flow, so this is load-bearing):
  `nhforms/core/constants.py: CODE_TO_COLUMN` maps `"EMPDP": "department"`, so a Registration-form
  answer for the Department question is written into `employee_masters.department`.
  `nhforms/builder/registration_defaults.py:48` seeds EMPDP as a **text** field
  (`_TEXT_FIELD_TYPE_ID`). HRMS-side seeders do the same:
  `backend/scripts/seed_edit_profile_form.py:63` (`("Department", "EMPDP", TEXT_FIELD, False, "department")`)
  and `seed_employee_registration_form.py`.
  **If the column is dropped before this changes, every registration that answers Department breaks.**
- `backend/app/modules/employee_import/service.py`: the mapping key `department` (L54). The value is
  resolved to `_department_master_id` only when the tenant has departments (L356–365), and both
  `department=` and `department_master_id=` are written (L391–392). A tenant with no departments
  imports free text with no FK.
- Seeds: `scripts/seed_dev.py` (~L268–338), `scripts/seed_realistic_dataset.py` (~L127–283),
  `scripts/seed_employee_user.py:136` write `department=` names.
- `scripts/delete_department_attribute.py`: read it and decide whether it is now obsolete or needs updating.

## Scope
1. **nhforms** (separate repo `../nhforms`, publish to CodeArtifact, then `uv add nhforms==<new>`):
   EMPDP becomes a **select** sourced from `department_masters` (own CDP + CDP-0, active,
   non-archived) and maps to `department_master_id`. Validate that the chosen id belongs to the
   submitting CDP. Also create the primary `employee_department_mappings` row. Check whether
   `target_logic`'s existing `employee_department_mappings` support already covers this. Keep
   EMPFN/EMPMB untouched (see CLAUDE.md "EMPFN/EMPMB are load-bearing").
   Migrate existing Registration / edit-profile forms' EMPDP question from text to select, with a
   data migration or a re-run of the seed scripts per CDP. Document which.
2. **Employee import**: an unknown department name is always a row error (even for a tenant with no
   departments yet, where the message says "add it in Organization Settings first"). Write only
   `department_master_id` (+ primary mapping row), never `department`.
3. **Seeds**: create or look up `department_masters` rows and set `department_master_id`. Never set `department`.
4. Update CLAUDE.md's dynamic-forms section if the EMPDP contract changes in a way admins must know.

Out of scope: readers (188–190), the column drop (192).

## Files
- `../nhforms/nhforms/core/constants.py`, `…/builder/registration_defaults.py`, the submission
  registration/target logic, the nhforms tests, version bump
- `backend/pyproject.toml` / `uv.lock` (new nhforms version)
- `backend/app/modules/employee_import/service.py`, `backend/app/tests/modules/test_employee_import.py`
- `backend/scripts/{seed_dev,seed_realistic_dataset,seed_employee_user,seed_edit_profile_form,seed_employee_registration_form}.py`

## Acceptance criteria
- [ ] `grep -rn "department=" backend/app backend/scripts` shows no write to `EmployeeMaster(department=…)`
      / `emp.department = …`.
- [ ] Add employee through the Registration form with a Department chosen: the employee row has
      `department_master_id` set, a primary mapping row exists, and `department` stays NULL. A
      department id from another CDP is rejected.
- [ ] Employee import: a known name → FK set; an unknown name → row error; cross-CDP names never match.
- [ ] `seed_dev.py` runs clean on a fresh DB.
- [ ] nhforms tests green, new version installed, HRMS `uv run pytest` green.
