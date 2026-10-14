---
name: hrms-responsive-side-panel
description: >
  Any page-level side panel/rail with a fixed pixel width (`w-[NNNpx]
  flex-none`, or a grid `grid-cols-[NNNpx_1fr]`) sitting beside a
  `flex-1`/`1fr` content area must not squeeze that content at narrow
  viewports — below `NARROW_BREAKPOINT` (1000px) it becomes a `fixed`
  overlay with a dark backdrop, opened via a trigger button, closing on
  selection or backdrop-tap. Use `useIsNarrow()` from
  `hrms/frontend/src/hooks/useIsNarrow.ts` for the breakpoint check — never a
  page-local `matchMedia`/resize listener. Use whenever building or
  reviewing a page that has its own secondary sidebar/rail/nav panel next
  to a content area, in `hrms/frontend/src/dashboards/`.
---

# HRMS responsive side panel — overlay, never squeeze

Found and fixed on 6 pages in one session: the main app sidebar
(`dashboards/shell.tsx`), Employee Directory's Departments panel
(`dashboards/shared/EmployeeDirectory.tsx`), Leave's Leave Types panel
(`dashboards/hrAdmin/Leave.tsx`), HR Attributes' attribute list
(`dashboards/hrAdmin/HrAttributes.tsx`), Roles & Permissions' roles rail
(`dashboards/hrAdmin/RolesPermissions.tsx`, CSS Grid variant), and Organization
Settings' settings-groups nav (`dashboards/hrAdmin/OrgSettings.tsx`). Every one
of these had a fixed-width `<aside>` (or grid column) sitting beside a
`flex-1`/`1fr` content column, with no responsive handling — at ≤1000px the
fixed-width sibling ate most of the viewport, squeezing the content into a
narrow, often-cut-off column.

One instance (`OrgSettings.tsx`) even had *existing* code claiming to handle
this — a comment saying the nav "becomes a horizontal strip" on narrow
screens — but on inspection the item list was never actually reworked into a
row layout, just clipped to a short scrollable box. It looked handled in the
diff; it wasn't fixed in practice. Don't trust a comment claiming responsive
handling — check that the actual JSX does what it says.

## The rule

Below `NARROW_BREAKPOINT` (1000px, from `hrms/frontend/src/hooks/useIsNarrow.ts`):
- The panel is **not rendered in-flow** — it doesn't take up space next to the
  content, full stop.
- A small **trigger button** (icon + short label, e.g. "Departments",
  "Leave Types", "Roles", "Settings") appears in the content area to open it.
- Opening it renders the panel as `position: fixed`, full height, with a dark
  `bg-black/40` backdrop behind it — never squeezed, never pushing content.
- Selecting an item in the panel closes the overlay **and** applies the
  selection. Tapping the backdrop closes it without changing anything.
- Above the breakpoint: **completely unchanged** — the panel renders in-flow
  exactly as it always did, no trigger button, no backdrop, no overlay logic
  ever fires.

## The breakpoint check — one shared hook, not a page-local listener

```tsx
import { useIsNarrow } from "@/hooks/useIsNarrow";

const isNarrow = useIsNarrow();
```

**Never** write a page-local `useState` + `matchMedia`/`resize` listener for
this — every one of the 6 fixes above originally had its own duplicated
`const [isNarrow, setIsNarrow] = useState(...); useEffect(() => { const mql =
window.matchMedia(...); ... }, [])` block, later consolidated into this one
hook. `useIsNarrow()` is the single source of truth for the breakpoint value
(`NARROW_BREAKPOINT`, exported alongside it) and the check logic. Each call
site still gets its own React subscription (that's how hooks work — there's
no app-wide singleton here, and none is needed), but there is exactly one
place that defines "what counts as narrow."

## The panel JSX recipe

Each page keeps its own local `*PanelOpen` boolean (no shared state for
this — the panels are unrelated to each other) and builds its own panel
content, but the container/overlay mechanics are the same shape everywhere:

```tsx
const [panelOpen, setPanelOpen] = useState(false);

// ...

{isNarrow && panelOpen && (
  <div
    className="fixed inset-0 bg-black/40 z-40"
    onClick={() => setPanelOpen(false)}
    aria-hidden="true"
  />
)}
{(!isNarrow || panelOpen) && (
  <aside
    className={`w-[NNNpx] ${isNarrow ? "fixed inset-y-0 left-0 z-50 shadow-xl" : "flex-none"} border-r border-border bg-white flex flex-col overflow-hidden`}
  >
    {/* unchanged internal content */}
  </aside>
)}
```

For a **CSS Grid** layout (`grid-cols-[NNNpx_1fr]` instead of
`flex-none`/`flex-1`) — see `RolesPermissions.tsx` — swap the grid's
`grid-template-columns` to single-column when narrow instead of trying to
make one grid track itself responsive:

```tsx
className={`... grid ${isNarrow ? "grid-cols-1" : "grid-cols-[268px_1fr]"} ...`}
```

**Trigger button**, visible only when `isNarrow`, placed wherever makes sense
in that page's content header (a tab-strip row, or a small button just above
the content):

```tsx
{isNarrow && (
  <button
    type="button"
    onClick={() => setPanelOpen(true)}
    className="cursor-pointer inline-flex items-center gap-[7px] rounded-[10px] border border-border bg-white text-ink-700 text-[13px] font-[650] px-3 py-[9px]"
  >
    <Icon path="M3 6h18M3 12h18M3 18h18" size={15} />
    {/* short label matching the panel's contents */}
  </button>
)}
```

## Closing the overlay on selection — watch for detour paths

Close the overlay inside whatever handler **actually commits** the selection,
not unconditionally at the top of a handler that might detour into a
confirmation dialog first. `OrgSettings.tsx`'s `switchTo` is the example that
matters here: it can either switch immediately, or set `pendingKey` and open
an "Unsaved Changes" modal instead. In that case, close the overlay
unconditionally at the very top of `switchTo` (before the dirty-check
branch) — the confirmation modal is itself a full-screen dialog, so the panel
overlay doesn't need to stay open behind it. For a simpler handler with no
such detour (e.g. `EmployeeDirectory.tsx`'s `handleDeptClick`,
`Leave.tsx`'s `handleSelectLeaveType`), just add `if (isNarrow)
setPanelOpen(false)` after the selection is applied.

## Loading skeletons

A static, non-interactive skeleton twin of the panel (shown while data is
loading, before the real component with its `panelOpen` state exists) doesn't
need the full overlay machinery — there's no toggle to open it yet. Just add
`max-[1000px]:hidden` to its `<aside>` so it doesn't squeeze content during
the loading flash. See `DirectorySkeleton` in `EmployeeDirectory.tsx` or
`LeaveSkeleton` in `Leave.tsx` for the pattern. If the skeleton is a CSS Grid
variant, also collapse its row to `max-[1000px]:grid-cols-1` (see
`RolesPermissionsSkeleton`).

## What NOT to do

- Don't hide the panel entirely with no way to open it (`max-[1000px]:hidden`
  and stop there) — that was the original bug on the main sidebar before this
  pattern existed. Always pair a hidden/pulled-out panel with a trigger.
- Don't shrink the panel to a short, clipped, still-in-flow box (the
  `max-h-[190px]` treatment `OrgSettings.tsx` had) — it still competes for
  layout space and reads as cramped/broken, even though it technically avoids
  squeezing the content column to zero.
- Don't add a page-local `matchMedia`/resize listener — use `useIsNarrow()`.
- Don't touch desktop (>1000px) behavior. Every code path above should be
  provably gated behind `isNarrow`/`panelOpen`, so above the breakpoint
  nothing about the existing layout, classes, or behavior changes.
