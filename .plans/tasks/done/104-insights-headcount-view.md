---
task: 104
title: Wire the Insights "Headcount" view to real data (reusing EmployeeHeadcountTab)
status: done
depends_on: [103-attendance-insights-register-rail]
---

# 104 — Wire the Insights "Headcount" view to real data (reusing EmployeeHeadcountTab)

## Source
Follow-up to [[103-attendance-insights-register-rail]] (2026-09-09). The user pointed at the
"Headcount" view screenshot from the Insights screen (4 KPI cards — Headcount / Attrition
(12m) / Avg tenure / Offer acceptance — plus Headcount-by-department bars, an Attendance-rate
trend chart, and a Gender-diversity bar) and asked to "design the analytics ui in the
screenshot." That exact look is a static mock in `.design/Admin Console.dc.html`'s `isIns`
panel — never live, never backed by an API.

**Scope decision confirmed with the user (2026-09-09) — asked directly rather than assumed:**
Build it as the live "Headcount" view, using real data wherever a real endpoint exists, and an
honest "not available yet" state everywhere else — never invented numbers. Concretely:
- **Real**: total/active/on-leave/inactive headcount + by-department breakdown — this data
  already exists and already has a UI: `getHeadcount()` / `EmployeeHeadcountTab`
  (`dashboards/shared/EmployeeHeadcountTab.tsx`), the same component the Employee Directory's
  own Headcount tab uses. Reused directly rather than rebuilt — same component, same cache-by-
  parent-state convention (a local `useState<EmployeeHeadcount | null>` here, since this view
  doesn't need cross-tab-switch caching the way the Directory's tabs do).
- **Not available yet**: Attrition (12m), Avg tenure, Offer acceptance (no HR analytics
  endpoint at all), an attendance-rate 6-month trend, and gender diversity (no gender field
  captured on `EmployeeMaster` today). These render as explicitly muted states — dashed-border
  "—" tiles for the three KPIs, the shared `Placeholder` ("this module is coming soon") for the
  two chart slots — never the mock's fabricated numbers (78 Nursing, 4.2% attrition, etc.).

## Files
- New: `frontend/src/dashboards/hrAdmin/Insights_components/components/HeadcountInsights.tsx`
  — `HeadcountInsights()`, no props. Renders `<EmployeeHeadcountTab cache={...} onLoaded={...} />`
  (imported from `../../../shared/EmployeeHeadcountTab`) followed by a "More people
  analytics · Coming soon" band (3 dashed-border metric tiles) and a 2-column row of
  `Placeholder` (from `../../../shell`) for the two chart slots.
- Edit: `frontend/src/dashboards/hrAdmin/Insights_components/index.tsx` — `metric ===
  "headcount"` now renders `<HeadcountInsights />` instead of falling through to the generic
  `Placeholder`. "Attrition"/"Diversity"/"Recruitment" still fall through to `Placeholder` —
  unchanged, no backend for any of them.
- No backend changes — `getHeadcount()` / `/api/v1/employees/headcount` already existed and is
  already used elsewhere (Employee Directory), so no new gating/RBAC decisions needed.

## Acceptance criteria
- [x] Insights → Headcount (the default view) shows real total/active/on-leave/inactive counts
      and a real by-department bar breakdown, sourced from `getHeadcount()` — confirmed live
      against the seeded dev tenant (11 total, IT 3 · 27%, Sales 1 · 9%).
- [x] Attrition (12m), Avg tenure, and Offer acceptance render as explicit "—" / muted tiles,
      not fabricated numbers.
- [x] Attendance-rate-trend and Gender-diversity render the shared "coming soon" `Placeholder`,
      not the mock's fake chart.
- [x] `EmployeeHeadcountTab` itself is untouched — reused as-is, no duplication.
- [x] No backend changes.
- [x] `npx tsc --noEmit` and `npx eslint` clean on both touched/added files (no new
      warnings/errors).
- [x] Manual browser walkthrough as HR Admin against the local dev stack — confirmed live, no
      console errors.

Verified: 2026-09-09 (`npx tsc --noEmit` clean, `npx eslint` clean, live browser walkthrough
via Chrome automation against the local dev stack logged in as HR Admin — `admin@test.com` /
`acme` tenant).
Completed: 2026-09-09
