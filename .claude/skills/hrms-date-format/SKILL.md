---
name: hrms-date-format
description: >
  Every user-facing date in HRMS displays as dd-MMM-yy (e.g. 15-Jul-23), and
  every date INPUT uses the shared hrms/frontend/src/components/ui/DateField.tsx
  component instead of a bare `<input type="date">`. A native date input
  cannot be restyled to dd-MMM-yy with CSS — it always renders in the
  browser/OS locale format (MM/DD/YYYY, DD/MM/YYYY, etc.) — so DateField
  wraps it: a dd-MMM-yy text display up front, the real native input
  invisibly on top so the OS calendar picker still opens on click. Use
  whenever displaying a date/timestamp, or adding/reviewing any date-picker
  field, anywhere in `hrms/frontend/src/`.
---

# HRMS date format — dd-MMM-yy everywhere, one shared date input

Established while building the Payroll module's period-creation flow: the
"New period" modal's native `<input type="date">` fields showed `MM/DD/YYYY`
(the browser's locale format) even though every other date on the page
correctly showed `dd-MMM-yy` via a local `formatDate()` helper. The two are
different code paths — formatting *display text* with a helper function does
nothing for a native `<input type="date">`'s own rendered value, which the
browser/OS controls and CSS cannot override. The fix: a shared `DateField`
component that shows the formatted text itself, with the native input
present-but-invisible underneath purely to drive the calendar picker.

## The rule

- **Any date shown as text** (a label, a table cell, a card, a timestamp):
  format as `dd-MMM-yy`, e.g. `15-Jul-23`. For a date+time, follow
  `nh_server_app`'s sibling convention: `dd-mmm-yy hh:mm AM/PM`, e.g.
  `14-Mar-26 09:47 PM`.
- **Any date INPUT** (a field the user picks/types a date into): use
  `import { DateField } from "@/components/ui/DateField"` — never a bare
  `<input type="date">`. `DateField` takes `value` ("YYYY-MM-DD"), `onChange`,
  and optional `min`/`max` — same shape as a native date input, drop-in
  compatible.
- **Do not build a per-page `formatDate()` for display text if one already
  exists in scope** — check the file/module first (e.g. Payroll's
  `formatDate()` in `hrms/frontend/src/dashboards/hrManager/Payroll.tsx`) before
  writing a new one; consolidate into `@/components/ui/DateField`'s exported
  formatter if a genuinely shared helper is warranted.

## Reference implementation

`hrms/frontend/src/components/ui/DateField.tsx` — the one canonical date input for
all of HRMS. `hrms/frontend/src/dashboards/hrManager/Payroll.tsx`'s
`NewPeriodModal` and `AssignStructureModal` both use it for every date field
(period start/end, planned pay date, structure effective-from).

## Common mistake to avoid

Do NOT build a `Date` from local y/m/d components and then format it with
`.toISOString().slice(0, 10)` to get a `"YYYY-MM-DD"` string — `.toISOString()`
converts to UTC first, which silently shifts the date back a day in any
timezone ahead of UTC (e.g. IST) for a `Date` built at local midnight. This
produced a real bug: a period meant to start "01-Aug-26" saved as
"31-Jul-26" in the database. Format local dates by reading
`.getFullYear()`/`.getMonth()`/`.getDate()` directly instead — see
`toISODate()` in `hrms/frontend/src/dashboards/hrManager/Payroll.tsx` for the
pattern.

## Pre-merge checklist for any new date field or date display

- [ ] Displayed dates read `dd-MMM-yy` (or `dd-MMM-yy hh:mm AM/PM` for a
      timestamp), not `MM/DD/YYYY`, not a raw ISO string
- [ ] Any date the user picks uses `@/components/ui/DateField`, not a bare
      `<input type="date">`
- [ ] Any "today" or "this month" default is built and formatted using local
      date components, never `.toISOString()`, to avoid the UTC-shift bug
