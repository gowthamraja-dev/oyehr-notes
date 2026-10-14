---
task: 26
title: Leave Policies admin screen — replace the static mock with server-backed UI
status: done
depends_on: [25]
---

## As-built deviations from the spec below

- **Added a new backend endpoint** (`GET /api/v1/leave/corps`, admin-only, tenant-scoped) plus a
  `listLeaveCorps` frontend wrapper and a `LeaveCorp`/`CorpOut` type on both sides. No endpoint
  anywhere in this codebase previously listed a tenant's corps as their own resource (`CorpMaster`
  was only ever joined into employee rows) — without it, the Applicability card's Corporation
  selector had nothing to populate. User confirmed via `AskUserQuestion` before building it, over
  the alternative of shipping v1 "All corporations only." Backend: `service.list_corps` /
  `router.list_corps` in `app/modules/leave/`, covered by `test_list_corps_scoped_to_tenant`.
- **Fixed a real dead-end bug found during manual QA**: `GET .../policy` resolves only
  `is_active=true` rows, so deactivating a policy made it vanish from the UI entirely with no way
  back — "Create policy" was the only option, which would have orphaned the deactivated row
  forever with no reactivation path. Added `InactivePolicyHint` (queries `GET .../policies`, the
  full history, for the most recent inactive row) rendered in the empty state, with a
  "Reactivate it" action calling `setLeavePolicyStatus(id, true)`. Not in the original component
  list — found by actually using the feature, not by re-reading the spec.
- **`handleAddLeaveType` uses two sequential `window.prompt()` calls**, not a proper modal. This
  is a known, deliberate stopgap: [[27-add-leave-type-flow]] replaces it with `CreateLeaveTypeModal`
  next. Kept only so this task's own manual-QA walkthrough ("create a leave type") is actually
  completable end-to-end without the empty-state screen being permanently unreachable. Do not
  extend or polish this path — it is getting deleted, not iterated on.
- **`archiveLeaveType` is wired into `LeaveTypeCard`'s "Manage type details" panel** ("Archive this
  leave type", with a `window.confirm` guard) rather than left unused — not explicitly in the
  component list, but the import was otherwise dead code and CLAUDE.md's activate/deactivate
  principle applies to leave types too, not just policies.
- **State/effect architecture differs from the spec's sketch** (§"Frontend state"): reworked to
  avoid the `react-hooks/set-state-in-effect` lint rule (a real, currently-enforced rule in this
  repo — confirmed it already flags pre-existing code in `MapPickerModal.tsx` too). Concretely:
  `PolicyForm`/`LeaveTypeCard` are remounted via a `key` prop from the parent (`leaveType.id`,
  `` `${leaveType.id}-${policy?.id ?? "new"}` ``) instead of a `useEffect` that resyncs local form
  state when the `policy`/`leaveType` prop changes; policy fetches are triggered imperatively from
  event handlers/promise callbacks (`selectLeaveType`/`reloadList`) via a `policyRequestRef`
  request-id guard, instead of a `useEffect` keyed on `selectedId`. Behavior is equivalent to the
  spec's `useState` list, just reorganized to satisfy the linter cleanly rather than carrying a
  suppressed/ignored lint error into new code.
- **Also found and fixed during implementation**: `reloadList` originally trusted a stale
  `selectedId` closure value as a fallback when re-selecting after a reload, which would have kept
  a just-archived leave type "selected" (and its policy still fetchable, since `_get_leave_type`
  doesn't filter archived rows) even though it no longer appears in the list. Fixed by validating
  the preferred selection against the freshly-fetched rows before falling back to it.

Manual QA walkthrough completed in an actual browser (Chrome via the claude-in-chrome tools)
against the live backend/dev DB — confirmed: empty list → add type → empty policy state → create
policy → list summary updates to "21 days · Monthly" → toggle carry-forward shows/hides max field
→ deactivate/reactivate round-trip (including the dead-end fix above) → validation error banner
shows the backend's exact clean message ("Effective until must be on or after effective from.")
with no raw stack trace. `npx tsc --noEmit` and `npx eslint` both clean throughout.

# 26 — Leave Policies admin screen — replace the static mock with server-backed UI

## Scope

Rewrite `frontend/src/dashboards/hrAdmin/Leave.tsx` to be fully server-backed, using the
wrappers from [[25-leave-policy-api-client]]. Keep the exported contract
`export function Leave({ me }: { me: Me })` — it's imported as-is at
`frontend/src/dashboards/hrAdmin/index.tsx:7` and rendered at nav key `leave` (`index.tsx:172-174`,
label "Leave"), no changes needed there.

**Terminology correction vs. the prompt file**: the prompt (`.design/prompts/P2P Full-Stack
Development Prompt — Leave Policies Admin Flow.md` §6/§40) describes a
`Home → Control Center → module` breadcrumb and a "secondary panel" from a static
`Admin Console.dc.html` mockup. That breadcrumb text does not exist anywhere in this codebase
(`grep -rl "Control Center" frontend/src` — zero hits) — it's mockup-only vocabulary. The real
shell has no per-feature breadcrumb; screens are `RoleDashboard` view objects reached via
`?v=leave` (`src/dashboards/shell.tsx`), and the existing `hrAdmin` sidebar nav item labeled
"Leave" *is* the entry point. Preserve the **visual language** (teal accents, card borders,
selected-item styling) the prompt asks for, not a breadcrumb string that was never built.

**Pattern to follow**: `frontend/src/dashboards/hrAdmin/HrAttributes.tsx` is the most recently
built two-panel admin screen in this repo (list on the left, detail form on the right) and
already has everything this task needs a local copy of — a local `Toast` function component
(`HrAttributes.tsx:11-18`), an exported `*Skeleton` component using `animate-pulse` placeholder
divs shaped like the real layout (`HrAttributes.tsx:20-35`), and `Icon`/`Combobox` shared
imports. Copy that shape, not `OrgSettings.tsx`'s older one (no toast, no skeleton — it predates
the shimmer-skeleton convention CLAUDE.md now mandates).

**Spacing**: per the `hrms-spacing` skill — outer page padding and gaps between sibling
cards/sections are `10px` (`p-[10px]`, `gap-[10px]`), not Tailwind's `p-4`/`gap-4` scale. The
existing `Leave.tsx` mock already violates this in places (`p-[26px]`, `gap-6`) — fix it as part
of this rewrite, don't carry it forward.

## Files

- `frontend/src/dashboards/hrAdmin/Leave.tsx` — full rewrite
- No changes to `index.tsx` or `registry.ts`

## Component structure

Internal to `Leave.tsx` (a `Leave_components/` split like `AttendanceShifts` is optional —
only do it if the file grows large enough to warrant it; don't preemptively split):

- `LeaveTypeList` — left panel, `listLeaveTypes()` on mount, one row per type showing name +
  `policy_summary` (prompt §7's `"21 days · Monthly"` format, already computed server-side —
  **do not recompute it client-side**, that duplicates policy-resolution logic the backend owns)
  + a status dot (`is_active` → green/grey, matching the mock's `dotClass` idea but driven by
  real data, not a hardcoded map). Selected row gets teal background/border (`bg-teal-50
  border-teal-200`, per the existing mock's `renderPolicyButton`, prompt §6's exact styling ask).
  An "Add leave type" button/action at the top of this panel opens the modal from
  [[27-add-leave-type-flow]].
- `LeavePolicyForm` — right panel, mounted per selected leave type. On leave-type switch: **the
  list stays visible, the form panel shows the skeleton** while the new `getLeaveTypePolicy` call
  is in flight — never flash the previous type's stale values (prompt §28). Sub-sections, each
  its own card (prompt §9 — "do not create one giant form"):
  - **Leave Type card** — read-only summary (name, code, paid/unpaid, unit, active) with a
    "Manage type details" affordance that opens an edit form for the `leave_type_masters` fields
    (reuses `updateLeaveType`) — kept visually/logically separate from the policy form below it,
    per prompt §9.A
  - **Applicability card** — Corporation selector (`All corporations` + a list — fetch corps via
    whatever existing wrapper already lists them for this tenant, e.g. check
    `frontend/src/lib/api.ts` for an existing `listCorps`/similar before adding a new one),
    Effective From, Effective Until. No Employee Type selector — `gaps.md #4` confirms that
    master table doesn't exist; per prompt §9.B, "keep the API field nullable and expose the
    selector only when the backend has a valid employee-type source" — it doesn't, so this
    selector is simply absent, not disabled/greyed
  - **Entitlement card** — Accrual frequency (segmented control: Monthly/Quarterly/Yearly/On
    Joining), Accrual quantity (labeled "per period" next to the input so admins don't confuse it
    with the annual total — this exact confusion is called out in
    `docs/leave-and-attendance/leave/admin-configuration.md` §5.2), Maximum balance, Pro-rate on
    joining (toggle), Leave year starts in (month-name dropdown, `reset_month` 1-12 — **send/
    receive the integer**, never persist the month name, prompt §14)
  - **Carry Forward card** — Allow carry-forward (toggle), Max carry-forward (number input,
    **hidden**, not just disabled, when the toggle is off — prompt §11)
  - **Encashment card** — Encashment allowed (toggle), Max encashment (number input, hidden when
    off — prompt §12)
- Empty state (prompt §30): when `getLeaveTypePolicy` resolves with `policy: null`, render
  "No leave policy configured" + the body text + a `[Create policy]` button that opens the
  Entitlement/Carry Forward/Encashment cards in create mode (calls `createLeavePolicy` instead of
  `updateLeavePolicy` on save)
- Error state (prompt §29): a failed `GET`/`PATCH`/`POST` shows an inline banner or the `Toast`
  pattern with a clean message (`"Unable to load leave policy."`, `"Another policy already
  covers this effective period."`, `"Maximum carry-forward is required when carry-forward is
  enabled."`) — surface the backend's `422 detail` string directly where it's already
  human-readable (the backend was written in [[23-leave-policy-api]] specifically to never leak
  raw Postgres errors), don't re-wrap it in a generic message
- Save bar: same fixed-footer pattern as the current mock (`Leave.tsx:316-335`) — `Save` disabled
  when `!dirty || saving`. On success: show the `Toast` ("Leave policy saved"), then **refetch**
  `getLeaveTypePolicy` rather than trusting local form state as the new source of truth (prompt
  §27's explicit requirement)

## Frontend state (prompt §36)

One normalized shape per the prompt's recommendation — do not keep parallel copies of the same
values in the list and the form:

```ts
const [leaveTypes, setLeaveTypes] = useState<LeaveType[]>([]);
const [selectedLeaveTypeId, setSelectedLeaveTypeId] = useState<number | null>(null);
const [policy, setPolicy] = useState<LeavePolicy | null>(null); // null = no policy yet (empty state)
const [loading, setLoading] = useState(true);   // list load
const [loadingPolicy, setLoadingPolicy] = useState(false); // per-type-switch load
const [saving, setSaving] = useState(false);
const [error, setError] = useState<string | null>(null);
const [form, setForm] = useState<LeavePolicyPatchInput | LeavePolicyInput>({});
const [dirty, setDirty] = useState(false);
```

## Manual verification (no frontend test runner in this repo — `grep test frontend/package.json`
confirms no `vitest`/`jest`, so this is browser QA, not an automated suite; CLAUDE.md's "test in
a browser before reporting complete" rule applies directly here)

Run `docker compose up -d` (or the existing dev flow), log in as an HR Admin, open the **Leave**
nav item, and walk:

- Fresh tenant with no leave types → empty list state, "Add leave type" reachable
- Create a leave type → its policy form shows the empty state, no fake values
- Create a policy → form populates, `policy_summary` in the list updates after save
- Edit accrual/carry-forward/encashment, toggle carry-forward off → max field disappears,
  toggle back on → reappears
- Switch between two leave types quickly → list never blanks, form shows skeleton then correct
  data, never a stale flash
- Refresh the browser mid-session → saved values persist (prompt §44's explicit checklist item)
- Trigger a validation error (e.g. termination date before effective date) → inline/toast error,
  no raw stack trace or SQL text

## Acceptance criteria

- [x] `Leave.tsx` contains no hardcoded `POLICIES` array or static `defaults` — every value
      rendered comes from a `GET` response
- [x] All spacing in new/changed markup uses the `10px` convention, not `p-4`/`gap-4`/`p-6`
- [x] Loading state is a shimmer skeleton (`animate-pulse`), never a spinner or "Loading…" text
- [x] Carry-forward/encashment max fields are conditionally rendered (hidden, not disabled) based
      on their toggle
- [x] Save button reflects `dirty` state; disabled with no pending changes
- [x] Manual QA walkthrough above completed and confirmed working against the real backend from
      [[22-leave-type-api]]/[[23-leave-policy-api]] — state explicitly in the PR/handoff that this
      was tested in-browser, per CLAUDE.md's UI-testing rule

Completed: 2026-08-18
