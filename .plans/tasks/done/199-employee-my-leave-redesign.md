---
task: 199
title: Employee My Leave tab redesign — adaptive type tiles, history + About rail
status: done
depends_on: [198]
---

# 199 — Employee My Leave tab redesign — adaptive type tiles, history + About rail

Built in the top-level `hrms/` clone (branch `feature/gowtham_HrmsDevConfig`), uncommitted.
Frontend only — every number comes from the existing self-service endpoints
(`/leave/me/balances`, `/leave/me/requests`, `/leave/me/policy`, `/leave/me/ledger`, `/leave/types`).

## Scope
`hrms/frontend/src/dashboards/Employee/MyLeave.tsx` (route `leave` in the Employee portal).

Layout, top to bottom, 10px page-level gaps (`hrms-spacing`):

1. **Leave type tiles** — one per row of `/leave/me/balances`, any count from 1 to 10.
   Columns balance the rows: `rows = ceil(n/5)`, `cols = ceil(n/rows)`
   → 1,2,3,4,5 in one row; 6 → 3+3; 7/8 → 4+4(3); 9/10 → 5+5(4). Below 1000px: 2 columns
   (1 when n = 1). Each tile: colour dot, name, Unpaid tag, available days, used/entitled
   bar, pending note. **Clicking a tile selects it** (selected ring in the type's colour);
   the first tile is selected by default.
   - **No leave types** (empty balances): a single full-width empty-state card instead of tiles.
2. **Two-column body** (`1fr | 1.2fr`, stacks below 1000px):
   - **Left — Apply for Leave**: unchanged `ApplyLeaveForm` in its card.
   - **Right — top: Leave History** = the caller's leave requests, newest first, **max 4
     rows**, with Cancel kept. Header carries **"View all (N)"** (modal with every request,
     shown when N > 4) and a **"Leave assignments"** button (modal with the full ledger —
     every credit/debit — filterable by leave type).
   - **Right — bottom: About <leave type>** fills the remaining height. Shows the selected
     tile's balance breakdown (entitled / accrued / used / pending / available), how it is
     earned and the apply rules (from `/leave/me/policy`, or a "not covered by your policy"
     note), and that type's last few ledger entries with a link into the assignments modal
     pre-filtered to it. Empty state when there are no types.
3. The old standalone "Leave Rules" and ledger "Leave History" cards are replaced by the
   About card and the Leave assignments modal.

`BalanceCards` stays exported and backwards-compatible for the manager profile Leave tab
(`shared/EmployeeLeaveTab.tsx`): `selectedId`/`onSelect` are optional, and the tile grid
no longer carries its own bottom margin (that caller already uses `gap-[10px]`).

Skeleton (`MyLeaveSkeleton`) mirrors the new structure using the shared Shimmer primitives.

## Files
- `hrms/frontend/src/dashboards/Employee/MyLeave.tsx`

## Acceptance criteria
- [x] 1–10 tiles lay out in balanced rows; narrow viewport falls back to 2 columns
- [x] Empty balances → empty-state card, About empty state, Apply form's own empty message
- [x] Clicking a tile switches the About card; selected tile is visibly marked
- [x] Leave History shows ≤ 4 rows; View all + Leave assignments modals work; Cancel still works
- [x] About card fills the space under Leave History; skeleton matches the layout
- [x] Manager profile Leave tab still renders `BalanceCards` (non-interactive)
- [x] `tsc --noEmit` and eslint clean on the touched file

Verified: rendered the real MyLeave against mocked /leave/* responses on the running dev server (temporary preview route, since deleted) — 0/1/3/4/6/7/10 tiles, tile→About switch incl. a type not covered by the policy, Leave assignments modal + type filter, skeleton, and a 760px viewport (2-col tiles, stacked body). tsc + eslint clean. Manager profile Leave tab only type-checked, not viewed. Not checked against real login data.

Completed: 2026-10-08
