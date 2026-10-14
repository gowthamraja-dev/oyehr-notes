---
name: hrms-dbml-first
description: >
  Schema-first design gate for any HRMS feature that adds or changes tables/columns. Before any
  plan, task file, model, or migration is written, draft the proposed schema as DBML
  (`.plans/<feature>-schema.dbml`, pasteable into dbdiagram.io) with a feasibility review against
  the existing schema in its Project note, and STOP for the user's approval. Only after the
  schema is approved, write the plan (`.plans/<feature>-plan.md`) and split it into task files via
  `hrms-task-tracker`. Use whenever the user asks to plan/design/POC a feature that touches the
  database, asks for a DBML/schema/DDL draft, or asks for a schema/feasibility review before planning.
---

# HRMS DBML-first design gate

Schema is the most expensive thing to get wrong. Once a migration is applied, it can't be
edited, only followed by another one (see CLAUDE.md "Migration workflow"). This skill makes
the user approve the **data model**, as a DBML diagram, before anyone writes a plan, task,
model file, or migration.

```
Phase 1  DBML draft + feasibility  → .plans/<feature>-schema.dbml   (STATUS: draft)
         ── STOP: user reviews (pastes into dbdiagram.io) ──
Phase 2  approved                  → same file                       (STATUS: approved, date)
Phase 3  plan                      → .plans/<feature>-plan.md
Phase 4  tasks                     → .plans/tasks/ongoing/NN-*.md    (hrms-task-tracker)
```

Always DBML. Don't write SQL `CREATE TABLE` drafts. The reference file for style is
`.plans/attendance-punch-import-schema.dbml`.

## Phase 1: draft the DBML (read-only phase)

**Allowed:** reading code, models, migrations, and docs, and running read-only queries
(`SELECT`, `\d`) against a dev DB.
**Not allowed:** creating model files, migrations, task files, a plan doc, or a branch.

1. **Survey what exists first.** Before proposing a new table:
   - read the related models in `hrms/backend/app/models/`;
   - grep for a table that already does the job, or a pattern to copy (e.g. a polymorphic
     `provider_type`/`provider_id` mapping like `leave_policy_provider_mappings`);
   - check how the data is written today (services, nhforms subscribers in
     `app/modules/forms/subscribers.py`, importers).

   Prefer extending or mirroring an existing shape over inventing a new one.
2. **Write `.plans/<feature>-schema.dbml`** with this layout, in this order:

   ```dbml
   // <Feature> — schema draft
   // STATUS: draft            (draft → approved → superseded)
   // CLONE: hrms | workspace-2/hrms
   // APPROVED_ON:
   // Paste into https://dbdiagram.io (DBML). Plan (after approval): .plans/<feature>-plan.md
   //
   // Header colours:
   //   green  #2E7D32  NEW table
   //   orange #EF6C00  existing table that GAINS columns
   //   grey   #616161  existing, read only / referenced (columns trimmed)
   // Column notes: [NEW] = added by this feature. "logical" = plain bigint, no FK constraint.

   Project <feature_snake> {
     database_type: 'PostgreSQL'
     Note: '''
     ## Why
     ## Feasibility        (checklist below, each line ✅ / ⚠️ note / ❌ blocker)
     ## Alternatives considered
     ## Open questions     (numbered)
     '''
   }

   Enum ...                 // varchar-backed value sets (note: 'varchar(N)')
   Table ... [headercolor: #2E7D32] { ... Indexes { ... } Note: '[NEW] ...' }
   Table ... [headercolor: #EF6C00] { ... }      // only the existing + [NEW] columns that matter
   Table ... [headercolor: #616161] { ... }      // trimmed reference tables
   TableGroup ...
   ```

   Rules for the tables:
   - Use real Postgres types (`bigint`, `varchar(120)`, `boolean`, `date`, `timestamptz`,
     `jsonb`) and write defaults as they will be in the DB (`default: true`,
     `` default: `now()` ``).
   - Draw real FKs as `ref: >`. A polymorphic or logical id has no ref; put the allowed values
     or target in its `note:`.
   - Write partial or unique indexes as `(cols) [unique, name: '…', note: 'WHERE …']`. DBML
     can't express a WHERE clause, so the note carries it.
   - Each new table's `Note:` names its model file and class, e.g.
     `[NEW] app/models/foo_bar.py → FooBar`.
   - Keep the Project note short. It's a review document, not the plan. Behaviour, APIs and
     UI belong in the plan, written after approval; mention them only where they explain a
     column.
3. **Stop and ask for approval.** Reply with:
   - the file path;
   - a 3–6 line summary of the tables and columns;
   - every ⚠️ and ❌;
   - the open questions.

   Do not continue to Phase 3 in the same turn.

### Feasibility checklist (answer every line in the Project note)

- **Tenant scoping**: every tenant-owned table has NOT NULL
  `care_delivery_program_master_id → care_delivery_program_masters.id`. There's no RLS, so
  say which queries must filter on it.
- **Conventions** (CLAUDE.md "Column conventions"):
  - `id bigint [pk]`;
  - NOT NULL + default → a DB default, i.e. `server_default` on the model;
  - `timestamptz` for `created_at`/`updated_at`;
  - `jsonb` only for blobs that are never queried;
  - reserved column names get a safe Python attribute.
- **Soft delete**: primary entities carry `is_active`, `archive`, `archived_by_id`,
  `archived_at` (`hrms-soft-delete`). Note which list queries must exclude archived rows.
- **Audit**: `created_by_id`, `updated_by_id`, `created_at`, `updated_at`.
- **FKs**: a real ref where the target table exists. Otherwise a logical bigint (e.g.
  `designation_master_id`). For polymorphic `(x_type, x_id)` pairs, list the allowed
  `x_type` values.
- **Indexes**: one per access path the feature will query (tenant + lookup key), with
  names in the existing style.
- **Existing data**: for altered tables, whether the column is nullable or needs a backfill.
  Adding a NOT NULL column without a default to a populated table is a ❌ unless a backfill
  step is planned.
- **Overlap**: no existing table already stores this. Name the closest one you checked.
- **Write paths**: every code path that must write or keep the new data consistent
  (UI endpoint, nhforms submit subscriber, CSV import, scheduled job).
- **Migrations**: plain Alembic revision on the HRMS branch, applied via
  `scripts/migrate.py upgrade heads`. Flag anything touching nhforms-owned tables (❌,
  that's the package's branch).
- **RBAC**: which `permissions.py` resource/action gates writes to it.
- **Cloud fit**: no local-disk or in-process state (CLAUDE.md "Cloud setup").

## Phase 2: approval

Only an explicit approval from the user counts ("approved", "go ahead with the schema",
"looks good, plan it"). Edits requested during review → update the DBML, re-summarise the
diff, and ask again.

On approval: set `// STATUS: approved` and `// APPROVED_ON: YYYY-MM-DD`, and record the
answers to the open questions in the Project note (`Decided: …`). From here on the approved
DBML is the contract.

## Phase 3: plan

Write `.plans/<feature>-plan.md` that **links the approved DBML instead of restating it**.
Sections: Scope (incl. explicitly out of scope) · Flow · Backend (services, endpoints, gates,
write-path hooks) · Frontend (screens, components) · Tests · Open decisions. Follow the shape
of `.plans/attendance-punch-import-plan.md`.

## Phase 4: tasks

Split the plan with `hrms-task-tracker`:
- Number from the highest existing number across `.plans/tasks/ongoing/` and `done/`, + 1.
- The **first task is always "models + migration"**, and it implements the approved DBML
  exactly. Its acceptance criteria include: the migration matches the DBML and has been
  reviewed, it applies on a fresh DB, and `alembic check` is clean.
- Every task file restates the columns and contracts it needs. Don't just point at the plan.

## Changing an approved schema

Never edit an approved DBML in place to match what got built. If the schema needs to change:
- **before its migration is applied:** revise the file, set `STATUS: draft`, and get
  approval again;
- **after it's applied:** write a new `<feature>-schema-v2.dbml` (changes only), set the old
  file to `STATUS: superseded`, then get approval and add a new task.
