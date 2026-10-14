---
task: 159
title: HR Admin Leave UI — restore grouped sections and inline editing (fewer popups)
status: ongoing
depends_on: [158]
---

# 159 — HR Admin Leave UI: restore grouped sections and inline editing

**Where:** the top-level `hrms/` clone, branch `feature/gowtham_LeaveMasters`, under
`frontend/src/dashboards/hrAdmin/`. Depends on 158 because 158 removes the policy stepper's
Scope step.

## Problem (user feedback, 30-Sep-26)
The new leave-policy UI (commit `d41ef7c`) looks worse than the old one:
1. **Grouping was lost.** The old editor showed fields in labelled cards grouped by meaning. The
   new one puts them in flat, mixed grids. For example, the expanded rule in
   `LeavePolicies.tsx` (~L463–497) is one `grid-cols-3` that mixes earning fields (Credited,
   Days each time, Max balance, Prorate) with year-end fields (Leave year starts, Carry forward,
   Encashable) and the rule's own status toggle. `LeaveTypeFormModal` in `LeaveTypes.tsx`
   (~L338–347) is a flat list of toggles.
2. **Almost everything is a popup.** Adding or editing a leave type (`LeaveTypeFormModal`),
   creating, editing or viewing a policy (the full stepper in a `fixed inset-0` modal,
   `LeavePolicies.tsx` ~L390), making a new version (`NewVersionModal`) and adding or editing an
   assignment (`AssignmentModal`, `PolicyAssignments.tsx` ~L421) all open over the page.

## Reference: the old UI (pre-`d41ef7c`)
See it with `git -C hrms show d41ef7c^:frontend/src/dashboards/hrAdmin/Leave.tsx` (and
`LeaveTypeWizard.tsx` at the same revision). The layout was a **split view**: the leave-type
list on the left and an **inline editor** on the right (`LeaveTypeList` + `LeaveTypeEditor`),
built from `Card`s with these groups:

| Card | Fields |
|---|---|
| Leave Type | name, code, colour, paid, status |
| Who It Applies To | ~~Corporation~~ (gone after 158), Only for (gender), Available after joining |
| How It Is Earned | Total per year (hint), Credited, Quantity each time, Balance cap, Pro-rate new joiners |
| How It Can Be Taken | Half day allowed, Skip week-offs, Skip holidays, Allow negative balance, Apply at least, Longest single stretch |
| At Year End | Carry forward + Max carried over, Encashable + Max encashed, Leave year starts |
| Advanced | Needs approval, Document required + Only when longer than, Display order, Calendar colour, Effective period |

The goal is to bring that look back, adapted to the new data model: leave-type attributes live
on `leave_type_masters` and accrual rules live on `leave_policy_details` under a policy.
**Do not** revert the model or the API.

## Scope
- **Leave Types tab (`LeaveTypes.tsx`):** replace `LeaveTypeFormModal` with the old split view:
  the list on the left and an inline editor on the right, using grouped cards
  (Leave Type / Who It Applies To / How It Can Be Taken / Advanced). Keep dirty-state
  "discard changes?" handling through `useConfirm()` when switching rows. Below 1000px the list
  becomes an overlay panel (`hrms-responsive-side-panel` skill, `useIsNarrow()`).
- **Leave Policies tab (`LeavePolicies.tsx`):** create, edit and view open **inline on the
  page** (list → detail view with a back link and breadcrumb), not a modal. Inside the detail view:
  - A **Basic information** card (name, code, description, status, effective from/to).
  - A **Leave rules** section: one card per leave type, with the collapsed one-line summary kept.
    When expanded, the rule is split into labelled sub-groups (**How It Is Earned** / **At Year
    End** / rule status) instead of one mixed grid. Use `leaveEntitlement.ts` hints
    (annual total / projection) the way the old "How It Is Earned" card did.
  - A **Review** summary can stay as a panel at the bottom or a sticky footer with Save/Discard.
    A separate step is not needed once everything is on one page. Decide while building, but no
    modal.
  - View mode is the same page, read-only, plus the assignment count and a link to Policy Assignments.
- **Keep as small modals:** only short, one-shot actions. That is `NewVersionModal` (name, code,
  effective date, move-assignments) and `useConfirm()` dialogs for archive/deactivate.
- **Policy Assignments (`PolicyAssignments.tsx`):** **ask the user at pickup** whether
  `AssignmentModal` (policy, provider type + provider, priority, dates, status) should move to an
  inline form or row editor, or stay a modal. It is short, so a modal is defensible. Don't change
  it without an answer.
- Do not change the backend or the API contract.

## Conventions to follow
- Tailwind only. Spacing per the `hrms-spacing` skill (10px page padding and card gaps,
  `py-[10px]` header cells, `py-3` body cells).
- Loading: shimmer skeletons from `components/ui/Shimmer.tsx` that match the new inline layouts
  (the split view, and the policy detail page with its cards). Update or replace the old
  modal-body skeletons. No "Loading…" text.
- Dates: `DateField` for inputs and dd-MMM-yy for display (`hrms-date-format`).
- Destructive prompts: `useConfirm()` (`hrms-confirm-dialog`), never `window.confirm`.

## Files
- `frontend/src/dashboards/hrAdmin/Leave_components/LeaveTypes.tsx`
- `frontend/src/dashboards/hrAdmin/Leave_components/LeavePolicies.tsx`
- `frontend/src/dashboards/hrAdmin/Leave_components/PolicyAssignments.tsx` (only if the user agrees)
- `frontend/src/dashboards/hrAdmin/Leave.tsx` (shell, tabs, breadcrumb for the policy detail view)
- Optional: a shared `Leave_components/SectionCard.tsx` (the old `Card` with title + right slot)
  if two or more files use it.

## Acceptance criteria
- [ ] Adding or editing a leave type happens inline in a split view with grouped cards. There is
      no full-screen modal, and dirty-switch asks for confirmation.
- [ ] Creating, editing or viewing a policy happens on the page, not a modal. Each expanded rule
      shows separate labelled **How It Is Earned** and **At Year End** groups.
- [ ] The only popups left in the Leave admin area are New version, confirm dialogs, and the
      assignment form (kept by the user's decision).
- [ ] Below 1000px the Leave Types list becomes an overlay panel, and nothing is squeezed.
- [ ] Skeletons match the new layouts (header rows included) with no layout shift on load.
- [ ] End-to-end browser check by the user (the `hrms/` API writes to the **shared remote DB**, so
      leave it to them): create a leave type, create a policy with CL/SL/EL, edit a rule, make a new
      version, archive. Screenshots are compared side by side with the old UI.
- [ ] `npx tsc --noEmit` and `npm run lint` are clean.

## Implementation plan (planned 30-Sep-26)

Line numbers are from `b618780` (task 158 committed). "old L" = `git show d41ef7c^:frontend/src/dashboards/hrAdmin/Leave.tsx`.

### 0. Shared pieces: new `Leave_components/SectionCard.tsx`
LeaveTypes and LeavePolicies both use these.
- `SectionCard({ title, right?, children })`: port the old `Card` (old L136-150) as it is. The
  header is `px-[18px] py-[13px]` with a 3px teal bar and an uppercase title; the body is
  `p-[18px_20px] flex flex-col gap-4`. Siblings sit `gap-[10px]` apart (hrms-spacing).
- `SectionCardSkeleton({ titleWidth, bodyRows, headerOnly? })`: port the old `CardSkeleton`
  (old L104-118), built from Shimmer primitives.
- `SubGroup({ title, children })`: a labelled block inside a rule card. Heading style from
  `LeaveTypes.tsx` L359 (`text-[11px] font-bold uppercase tracking-[.05em] text-ink-400`), with
  the body in `.field-row-grid` (`globals.css` L99).
- `StickyActionBar({ note, error, onDiscard, onSave, dirty, saving, saveLabel })`: port the old
  sticky footer (old L1190-1213, `sticky bottom-0 bg-gradient-to-t from-app-bg from-[62%] to-transparent`).
- `CarryEncashField`: port old L156-175 and change it to string values (RuleDraft keeps numbers
  as strings). It can stay local to LeavePolicies.
- Reuse without changes: `FieldBox`, `DefaultRow`, `ToggleButton` (`AttendanceShifts_components/components/ui`);
  `NumberField`, `OptionalMinutesField`, `Segmented` (`…/components/inputs`); `accentFor` (`@/lib/shiftAccent`).

### 1. Leave Types tab: split view (`LeaveTypes.tsx`)
- **Layout.** Root is `flex h-full min-h-0 gap-[10px] p-[10px]`.
  - **Rail** `LeaveTypeRail`: port the old `LeaveTypeList` (old L198-315), `w-[280px] flex-none`.
    The header shows "Leave Types · N configured" and an **Add** button. Each row's sub-line is
    built from type attributes (`Paid · Approval · Half day`), not `policy_summary`.
  - **Right pane**: `flex-1 min-w-0 overflow-y-auto`, holding an editor keyed by `selected`
    (`number | "new"`).
- **Narrow (`useIsNarrow()`)**: the rail becomes `fixed inset-y-0 left-0 z-50` over a
  `bg-black/40` backdrop and closes on backdrop tap or row select. A trigger button sits at the
  top of the right pane (old L1383-1392).
- **Field → card mapping.** Reuse `Draft`/`toDraft`/`toInput`/`validate` (L202-250) unchanged, and
  replace `ToggleRow` (L252-262) with `FieldBox` + `ToggleButton`.

  | Card | Fields |
  |---|---|
  | Leave Type | name + code (inline header inputs, old L650-690), `color_code` chip/picker, `is_paid`, a read-only status with an "Archive this leave type" link (existing `handleArchive` L86-103), and a summary line |
  | Who It Applies To | `gender_applicable` (Only for), `applicable_after_days` (Available after joining, "Immediately") |
  | How It Can Be Taken | `allow_half_day`, `exclude_week_offs`, `exclude_holidays`, `allow_negative_balance`, `min_notice_days`, `max_consecutive_days` ("No limit") |
  | Advanced (collapsed, Show/Hide as in old L1060-1073) | `requires_approval`, `requires_document` + `doc_required_after_days` (shown when on), `display_order`, `effctv_dt`/`trmntn_dt` (DateField) |

  The old *How It Is Earned* / *At Year End* fields now live on policy rules, and *Corporation* is
  gone (task 158). In their place, add one info strip: "How much is earned and what happens at
  year end is set per leave policy → Open Leave Policies" (an `onOpenPolicies` prop).
- **Create inline.** The rail's **Add** and the breadcrumb button (L72-84) call
  `requestSelect("new")`: a placeholder rail row plus `toDraft(null)`. On save, reload the list
  and select `created.id`. After an archive, reload and select the first row (old L1308-1320).
- **Dirty switch.** The editor reports `onDirtyChange` into a parent `dirtyRef`. `requestSelect`
  runs `useConfirm({ title: "Discard changes?", confirmLabel: "Discard changes", cancelLabel: "Keep editing", danger: true })`.
  The same guard runs on narrow-overlay select and on tab switch (§2).
- **Save/Discard.** Use `StickyActionBar` with the note "Changes apply to new requests". Delete
  `LeaveTypeFormModal` (L264-413) and `ToggleRow`.
- **Skeleton.** Replace `LeaveTypesSkeleton` (L25-45) with:
  - a rail (`max-[1000px]:hidden`): header lines + `ShimmerButton` + 5 × 46px rows;
  - a narrow trigger `ShimmerButton` (`min-[1001px]:hidden`);
  - the right pane: `SectionCardSkeleton` ×3 + Advanced `headerOnly` + a bar with 2 buttons.

### 2. Leave Policies tab: list → inline detail page (`LeavePolicies.tsx`)
- **State.** Replace `editor` (L61, L67) with
  `view: {kind:"list"} | {kind:"create"} | {kind:"detail"; id; edit: boolean}`. When it isn't
  the list, render `<PolicyDetail>` **instead of** the list (L127-229). The "Create Leave Policy"
  breadcrumb control (L82-93) shows only on the list.
- **Breadcrumb + back.** Leave.tsx owns the single `useSetBreadcrumbExtra` (L25). LeavePolicies
  reports `onCrumb(label | null)`. Clicking the crumb calls `guardRef.current?.()` and then goes
  back to the list. The guard is read through a ref, because the hook captures `onBack` only when
  the label changes. Also add a `← All leave policies` link, and make Leave.tsx await the guard
  before a tab switch (L37).
- **PolicyDetail (rename `PolicyEditor`).** Keep state + load (L305-346) and **`save()` (L348-381)
  unchanged**, except:
  - drop `step`/`STEPS`;
  - capture `createLeavePolicyMaster`'s result so create lands on `{detail, id, edit:false}`;
  - add a load-time `snapshot` for `dirty`.
- **Page.** `p-[10px] max-w-dash mx-auto flex flex-col gap-[10px]`.
  - **Title row**: name, code chip, status pill (L176-178). View mode adds **Edit policy** and
    **New version** (the existing `NewVersionModal`, L561-616, stays a modal).
  - **Basic information** `SectionCard`: the fields from L415-437. In view mode they render as
    plain text, plus "Used by N assignments · View in Policy Assignments →" (`onOpenAssignments`).
  - **Leave rules** `SectionCard` with `right` = "+ Add a leave type…" (L499-504). One card per
    rule:
    - **Collapsed**: header (L446-459) + chevron.
    - **Expanded**: replaces the mixed grid (L460-495) with:
      - **How It Is Earned**: Total per year (`annualTotal`, and editing it redistributes quantity
        + cap as in old L806-866), Credited (`Segmented`), Days each time (`quantityHint`), Max
        balance ("No cap", `balanceCapHint`), Prorate, plus the `projectionText` callout (old L889-893).
      - **At Year End**: Carry forward + max, Encashable + max, Leave year starts.
      - **Rule status strip**, like the old "Policy status" strip (old L1170-1188).
    - **View mode**: the same groups as text, all rules collapsed.
  - **Footer**: `StickyActionBar`, edit/create only. The note is the L522-527 copy. Discard
    confirms if dirty. `validateAll` errors show in the bar.
- **Skeletons.** Keep `LeavePoliciesSkeleton` for the list. Add `PolicyDetailSkeleton`: a back
  link, a title + pill, the Basic info card (2-col, textarea, 3-col at 38px), the Leave rules
  card (3 rows), and a 2-button bar in edit/create only.

### 3. Policy Assignments: **decided 30-Sep-26: keep `AssignmentModal` as it is** (option A)
- **A. Keep `AssignmentModal` (L320-507)** (recommended). It is short, and its conflict state and
  provider picker are built around a dialog.
- **B. Inline form card** above the table. Moderate work.
- **C. Inline row editor.** Not advised: it doesn't fit a row and breaks below 1000px.

Separately: should the policy page's "View in Policy Assignments" pre-filter the list? That is an
`initialPolicyId?` prop seeding `policyId` (L100).

### 4. Order of work
1. `SectionCard.tsx`
2. Leave.tsx: `guardRef`, `policyCrumb`, the guarded `setSection`, `onOpenPolicies`/`onOpenAssignments`
3. LeaveTypes.tsx
4. LeavePolicies.tsx (remove the modal chrome/stepper/footer L385-409, L532-555)
5. PolicyAssignments.tsx, only per the §3 answer

### Verification
- `npx tsc --noEmit` and `npm run lint` are clean, with no unused imports left behind (e.g.
  `FREQ_MULT` if `annualTotal` replaces it).
- `grep -n "fixed inset-0" Leave_components/*.tsx` finds only NewVersionModal, the narrow
  backdrop/rail and (option A) AssignmentModal.
- Browser check by the user (shared DB), at ≥1000px and <1000px:
  - Leave types: inline create/edit, dirty-switch confirm, archive.
  - Policies: create with CL/SL/EL; rule groups; Total-per-year redistribution; save lands on
    the view page; edit; dirty back/tab guard; New version; archive.
  - No skeleton layout shift, and screenshots compared side by side with the old UI.
