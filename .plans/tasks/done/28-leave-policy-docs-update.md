---
task: 28
title: Reconcile docs/leave-and-attendance/leave/ docs with what was actually built
status: done
depends_on: [22, 23, 26, 27]
---

## As-built deviations from the spec below

- **The endpoint index's biggest correction wasn't the built/unbuilt split — it was that
  `GET /types` is admin-only, not "also M, S" as the pre-existing doc claimed.** Read
  `backend/app/modules/leave/service.py` directly: every function in the module calls
  `_require_admin(principal)` first, with no exception for `GET /types`. Restructured §3 into
  3.1 (admin, built), 3.1b (admin, not built), 3.2/3.3 (manager/self, entirely not built — no
  route exists for either role at all yet, not even a read-only one) rather than reusing the
  original "also M, S" annotations, which described an aspiration, not the shipped permission
  model.
- **`admin-configuration.md` §5.3 split into two outcomes, not one.** Most "no column" mockup
  fields (monthly cap, clubbing, backdating, comp-off fields, Approver: HR) were dropped from
  the UI entirely, confirmed by grepping `Leave.tsx`/`CreateLeaveTypeModal.tsx` for each label.
  But the two Maternity rows (`Eligibility (months)`, `Duration (weeks)`) were **not** dropped —
  their underlying `applicable_after_days`/`max_consecutive_days` columns are exposed in the
  built form, just in days (as the schema already stores them), never converted to months/weeks.
  The original single "drop from the UI" framing for the whole table would have been wrong for
  those two rows specifically.

# 28 — Reconcile docs/leave-and-attendance/leave/ docs with what was actually built

## Scope

`docs/leave-and-attendance/leave/` (`api-and-pages.md`, `admin-configuration.md`,
`domain-model.md`, `gaps.md`) currently describes the leave-policy admin flow as
**"planned, not built"** (`api-and-pages.md`'s banner line 9: `> **Status: planned, not built.**`).
Once tasks 21-27 land, that's no longer true for the types/policy slice — this task brings the
docs back in sync, the same way `.plans/tasks/done/17-shift-assignment-docs-update.md` and
`.plans/tasks/done/20-employee-shift-docs-update.md` did for the shift-assignment work. Read
those two done task files first as the template for *how* to phrase a "this is now built, here's
what changed vs. the original doc" update — don't invent a new doc-update style.

**This task does not touch** `ledger.md`, `manager-approvals.md`, or
`employee-self-service.md` — those describe the request/approval/ledger slice that remains
entirely unbuilt after task 27; leave their "planned" framing untouched.

## Files

- `docs/leave-and-attendance/leave/api-and-pages.md`
- `docs/leave-and-attendance/leave/admin-configuration.md`
- `docs/leave-and-attendance/leave/domain-model.md`
- `docs/leave-and-attendance/leave/gaps.md`
- `/home/solo/hrms/CLAUDE.md` — add a doc link only if one doesn't already exist for this corpus
  (check first: `grep -n "leave-and-attendance" CLAUDE.md` — if the whole corpus was never linked
  from CLAUDE.md, that's a pre-existing gap this task should fix while it's touching this area)

## Updates required

1. **`api-and-pages.md` line 9 banner** — replace "planned, not built" with what's actually true
   after task 27: the admin types/policy CRUD (§3.1's `/types`, `/policies`, `/policies/{id}`,
   `/policies/{id}/status` rows) is built; `/config`, `/employees/{id}/balances`,
   `/employees/{id}/ledger`, `/requests*` and everything under §2.2/§2.3 remain unbuilt. Split the
   endpoint table's rows (or add a status column) so a reader doesn't have to guess which half is
   real.
2. **Base path correction**: this doc already says `/api/v1/leave` (§3, consistent with what was
   actually built in [[22-leave-type-api]]) — confirm the built routes match exactly and fix any
   drift (e.g. if `service.py` ended up naming a path slightly differently than specced, the doc
   is what's wrong, not the code — CLAUDE.md's docs exist to describe reality).
3. **`admin-configuration.md` §5.3** ("Admin Console fields with no column") — for each row,
   confirm the built frontend ([[26-leave-policy-frontend]]/[[27-add-leave-type-flow]]) actually
   dropped the field from the UI as this doc prescribes (monthly cap, clubbing, backdating,
   comp-off fields, maternity-in-weeks). If the implementation made a different call for any of
   them, update the doc to match reality rather than leaving stale guidance.
4. **`domain-model.md` §5.2** — note that `leave_policy_audits` was added (not in the original
   12-table SQL sketch) and why (prompt §26's audit requirement, no generic audit table exists in
   this codebase — same reasoning as `shift_assignment_audits`). Cross-reference
   [[21-leave-policy-models-migration]].
5. **`gaps.md` #4** (`employee_type_master_id`) — confirm the "v1: NULL everywhere, resolve by
   corp only" resolution is exactly what got built ([[23-leave-policy-api]]'s
   `resolve_leave_policy`); if so, this gap can be marked resolved-for-v1 the same way gap #19
   already carries a `✅ ... — RESOLVED` heading in this same file — follow that exact heading
   convention.
6. **`gaps.md` #34** (gender vocabulary) — record that this task did **not** resolve it (per
   [[21-leave-policy-models-migration]]'s note): `gender_applicable` got a fixed
   `Male`/`Female`/`Other` vocabulary at the API layer, but `employee_masters.gndr` remains an
   unconstrained free string with no matching enforcement anywhere, because no request-flow code
   exists yet to do the matching. Leave this gap open, just make the note current.
7. **CLAUDE.md link check** — if `docs/leave-and-attendance/README.md` (or any file in that
   directory) is not currently linked from `/home/solo/hrms/CLAUDE.md`'s "Documentation" section,
   add one line there per that section's existing convention (matching how
   `docs/payload-encryption.md` and `docs/authentication-session-flow.md` are referenced) — this
   is a pre-existing gap, not something introduced by this task chain, but this is a natural point
   to fix it while already editing CLAUDE.md's neighborhood.

## Acceptance criteria

- [x] `api-and-pages.md`'s status banner accurately reflects the built/unbuilt split after task 27
- [x] Every endpoint path/shape in the doc matches the actually-implemented router exactly —
      verified by re-reading `backend/app/modules/leave/router.py` against the doc table, not
      from memory of what task 22/23 specced
- [x] `gaps.md` #4 gets the `✅ ... RESOLVED` treatment if and only if the built resolution logic
      matches; #34 stays open with an updated note
- [x] `domain-model.md` mentions `leave_policy_audits` as a deviation from the original 12-table
      SQL sketch, with the reasoning
- [x] CLAUDE.md links this doc corpus if it didn't already
- [x] No file outside `docs/leave-and-attendance/leave/` and `CLAUDE.md` is touched by this task

Completed: 2026-08-18
