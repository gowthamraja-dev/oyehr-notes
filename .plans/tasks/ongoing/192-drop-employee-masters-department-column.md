---
task: 192
title: Drop employee_masters.department column
status: ongoing
depends_on: [187, 188, 189, 190, 191]
---

# 192 — Drop `employee_masters.department`

Work in **`workspace-2/hrms/`**. The last step of the series (187–192). Only start this once every
reader (188–190) and writer (191) is off the column and the backfill (187) has been applied in each
environment that will receive this migration.

## Scope
1. Final sweep. These must return nothing outside migrations:
   `grep -rnw "department" backend/app backend/scripts | grep -v "department_master\|department_name\|department_id"`,
   then review every hit by hand (response field names called `department` that carry the FK name are fine).
   Also check `employeeapp/` (`MyTeam.js`, `Profile.js` show `department`). Confirm the backend
   responses they read still carry a `department` name.
2. Remove `department: Mapped[str | None] = mapped_column(String(120))` from
   `backend/app/models/employee_master.py`.
3. Alembic: `uv run alembic revision --autogenerate -m "drop employee_masters.department"`. Review it.
   The `downgrade()` re-adds the column **and** repopulates it from
   `department_masters.department_name` via `department_master_id`, so a rollback leaves usable data.
   Apply with `uv run python scripts/migrate.py upgrade heads` (not bare `alembic upgrade head`).
4. Pre-flight guard in the migration's `upgrade()`: if any active employee still has
   `department IS NOT NULL AND department_master_id IS NULL`, raise with the count. Do not silently
   drop unbackfilled data. Run task 187's script first.
5. Docs: update any doc that mentions the legacy free-text department fallback
   (`grep -rn "free-text" docs/`), and add a deploy note that 187's backfill must run before this migration.

## Files
- `backend/app/models/employee_master.py`
- `backend/alembic/versions/<new>_drop_employee_masters_department.py`
- docs mentioning the legacy column

## Acceptance criteria
- [ ] The migration upgrades and downgrades cleanly on a throwaway Postgres 18 (see memory: tests on
      throwaway pg). The downgrade restores names from the FK.
- [ ] The upgrade refuses to run while unbackfilled rows exist (tested).
- [ ] Full `uv run pytest` green (apart from the known `status_masters` seed failures). Frontend build clean.
- [ ] Smoke test in the browser: HR Manager attendance (filter + export), employees directory, shift
      roster, Add employee (Registration form with Department), payslip PDF.
