---
name: hrms-spacing
description: >
  Strict spacing rule for every HRMS dashboard page and card: outer page padding
  and the gap between sibling cards/sections is 10px, not Tailwind's default
  scale (p-4/p-5/mb-4/mb-5, i.e. 16-20px). Also covers table row density: header
  cells py-[10px], body cells py-3 — not py-[14px]/py-[18px], which only shows
  5-6 rows per screen. Use whenever building or reviewing a page-level component
  (list/table pages, detail pages, filter bars, cards) in `hrms/frontend/src/dashboards/`.
  Does not apply to modal internals (header/body/footer padding), which follow the
  existing modal convention instead (px-5 py-4, see `nh-modal-skill`-equivalent
  hrms pattern in ShareCredentialsModal.tsx/EditAdminModal.tsx/AddOrganizationModal.tsx).
---

# HRMS spacing — 10px, strictly, for page-level layout

Established while building the Super Admin Organizations/Admins pages: the
outer page padding and the gaps between page-level cards/sections kept drifting
to Tailwind's default scale (`p-4` = 16px, `p-5`/`mb-5` = 20px, `p-6` = 24px,
`p-[26px]` matching the shell's header height), which reads as too much
whitespace. The fix, confirmed directly by the user across several rounds of
screenshot feedback: **10px, everywhere, for page-level spacing.**

## The rule

- **Outer page wrapper** (the root `<div>` a `DashboardView`'s `render` returns,
  when the view is `fullBleed: true`): `className="p-[10px]"`. Not `p-[26px]`,
  not `p-6`, not any Tailwind default-scale class.
- **Gap between sibling page-level blocks** (filter card → table, card → card,
  success banner → form, section → section): `mb-[10px]` on the earlier block,
  or `gap-[10px]`/`gap-3` in a flex container — not `mb-4`/`mb-5`/`gap-4`/`gap-5`.
- **Inside a filter/action-bar card** (`bg-white border border-border rounded-[14px] ...`):
  card padding is also `p-[10px]`, not `p-4`/`p-5`.
- **Table row density**: header cells `py-[10px]`, body cells `py-3` (12px) —
  keep horizontal padding (`px-6`/`px-4`) and font sizes as they are, this is a
  vertical-density change only. Previously these had crept up to `py-[14px]`/
  `py-[18px]` during a page-padding fix pass, which was the wrong target: it made
  each row tall enough that a table only showed 5-6 rows per screen before
  scrolling. Row padding is NOT the same axis as page-level card padding above —
  don't let a "too much whitespace" complaint about page margins get applied to
  table rows, and don't let a "rows too tall" complaint get applied to page margins.

## What this does NOT apply to

- **Modal internals** (`ShareCredentialsModal.tsx`, `EditAdminModal.tsx`,
  `AddOrganizationModal.tsx`, and any future modal): header/body/footer padding
  stays `px-5 py-4` / `px-5 py-3` — the existing hrms modal convention, unrelated
  to page-level spacing. A modal is not a page; do not shrink its chrome to 10px.
- **Gaps *within* a single row of controls** (e.g. `gap-2`/`gap-3` between a
  search box, status tabs, and a button in one filter row) — those are fine as
  designed; this rule governs the *outer* page margin and the *vertical* gap
  *between* stacked blocks, not horizontal spacing within one row.

## Reference implementation

`hrms/frontend/src/dashboards/superAdmin/OrganizationsList.tsx` and
`AdminsPage.tsx` — both use `p-[10px]` on the root wrapper, `p-[10px]`/`mb-[10px]`
on the filter card, and the same pattern on every stacked block below it
(new-admin form, success banners). Table header cells `px-6 py-[10px]`/`px-4 py-[10px]`,
body cells `px-6 py-3`/`px-4 py-3`. Match these files when building any new
page-level component.

## Pre-merge checklist for any new dashboard page

- [ ] Root wrapper is `p-[10px]`, not `p-6`/`p-[26px]`/any default Tailwind padding scale
- [ ] Every gap between stacked page-level blocks is `mb-[10px]` or `gap-[10px]`/`gap-3`, not `mb-4`/`mb-5`
- [ ] Filter/action-bar cards use `p-[10px]` internally, not `p-4`/`p-5`
- [ ] Table header cells are `py-[10px]`, body cells are `py-3` — not `py-[14px]`/`py-[18px]`
- [ ] Modals are NOT touched by this rule — their `px-5 py-4` chrome stays as it is
