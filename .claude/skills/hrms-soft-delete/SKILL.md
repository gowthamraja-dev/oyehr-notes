---
name: hrms-soft-delete
description: >
  Every "delete" in HRMS is a soft delete — never a real SQL DELETE on a
  primary entity. Flip is_active=false and archive=true (+ archived_by_id/
  archived_at) instead, and every list/picker/report query on a table that
  carries those columns MUST filter them out. Use whenever adding a delete/
  remove/archive/deactivate action, adding a new table with a soft-delete
  need, or writing/reviewing any query that reads a table which has
  is_active/archive columns.
---

# HRMS soft delete — archive=true, never a real DELETE, and every read must filter it

Confirmed via a full-codebase audit (Sept 2026): **every** `@router.delete` endpoint in
this backend already does a soft delete — zero exceptions. The audit also found two
real, live bugs from the flip side of this rule: a query that read a soft-deletable
table but forgot to filter the flag, so an archived row kept showing up in a picker as
if it were still active. This skill exists so a third instance doesn't get written.

## The rule, in two halves

**1. Deleting/removing/archiving a row → never `DELETE`.** Set:
- `is_active = False` (if the table has it — most do)
- `archive = True`, `archived_by_id = <acting user id>`, `archived_at = <now, UTC>`
  (if the table has the trio — see "Which tables" below)

Re-activating (un-archiving) an existing row → reverse all of the above
(`is_active = True`, `archive = False`, `archived_by_id = None`, `archived_at = None`)
rather than inserting a duplicate row, if the feature supports re-activation at all.

**2. Reading a table that has these columns for a list, dropdown, picker, or report
→ always filter them out.** `Model.is_active.is_(True)` and, if the column exists,
`Model.archive.is_(False)`. An endpoint that skips this will show a row a user believes
was deleted — this is a real, user-visible bug class, not a theoretical one (see
"Real bug this caught" below).

The one carve-out: fetching a row **by its own id** for an edit/view/re-archive screen
(an admin opening an already-archived shift to look at it) legitimately skips the
filter — that's not a list, and the row exists on purpose. Don't add the filter to a
shared "get this one row by id" helper if it's also used by such a screen; see
`_require_assignable_shift` below for how to add a second, narrower helper instead of
widening a shared one.

## Which tables have `archive`/`archived_by_id`/`archived_at`

Most soft-deletable tables carry the full trio (`is_active` + `archive` +
`archived_by_id` + `archived_at`) — this is the default shape for any new table that
needs delete/deactivate. A few older tables only have `is_active` with no `archive`
column; if you're adding a delete/deactivate action to one of those, add the trio via
an Alembic migration first (see `2ad55304b3ca_add_archive_columns_to_provider_corp_.py`
for the exact shape: `Boolean server_default('false')` for `archive`, nullable
`BigInteger`/`ForeignKey("users.id")` for `archived_by_id`, nullable
`DateTime(timezone=True)` for `archived_at`).

**Watch for `archived_by_id` as a bare `ForeignKey("users.id")` breaking an existing
relationship.** If the table already has a SQLAlchemy `relationship()` to `User` keyed
on a different column (e.g. `user_id`), adding a second FK to `users` on the same table
makes that relationship ambiguous (`AmbiguousForeignKeysError` at first query, not at
migration time — it won't surface until something touches the relationship). Either add
`foreign_keys=[...]` to the relationship, or — simpler, and what this codebase already
does for `created_by_id`/`updated_by_id` everywhere — just use a plain `BigInteger`
column with no FK. `user_role_details.archived_by_id` is a live example of hitting this
and fixing it by dropping the FK.

## Real bug this caught, and the general shape of the fix

`payroll/service.py`'s Run Payroll "Department"/"Payroll Group" picker
(`_list_attribute_groups`) filtered `CorpParameterMaster.is_active`/
`CorpParameterValue.is_active` — but HR Attributes' own delete action
(`hr_attributes/service.py: delete_value`) only ever sets `archive = True` on those two
tables, never `is_active`. Result: an HR Admin archives a Department in Settings → HR
Attributes, and it never disappears from the Run Payroll picker — payroll could be run
against a group HR believed was removed. Fixed by adding `archive.is_(False)` alongside
the existing `is_active` check (additive — narrows results, changes nothing else).

`employees/service.py: list_reporting_managers` (the "Reports To" picker on Add/Edit
Employee) had no `is_active` filter at all, so a deactivated employee who once had a
direct report stayed selectable as someone's manager indefinitely. Fixed by adding
`EmployeeMaster.is_active.is_(True)` to its existing `.where(...)`.

When you add a new delete/archive action to any table, or a new query against a table
that already has one, check both directions:
1. Does the delete action set every flag the table has (`is_active` **and** `archive`
   where both exist), or does it silently miss one — leaving a different query that
   trusts the other flag blind to the deletion?
2. Does every new list/picker/report query filter every flag the table has?

## Pre-merge checklist for any new delete/archive action or new read of a soft-deletable table

- [ ] No `db.delete(...)`/`delete()`/`DELETE FROM` on a primary entity row — only
      allowed for genuine "replace the whole child set" patterns (e.g.
      `shifts/service.py: replace_week_offs`, `roles/service.py: _replace_statements`),
      never as a stand-in for a user-facing "delete this."
- [ ] The delete/archive action sets `is_active=False` AND, if the table has it,
      `archive=True` + `archived_by_id` + `archived_at` — together, not just one.
- [ ] Any re-activation path resets all of the same fields, not just `is_active`.
- [ ] Every new list/dropdown/report query on a soft-deletable table filters
      `is_active.is_(True)` and (if present) `archive.is_(False)`.
- [ ] A shared "get by id" helper used by BOTH an edit/view screen and an
      assignment/validation path is not blindly given an `archive` filter — if the
      edit/view use needs to reach an archived row, add a narrower wrapper for the
      validation path instead (see `_require_assignable_shift`/
      `_require_assignable_holiday_calendar` in `shifts/service.py`).
- [ ] Ran the affected module's tests after the change — this class of bug rarely
      throws an error, it just silently returns/hides one extra or one fewer row, so a
      passing test suite without a directed assertion won't necessarily catch it.
