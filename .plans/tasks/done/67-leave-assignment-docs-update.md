---
task: 67
title: Update leave-and-attendance docs for the leave assignment arc
status: ongoing
depends_on: [62, 65, 66]
---

# 67 — Update leave-and-attendance docs for the leave assignment arc

## Discussion

Per CLAUDE.md's "Documentation" convention and this module's own established pattern (every
prior arc closes with a docs-update task — [[17]], [[20]], [[28]], [[38]], [[51]]). Run last, once
[[61]]-[[66]] are all built, so the docs describe what actually shipped rather than a plan.

## Files — `docs/leave-and-attendance/leave/`

- **`gaps.md`** — gap #9 currently reads *"Partially resolved... But there is still no frontend
  for either... This gap re-opens fully on the frontend half; the backend half is done."* Update
  to reflect: the `employee_leave_assignments` table + friendly source-type vocabulary now exist
  ([[61]]/[[62]]), the ledger/assignment-history frontend exists ([[65]]), and the Assign Leave
  form exists ([[66]]) — mark the gap fully resolved, or narrow it to whatever, if anything, is
  still missing after those tasks land (e.g. if [[66]] shipped without a bulk/CSV import path,
  note that as a new narrower gap rather than leaving the old text stale).
- **`domain-model.md`** — add entries for `employee_leave_assignments` and
  `leave_assignment_audits` alongside the existing §5.3-§5.6 (`leave_request_details`,
  `leave_request_day_details`, `employee_leave_balance_ledgers`, `leave_request_audits`) —
  restate the exact column list from [[61]], not a summary, matching this doc's existing level
  of detail for the other four tables.
- **`ledger.md`** — §4 "Ledger entry per lifecycle event" table gets a new row (or rows) for
  "Leave assignment (Policy/Manual/OpeningBalance/CarryForward)", documenting the
  `source_type → txn_type` mapping [[61]]/[[62]] decided (`Policy→Accrual`, `Manual→Adjustment`,
  `OpeningBalance→Opening`, `CarryForward→CarryForward`) and *why* (the reasoning already written
  in [[61]]'s Discussion — restate it here, this is where a future reader of `ledger.md` alone
  will look for it). §7.4's idempotency-index note should mention that Policy-sourced assignments
  ride the same `Accrual` uniqueness protection, not a separate mechanism.
- **`vocabularies.md`** — add the `employee_leave_assignments.source_type`
  (`Policy|Manual|OpeningBalance|CarryForward`, explicitly noting CompOff/Import/Reversal are
  deliberately excluded and why, one line each) and `.status` (`Active|Cancelled`) vocabularies,
  next to the existing `txn_type` table (§7).
- **`api-and-pages.md`** — document the five endpoints from [[62]]
  (`POST/GET .../leave-assignments`, `GET .../leave-assignments/{id}`,
  `POST .../leave-assignments/{id}/cancel`, and the now-loosened `GET .../ledger`), plus the
  extended Manager Portal employee Leave tab (Ledger + Assignment History read sections from
  [[65]], the Assign Leave form from [[66]]) — follow this doc's existing per-endpoint
  request/response-shape format, don't just link to the code.
- **`README.md`** (repo root of this corpus, `docs/leave-and-attendance/README.md`) — no new file
  needed (this arc adds to existing docs, doesn't introduce a new one), but if the "Contents"
  table's one-line description for any of the five docs above no longer reflects what it covers,
  update that line.

## Acceptance criteria

- [ ] `gaps.md` gap #9 accurately reflects final state — resolved, or narrowed with a precise
      description of what's left.
- [ ] `domain-model.md`, `ledger.md`, `vocabularies.md`, `api-and-pages.md` each mention
      `employee_leave_assignments`/`leave_assignment_audits` with the same level of concrete
      detail (exact column/endpoint names) the rest of those docs already use — no doc merely
      says "see the code."
- [ ] No stale claim survives anywhere in this corpus (e.g. `ledger.md`'s "no ledger... UI"-style
      language, if any remains, is corrected).

