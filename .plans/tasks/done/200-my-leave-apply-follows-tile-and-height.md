---
task: 200
title: My Leave — Apply form uses the selected tile; right column follows the Apply card's height
status: done
depends_on: [199]
---

# 200 — My Leave — Apply form uses the selected tile; right column follows the Apply card's height

Built in the top-level `hrms/` clone (branch `feature/gowtham_HrmsDevConfig`), uncommitted.
Follow-up to [[199]].

## Scope
`hrms/frontend/src/dashboards/Employee/MyLeave.tsx` only.

- **No leave-type dropdown.** `ApplyLeaveForm` takes a required
  `lockedType: { id, name, color } | null`. My Leave passes the selected balance tile — the
  same type the About card shows — and the form shows it as a read-only "Leave type" row
  ("Pick a tile above to change"). A tile the policy doesn't cover shows a note and leaves
  Submit disabled; `null` (no tiles) shows "No leave type to apply for yet". The form's
  apply-rule chips are gone (the About card shows them). My Leave is the form's only caller —
  the old docstring's "Home quick-action modal also uses it" was stale — so the dropdown
  was removed outright, not kept as a mode.
- Half-day values are only sent when the selected type allows half days, so switching tiles
  can't carry a stale half over.
- **Height:** the right column (Leave History over About) sits absolutely in its grid cell
  (`RIGHT_RAIL_CELL`/`RIGHT_RAIL_INNER`), so the Apply card sets the row height. It grows
  with the form (half-day, preview, document field), with a 620px floor. About fills the
  rest and scrolls inside itself. Below 1000px the column stacks with natural height.
  The skeleton uses the same wrappers.

## Acceptance criteria
- [x] Tile click switches both About and the Apply form's leave type; no dropdown on My Leave
- [x] Uncovered type → note + Submit disabled; no tiles → empty leave-type row
- [x] Right column height equals the Apply card's (620 floor, 738 / 758 as the form grew)
- [x] Dropdown removed from `ApplyLeaveForm` entirely (no other caller — grep-checked)
- [x] `tsc --noEmit` + eslint clean

Verified against mocked `/leave/*` responses on the running dev server (temporary preview
route, since deleted). Not checked with real login data.

Completed: 2026-10-08
