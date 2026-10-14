---
name: hrms-confirm-dialog
description: >
  Never use the browser's native `confirm()`/`window.confirm()` for a
  destructive-action prompt (delete, remove, archive) in HRMS — use the app-wide
  `useConfirm()` hook instead, which shows a styled modal matching the rest of
  the app instead of an unstyled native dialog. Use whenever adding any new
  "are you sure?" guard before a destructive action, or when reviewing/fixing
  existing code that calls `confirm(...)`/`window.confirm(...)`.
---

# HRMS confirm dialog — one reusable component, never `window.confirm()`

Found while fixing HR Attributes' delete-value flow: `confirm()` pops the
browser's native, unstyled dialog (title bar reads "localhost:7001 says") —
jarring next to every other confirm/cancel surface in this app, which are all
styled modals. The same native `confirm()`/`window.confirm()` pattern had
quietly spread to three files (`HrAttributes.tsx`, `HolidayCalendarAdmin.tsx`,
`ShiftDefaults.tsx`) before being fixed here — built as a **global** provider +
hook specifically so it never needs re-inventing per page again.

## The rule

**Any new destructive-action confirmation → `useConfirm()`. Never `confirm()`
or `window.confirm()`.**

```tsx
import { useConfirm } from "@/contexts/confirm-context";

function MyComponent() {
  const confirm = useConfirm();

  async function handleDelete(label: string) {
    if (!(await confirm(`Remove "${label}"? This cannot be undone.`))) return;
    // proceed with the destructive call
  }
}
```

`confirm(...)` returns `Promise<boolean>` — same call shape as native
`confirm()`, just async, so converting an existing `if (!confirm(msg)) return;`
guard is a two-token change: wrap in `await (...)` and make the enclosing
function `async` (it almost always already is, since the destructive call right
below it is itself awaited).

For a non-default title, button labels, or a non-destructive style, pass an
options object instead of a string:

```tsx
const ok = await confirm({
  title: "Archive this shift?",
  message: "It will no longer appear in this list.",
  confirmLabel: "Archive",
  danger: false, // renders the confirm button in the app's teal, not red
});
```

## What's already wired up

- **`hrms/frontend/src/contexts/confirm-context.tsx`** — `ConfirmProvider` +
  `useConfirm()`. Mounted once in `hrms/frontend/src/app/dashboard/layout.tsx`,
  alongside `AuthProvider`/`BreadcrumbProvider` — do not mount it again
  per-page.
- **`hrms/frontend/src/dashboards/shared/ConfirmDialog.tsx`** — the actual modal,
  styled like `EditAdminModal.tsx`'s shell (rounded card, header/message, footer
  Cancel + action button). Rendered once by the dashboard layout; nothing to
  import at a call site beyond the `useConfirm()` hook itself.
- Danger styling uses the existing `--color-danger` token (`bg-danger`), the
  same one used by `text-danger` error text elsewhere in this app — not a raw
  Tailwind red.

## Reference implementations

`HrAttributes.tsx`'s `handleDeleteValue`, `HolidayCalendarAdmin.tsx`'s
`handleDelete`, and `ShiftDefaults.tsx`'s `handleArchive` — all converted from
`confirm()`/`window.confirm()` to `useConfirm()` as the first three call sites.
Match these when adding a new destructive-action confirmation anywhere else in
the app.

## Pre-merge checklist for any new destructive action

- [ ] No `confirm(...)` or `window.confirm(...)` call anywhere in the diff
- [ ] `useConfirm()` called at the top of the component, `await`ed at the guard
- [ ] The enclosing handler is `async`
- [ ] Non-destructive confirmations (rare) pass `danger: false` explicitly
