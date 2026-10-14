---
task: 51
title: Update the leave-and-attendance doc corpus to reflect the built request/approval flow
status: done
depends_on: [42, 43, 44, 45, 46, 47, 48, 49, 50]
---

## As-built notes

Went through every file this task listed, confirming each claim against the actual current code
(`app/modules/leave/router.py`/`service.py`/`schemas.py`, `Employee/MyLeave.tsx`,
`hrManager/Leave.tsx`, `hrManager/index.tsx`, `registry.ts`) rather than trusting the task file's
own pre-arc framing:

- **`README.md` §1.1** — Employee row already had a corrected `hr_employee`→`Employee/` dashboard
  note (from an earlier pass) but never mentioned the leave screen; added `MyLeave.tsx`. Manager
  row's "No leave queue screen yet" was fully stale — `Leave.tsx` (task 50) is real; also noted
  the still-missing manager-facing ledger view for completeness.
- **`leave/api-and-pages.md`** — flipped the top banner from "partially built" to "built, except
  `/config`"; folded §3.1b/§3.2/§3.3's "not yet built" proposal tables into built descriptions
  (all three predicates route through the same endpoints in `router.py`, gated in `service.py` —
  there's no separate manager/self copy of a route, which the old tables implied); corrected §2.2
  (dashboard path is `Employee/`, not `hrEmployee/`) and §2.3 (leave nav item is real); fixed the
  §4 intro's "aspirational" framing and §7's stale "41 tests" line (now 110, audited by [[48]]).
- **`employee-self-service.md`** / **`manager-approvals.md`** — both prerequisite notes rewritten
  from "doesn't exist" to built, with the real file/nav-key names.
- **`gaps.md`** — #11 and #27 are **fully resolved**, confirmed built exactly as proposed. #8 is
  **resolved with one open caveat**: cancellation itself is fully built, but
  `allow_retro_leave_cancellation` (cancelling a fully-past approved request) is still hardcoded
  off — no `tenant_params` storage exists for that knob, so it's a real remaining gap, not
  incidentally closed. **#9 turned out only partially resolved**, the one surprise in this pass:
  the admin ledger/adjust *endpoints* are real (HR can fix a balance without DB access via the
  API), but there is **no frontend at all** for either — no `src/lib/api.ts` wrapper, no screen in
  any dashboard. Left #9 without the ✅ heading since the UI half — the actual subject of the gap
  — is still completely missing; documented the split explicitly instead of fully closing it.
- **`implementation-structure.md`** — fixed §3's flatly-false "`backend/app/modules/leave/` does
  not exist yet" line, §7.2's `MyLeave.tsx` framing, and §7.3's most-stale claim in the whole
  corpus (`Leave.tsx` described as "a 4-line `<Placeholder />` wrapper, not a queue" — that
  self-described note had left leave scope "uninvestigated further"; now confirmed built, task 50).
- **`CLAUDE.md`** — **no change.** Considered a short mention of the ledger's
  `pg_advisory_xact_lock` pattern alongside Payload Encryption/Dynamic Forms, but
  `docs/leave-and-attendance/leave/ledger.md` §5.2 already documents it in full, and CLAUDE.md's
  own doc-linking rule is already satisfied by the existing "Leave & Attendance module has its own
  multi-file doc corpus" pointer. Adding a section here would just duplicate `ledger.md`.
- Gaps #1, #10, #29, #38, #40 left open and untouched, exactly as instructed.

# 51 — Update the leave-and-attendance doc corpus to reflect the built request/approval flow

## Discussion

Mirrors [[28-leave-policy-docs-update]]'s role for this arc. `docs/leave-and-attendance/leave/`
was written entirely as forward-looking design ("Status: partially built" / "not yet built" /
"aspirational" markers throughout `api-and-pages.md`, `ledger.md`, `employee-self-service.md`,
`manager-approvals.md`, `gaps.md`, `config-knobs.md`). Once [[42]]–[[50]] land, most of those
markers are stale. Go through each file and update status language the same way
[[26-leave-policy-frontend]]/[[27-add-leave-type-flow]]'s docs pass did for the types/policies
arc — **correct the record, don't rewrite the design**: the algorithms and rules in `ledger.md`
don't change, only the "is this built" framing around them.

## Files to update

- `docs/leave-and-attendance/README.md` — §1.1's persona/surface table (Employee "No `hr_employee`
  dashboard exists" line is already stale even before this task — correct it to describe the
  real `Employee/` dashboard and its `MyLeave.tsx`; Manager's "No leave queue" line becomes
  false once [[50]] lands)
- `docs/leave-and-attendance/leave/api-and-pages.md` — the top "Status: partially built" banner,
  §3.1b/§3.2/§3.3's "not yet built" tables move (fully or partially) into §3.1's "built" section
- `docs/leave-and-attendance/leave/employee-self-service.md` — the `hr_employee`-doesn't-exist
  prerequisite note
- `docs/leave-and-attendance/leave/manager-approvals.md` — the "no leave screen yet" framing
- `docs/leave-and-attendance/leave/gaps.md` — close what's actually resolved: #8 (cancellation
  now has a UI/flow — but note if `allow_retro_leave_cancellation` is still hardcoded off, per
  [[44]]'s discussion, that half of the gap stays open), #9 (ledger/adjustment now has a minimal
  UI via the admin adjustment endpoint — note if a *manager-facing* ledger view was still left
  out per [[45]]'s admin-only scoping), #11 (half-day/contact/attachment/preview — confirm
  which landed in [[49]]), #27 (approver_employee_master_id — confirm the column got added per
  [[44]]'s discussion)
- `docs/leave-and-attendance/shared/implementation-structure.md` — §3's phase-to-file mapping
  table (phases 5/6's leave rows), §7.2/§7.3's frontend tables (correct the `hrEmployee`/
  `LeaveQueue.tsx` predicted filenames to the real `Employee/MyLeave.tsx` /
  `hrManager/Leave.tsx` paths this arc actually used)
- `CLAUDE.md` — no change expected unless this arc introduced a genuinely new cross-cutting
  pattern beyond what's already documented (the ledger's advisory-lock pattern is arguably
  novel enough to warrant a one-paragraph mention alongside the existing Payload Encryption /
  Dynamic Forms sections, if not already covered by a linked doc — use judgment; don't add a
  section if `docs/leave-and-attendance/` already covers it adequately and CLAUDE.md's own rule
  is satisfied by the existing README.md link)

## Explicitly do not update

Leave `gaps.md` items #1 (comp-off), #10 (encashment), #29 (multi-stage approval display), #38
(backdating knob scope), #40 (mid-year corp transfer) as open — none of [[42]]–[[50]] resolve
them, per [[42]]'s own explicit scope note.

## Acceptance criteria

- [x] No file in `docs/leave-and-attendance/leave/` still claims "not yet built" for anything
      [[42]]–[[50]] actually shipped.
- [x] Every closed gap in `gaps.md` gets the same `### ✅ N. ... — RESOLVED` treatment already
      used for #4 and #19, with a one-paragraph "built exactly as proposed" or "built with this
      deviation" note, confirmed against the actual code (per those two existing resolutions'
      own stated standard — "confirmed directly against `backend/app/...`, not from memory of
      the spec").
- [x] Gaps not resolved by this arc are left open, explicitly, not silently dropped from the
      file.

Completed: 2026-08-19
