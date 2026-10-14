---
task: 187
title: Backfill employee_masters.department (free text) into department_master_id
status: ongoing
depends_on: []
---

# 187 — Backfill `employee_masters.department` (free text) into `department_master_id`

Work in **`workspace-2/hrms/`** (run `git -C workspace-2/hrms status -sb` first; it was 16 commits
behind `origin/feature/gowtham_AttendanceDateRange` on 2026-10-07, so pull first).

## Why
Parent goal (tasks 187–192): drop the legacy free-text column `employee_masters.department`
(`String(120)`) and drive every department read, filter and group-by off
`employee_masters.department_master_id` (FK → `department_masters.id`, already exists, indexed).

The column can't be dropped yet without losing data. Dev DB snapshot (`hrms_dev`, 2026-10-07):

| | employees |
|---|---|
| total | 1102 |
| `department` text set | 995 |
| `department_master_id` set | 243 |
| **text set, FK NULL (would lose their department)** | **758** |
| FK set but FK's name ≠ text (text is stale, as expected) | 77 |

The text-only rows are spread over ~30 CDPs. Most CDPs have no `department_masters` rows of their own.

## Scope
A one-off, idempotent backfill script `backend/scripts/backfill_department_master_id.py`, in the
same style as `scripts/cleanup_policy_data.py`: **dry run by default, `--apply` to write**,
`--cdp <id>` or `--all`, and a printed report.

For each active employee with `department` text set and `department_master_id IS NULL`, scoped per CDP
(employee → `corp_masters.care_delivery_program_master_id`):
1. Normalize the text (`strip`, collapse whitespace, case-insensitive compare).
2. Match an active, non-archived `department_masters` row by `department_name`: the employee's
   own CDP first, then CDP-0 (global). This is the same own-CDP-or-CDP-0 rule as
   `employees/service.py:_department_masters_for_tenant_and_global`. If the corp-scoped column on
   `department_masters` is set, prefer a row for the employee's corp.
3. **No match → create a `department_masters` row for that CDP** with the original text as
   `department_name` (once per distinct normalized name per CDP). *Decision to confirm before
   `--apply`: auto-create vs. leave NULL and report. The default here is auto-create, so no
   department is silently lost.*
4. Set `department_master_id`, and write the matching primary `employee_department_mappings` row
   the same way `employees/service.py:_set_employee_department` does. That way the directory's
   "all departments" view (`_department_names_by_employee`) agrees with the primary FK.

Do **not** touch rows that already have `department_master_id`. The 77 stale-text rows are fine,
because the FK wins.

The report lists, per CDP: matched (name → id), created departments, and employees updated.
Write a JSON backup of the original `(employee_id, department, department_master_id)` values
before `--apply` so the run can be reversed.

Out of scope: any code that reads `department` (tasks 188–190), and dropping the column (task 192).

## Files
- `backend/scripts/backfill_department_master_id.py` (new)
- `backend/app/tests/scripts/test_backfill_department_master_id.py` (new, or under `tests/modules/`
  following whatever existing script tests do)
- `backend/docs/…` or `docs/` runbook section. Add one short paragraph to the employees/department
  doc if one exists. Otherwise put the usage notes in the script's module docstring.

## Acceptance criteria
- [ ] Dry run prints, per CDP, what would be matched or created and the employee counts. It writes nothing.
- [ ] `--apply` leaves **0** active employees with `department` text set and `department_master_id IS NULL`
      (re-run the snapshot query in "Why").
- [ ] Re-running `--apply` is a no-op.
- [ ] Matching never crosses CDPs: an employee in CDP A is never pointed at CDP B's department.
      Covered by a test.
- [ ] Case and whitespace variants ("Nursing", " nursing ") map to one department, not two.
- [ ] Each updated employee has an active primary `employee_department_mappings` row.
- [ ] JSON backup written. Restore path documented (or `--restore <file>` implemented).
- [ ] `uv run pytest` green for the new tests.
