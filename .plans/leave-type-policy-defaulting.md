# Plan — Leave Type / Leave Policy: multi-policy, no manual employee mapping, default policy

Status: **planning only** — no code in this doc's scope. Produced to answer a specific brief:
*"analyze and plan the leave type and leave policy design where one leave type can have multiple
policies, without adding new fields or manual employee mapping, with a default leave
type/policy."*

## 0. Headline finding — this already exists, built to spec

`hrms/backend/app/modules/leave/` (models, `service.py`, `router.py`, `schemas.py`) and
`hrms/backend/app/tests/modules/test_leave.py` (≈2988 lines, ~120 tests) already implement leave
types and leave policies exactly along the three constraints in the brief. Nothing here requires
a new column, a new table, or new manual per-employee mapping. This plan documents *why* that's
true, names one piece of stale repo state to clean up, and lists the few genuinely open items
that are in-scope for this concept without violating the "no new fields / no manual mapping"
constraint.

Read together with the existing doc corpus this plan does not duplicate:
- `hrms/docs/leave-and-attendance/leave/domain-model.md` §5.1–5.2 (`leave_type_masters`,
  `leave_policy_details` — exact column lists)
- `hrms/docs/leave-and-attendance/leave/admin-configuration.md` (mockup field → column mapping)
- `hrms/docs/leave-and-attendance/leave/gaps.md` (open decisions, numbered, global across the
  `leave-and-attendance` corpus)
- `hrms/docs/leave-and-attendance/leave/ledger.md` §7.1 (policy resolution / precedence detail)

## 1. "One leave type, multiple policies" — already built

- `leave_type_masters` (file `leave_type_master.py`) is the type definition — one row per leave
  category (Earned Leave, Sick Leave, …), scoped by `care_delivery_program_master_id` (the CDP,
  i.e. the tenant) with `UniqueConstraint(care_delivery_program_master_id, code)`.
- `leave_policy_details` (file `leave_policy_detail.py`) is a **separate, many-per-type** table:
  `leave_type_master_id` is a plain FK with no uniqueness constraint against it, so a type can
  have any number of policy rows. Two axes already produce genuine multiplicity without any new
  column:
  1. **Corp axis** — `corp_master_id` (nullable FK to `corp_masters`). A policy with
     `corp_master_id = NULL` applies to every corp under the tenant (see §3, "default policy"
     below); a policy with `corp_master_id` set overrides it for that one corp only.
  2. **Time axis** — `effctv_dt`/`trmntn_dt` (the same effective-dating pattern used everywhere
     else in this codebase). Multiple policy rows for the *same* leave type and the *same* corp
     (or the same all-corps slot) can coexist as long as their date ranges don't overlap;
     `service.py:_check_no_overlap` enforces that at write time (app-level, not a DB constraint —
     matches this table's existing pattern for every other cross-row rule in this module).
- Resolution — `service.py:resolve_leave_policy(db, tenant_id, leave_type_master_id,
  corp_master_id, as_of)` — picks *one* applicable policy at read/apply time: corp-specific row
  (if any, as of that date) wins, otherwise the all-corps row (if any, as of that date). This is
  computed fresh on every call (leave apply, preview, balance, ledger, accrual) — nothing is
  cached or pre-assigned per employee.

**No new field is needed for this axis.** The multiplicity already comes from `leave_policy_details`
being a child table, not from any column on `leave_type_masters` itself.

## 2. "No manual mapping to employees" — already the architecture, and deliberately so

> **⚠️ Superseded (29-Sep-26, tasks 137–148).** This section describes corp-only resolution
> with no mapping table. That is no longer the design. Policies are now **policy masters** with
> one rule per leave type, and reach employees through `leave_policy_provider_mappings`
> (Employee / Department / Employee Type / Corp / All employees, by priority). Resolution is still
> computed, never stored per employee, but it is driven by those assignments. The old
> per-type rules were backfilled into a `DEFAULT` policy assigned to all employees at priority 0.
> See `hrms/docs/leave-and-attendance/leave/domain-model.md` §5.2 and `ledger.md` §7.1. The text
> below is kept as the record of the earlier decision.

There is **no employee-to-policy assignment table today**. An employee's applicable policy is
computed, not stored: `resolve_leave_policy(..., employee.corp_master_id, as_of)` derives it
purely from the employee's own `corp_master_id` (a column that already exists on
`employee_masters` for unrelated reasons — corp membership) at the moment it's needed. Nobody
picks a policy for an employee; the corp they already belong to picks it for them.

### Important repo-state finding: a manual-mapping feature *was* built, then reverted

A parallel effort (`.plans/tasks/done/61`–`66`, "leave assignment") built exactly the kind of
manual per-employee mapping the brief says to avoid: an `employee_leave_assignments` table (HR
picks an employee + leave type + a `source_type` of `Policy|Manual|OpeningBalance|CarryForward`
and an amount) plus a `leave_assignment_audits` table and an "Assign Leave" frontend drawer.

That work was **later reverted** — `hrms/backend/alembic/versions/30e3ca4fa149_drop_employee_leave_assignments.py`
(dated 2026-09-01, applied after task 61 which completed 2026-08-19) drops both tables and the
traceability column it had added to `employee_leave_balance_ledgers`. The migration is real and
applied; the model files (`employee_leave_assignment.py`, `leave_assignment_audit.py`) are **not**
present in `app/models/` or `app/models/__init__.py` today — only stale `.pyc` files remain in
`__pycache__`, confirming the code was removed, not just the table.

**But the task tracker was never reconciled with the revert:**
- `.plans/tasks/done/61` through `66` still read as completed and current.
- `.plans/tasks/ongoing/67-leave-assignment-docs-update.md` is still sitting open, instructing a
  future session to document `employee_leave_assignments` in `domain-model.md`, `ledger.md`,
  `vocabularies.md`, and `api-and-pages.md` — i.e. to write docs for a table that no longer
  exists.
- `hrms/docs/leave-and-attendance/leave/gaps.md` gap #9 still describes the ledger/adjustment UI
  gap in terms that predate this revert (it correctly says the frontend is missing, but doesn't
  mention the assignment arc was built and pulled back out).

**Action item (housekeeping, not a feature build):**
1. Move `.plans/tasks/ongoing/67-leave-assignment-docs-update.md` to `done/` with its status
   changed to **superseded/cancelled** (not completed) and a one-line note pointing at
   `30e3ca4fa149_drop_employee_leave_assignments.py` as the reason — so a future session doesn't
   pick it up and write docs for dropped tables.
2. Add a short note to `.plans/tasks/done/61`–`66` (or a single new note at the top of `61`, since
   it's the first in the chain) recording that this arc was reverted by `30e3ca4fa149`, so anyone
   reading the done/ chain understands `employee_leave_assignments` is gone, not just undocumented.
3. Do **not** re-read tasks 61–66 as a blueprint to rebuild manual assignment — the brief this
   plan answers explicitly rules that back in, and the revert appears intentional (a full,
   deliberate down-migration, not an accident).

This finding matters because it's the one place in the repo where "no manual mapping to
employees" isn't just a design choice to make going forward — it's a design choice that was
already tried, in code, and then undone. Restating it here keeps it from being silently
reintroduced.

## 3. "Default leave type/policy" — an existing but unnamed concept; formalize it in docs

The all-corps policy (`corp_master_id IS NULL`) **already functions as the default** in the
running code — `service.py:_default_policy_summary` resolves it (`resolve_leave_policy(db,
tenant_id, leave_type_id, corp_master_id=None, date.today())`) to build the summary string
(e.g. `"21 days · Monthly"`) shown in the leave-type list. Every corp that has no
corp-specific override transparently falls back to this row. This is precisely a "default
policy" — it just isn't named that anywhere in the docs or the API surface.

**No new column is needed.** `corp_master_id IS NULL` already *is* the default marker; adding an
`is_default` boolean would be a second way to say the same thing and risks the two disagreeing
(e.g. an admin creates an all-corps row without also flipping a separate flag). The plan is to
formalize and document the existing semantics, not add a field:

1. **Docs**: add a named "Default policy" subsection to
   `hrms/docs/leave-and-attendance/leave/ledger.md` §7.1 (where `resolve_leave_policy`'s
   precedence is already documented) stating explicitly: *"a policy with `corp_master_id = NULL`
   is the leave type's default policy — every corp without its own override resolves to it. A
   leave type with zero all-corps policy and zero matching corp-specific policy has **no**
   applicable policy, and `resolve_leave_policy` returns `None`"* (confirm and document what
   currently happens downstream when that's `None` — see §4 below).
2. **API surface**: `LeaveTypeOut.policy_summary` (already returned today from
   `_default_policy_summary`) is de facto "the default policy's summary." Rename the *concept* in
   docs/comments to make this explicit (e.g. clarify in `schemas.py`'s docstring for
   `policy_summary` that it always reflects the all-corps/default policy, never a corp-specific
   override, even if the viewing admin's own corp has one) — a documentation/comment change, not
   a schema change.
3. **Admin UX** (frontend, no backend field): when an admin creates the *first* policy for a new
   leave type in `LeaveTypeWizard.tsx`, default the "Applies to" selector to "All corps" (i.e.
   `corp_master_id = NULL`) rather than forcing a corp pick — so the natural path produces a
   default policy without the admin needing to understand the precedence rule up front. Purely a
   frontend initial-value change; the field (`corp_master_id`, nullable) already exists.

## 4. What happens with **no** applicable policy at all — a real, small gap worth closing

`resolve_leave_policy` returns `None` when a leave type has no all-corps row and no matching
corp-specific row (e.g. right after a brand-new leave type is created with zero policies yet).
Walking the call sites (`service.py` lines ~440, 1267, 1365, 1558, 1699, 1796, 1909):
`_default_policy_summary` handles `None` gracefully (returns `None`, UI just shows no summary
text), but the leave-apply/preview path's behavior on a `None` policy should be confirmed and, if
not already, made to fail with a clear, admin-actionable error (*"This leave type has no active
policy configured — add a default policy before employees can apply"*) rather than a generic
500/None-attribute error. This is a defensive-validation check, not a new field or table — a
guard clause plus (if missing) a dedicated exception message, mirroring the existing gate style in
`service.py` (tenancy/type-in-force/gender/probation/date-sanity/notice/overlap/balance/document
gates already documented in `test_leave.py`).

**Acceptance shape for this item** (to become a real task later, not executed by this plan doc):
- [ ] A leave type with zero policies, when an employee attempts to apply, returns a clear 4xx
      with a specific error message distinguishing "no policy configured" from other validation
      failures — covered by a new test in `test_leave.py` alongside the existing gate tests.
- [ ] The Admin Console's leave-type list visibly flags a type with no default (all-corps) policy
      (e.g. "No default policy set" instead of a blank `policy_summary`), prompting the admin to
      add one — frontend-only, no schema change.

## 5. Explicitly out of scope for this plan (do not fold in)

To keep this plan aligned with "don't add new fields, don't add manual employee mapping":

- **Not** reintroducing `employee_leave_assignments` or any HR-picks-an-employee assignment flow
  (§2) — superseded by the revert.
- **Not** an `employee_type_master_id`-based third precedence tier (`gaps.md` #4) — that table
  doesn't exist yet; the resolution function already has a one-line hook for it, deliberately
  left unused until the master table is built. Revisit only when `employee_type_masters` exists.
- **Not** comp-off earning (`gaps.md` #1), encashment flow (`gaps.md` #10), sandwich-leave rules
  (`gaps.md` #13), or `unit = 'Hour'` (`gaps.md` #14) — all real gaps, but orthogonal to the
  type↔policy↔defaulting question this plan answers, and several would need new columns (e.g. an
  expiry-window column for comp-off), which the brief rules out.
- **Not** `max_backdated_leave_days` placement (`gaps.md` #38) or mid-year corp-transfer accrual
  ownership (`gaps.md` #40) — real open decisions, but they're about *when* a policy applies to a
  request, not about *how many* policies a type can have or *whether* mapping is manual; track
  separately.

## 6. Summary — what to actually do next

Everything in §1–§3 is already correct in the running code; the only actions this plan calls for:

1. **Housekeeping** (§2): retire `.plans/tasks/ongoing/67-leave-assignment-docs-update.md` as
   superseded, and annotate `.plans/tasks/done/61` with the revert, so the task tracker stops
   describing a table that was deliberately dropped.
2. **Docs-only** (§3): name and document the existing "default policy" (`corp_master_id IS NULL`)
   concept in `ledger.md` §7.1 and `schemas.py`'s `policy_summary` docstring — zero schema change.
3. **Small defensive-validation task** (§4): turn the "leave type with no applicable policy"
   `None`-return case into a clear, tested, admin-actionable error — a guard clause, not a new
   field or table; write this up as a normal `.plans/tasks/ongoing/` task when ready to execute.
4. **Frontend default-value nudge** (§3.3): `LeaveTypeWizard.tsx`'s first-policy step defaults
   "Applies to" to All corps — a frontend initial-state change using the existing nullable
   `corp_master_id` field.

No new backend column, table, or manual employee-mapping mechanism is required for any of the
above.
