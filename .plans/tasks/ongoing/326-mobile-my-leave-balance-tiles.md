---
task: 326
title: Mobile — My Leave balance shown as two-column tiles (Granted / Consumed / Balance)
status: ongoing
depends_on: []
---

# 326 — Mobile: My Leave balance tiles

## Scope
`LeaveBalance` (top of the My Leave screen, `employeeapp/src/screens/LeaveScreen/Components/LeaveBalance/`) renders one full-width card per leave type
("x/y Used", big "N days left", bar). Replace it with compact **tiles, two per row**, matching the design the user shared:

- Tile: leave-type name (bold, 1 line) -> used/entitled progress bar (grey track, fill in the type's `color_code`) -> divider ->
  `Granted  N days` / `Consumed  N days` -> divider -> `Balance  N days` (teal, bold).
- Data is unchanged — `GET /leave/me/balances`: Granted = `entitled` (existing fallback chain kept, then `used + available`),
  Consumed = `used`, Balance = `available_balance`. No backend change.
- Layout: 2 columns at every phone width; an odd last tile stays half-width at the left (never stretches). Equal heights within a row.
- Day values keep `formatDays` (integers plain, fractions to 1 dp) and read "1 day" / "N days".
- Empty balances keep the existing empty-state card (full width).
- `LeaveShimmer` top block becomes a 2-up tile skeleton so there is no layout jump when data lands.

Not covered: Apply Leave form, Request History, web portal (already has its own tiles, task 199), Home leave summary.

## Rules
Mobile conventions: `Colors` / `Spacing` constants only (no hardcoded hex), styles in `LeaveBalanceStyles.js`, MVVM split untouched
(tile math stays in the component, same as before).

## Files
`employeeapp/src/screens/LeaveScreen/Components/LeaveBalance/LeaveBalance.js`, `.../LeaveBalanceStyles.js`,
`employeeapp/src/components/ShimmerLoader.js` (`LeaveShimmer` only).

## Acceptance criteria
- [ ] Balances render two per row with name, bar, Granted / Consumed / Balance
- [ ] Odd count -> last tile half-width at left; single type -> one half-width tile
- [ ] 1 day / N days wording; fractional days (e.g. 1.5) display correctly
- [ ] Empty balances -> empty-state card unchanged
- [ ] Shimmer matches the tile grid
- [x] eslint clean on touched files
- [ ] Checked on a device / simulator

## Progress (2026-11-04)
Built in `workspace-2/employeeapp` (branch `feature/gowtham_WfhRequests`), NOT committed: `LeaveBalance.js` now renders a wrapped 2-up tile grid
(name, bar, Granted / Consumed / Balance, `formatDaysLabel` for 1 day / N days), styles in `LeaveBalanceStyles.js` (`grid`/`tile`/`stat*`/`balance*`;
`leaveCard` kept for the empty state), `LeaveShimmer` leads with a 2-up skeleton row. eslint: 0 errors (only the file's pre-existing inline-style warnings).
Layout rules are written from the code, not seen: not run on a simulator/device, and jest can't start in this clone (`@react-native/jest-preset` missing).

## Progress (2026-11-05)
Mobile already has the 2-up tiles committed on `gowtham-dev`, so the earlier uncommitted tile work (`workspace-2/employeeapp` `stash@{0}`) is obsolete.
A mobile section reorganisation was tried and **reverted** at the user's request; the same change (tiles -> Apply button -> History) was made on the web
My Leave page instead (`workspace-1/hrms/frontend/src/dashboards/Employee/MyLeave.tsx`). Nothing further planned on mobile.
