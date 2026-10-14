# P2P Full-Stack Development Prompt — Leave Policies Admin Flow

## 1. Objective

Implement the **Leave Policies** module end-to-end in the HRMS Admin flow.

The implementation must replace the existing Admin Console mock/static leave-policy behavior with a real PostgreSQL-backed full-stack implementation.

The feature must allow an authorized HR Admin/HR Manager to:

- View configured leave types.
- Create a leave type.
- View the policy configuration for a leave type.
- Create or update a leave policy.
- Configure entitlement/accrual rules.
- Configure carry-forward rules.
- Configure encashment rules.
- Configure joining/proration behavior.
- Configure effective and termination dates.
- Configure corporation and employee-type applicability where supported by the existing schema.
- Activate/deactivate policies without physically deleting historical policy data.
- Preserve auditability.
- Ensure downstream employee leave balance calculations can use the policy configuration.
- Keep the existing Admin Console visual language and interaction model.

Do **not** create a table called `leave_policys` merely because the feature is called "Leave Policies".

Use the existing schema:

- `leave_type_masters`
- `leave_policy_details`
- `employee_leave_balance_ledgers`
- `leave_request_details`
- `leave_request_day_details`

The schema explicitly defines `leave_policy_details` as the policy layer split from leave types because accrual can vary by employee type/corporation.

---

# 2. UI References — Mandatory

Use the supplied files as the primary UI reference.

### Primary UI reference

`Admin Console.dc.html`

The existing Admin Console already establishes:

- NanoHealth HRMS Console shell.
- Dark teal left rail.
- Search bar.
- Breadcrumb strip.
- Secondary configuration panel.
- Main configuration form.
- Save action in the header.
- Selected-item styling.
- Grouped configuration sections.
- Toast feedback.
- Admin identity and permissions model.

The Admin Console uses:

> Home → Control Center → module

and has a secondary panel for configuration sections.

For Leave Policies, preserve this exact information architecture.

### Existing Leave Policy navigation

The current mock Admin Console defines:

**Leave types**

- Annual / Earned Leave
- Sick Leave
- Casual Leave
- Maternity Leave
- Comp-off

and separately:

**Attendance**

- Regularization
- Late-mark Rules

Do not mix attendance policies into this implementation. Leave Policies should operate only on the `Leave types` group.

### Employee Portal reference

Use `Employee Portal.dc.html` to validate how policy configuration ultimately affects the employee experience.

The employee portal already exposes:

- My Leave
- Leave balance
- Apply leave
- Leave history

and displays balances such as "Leave balance".

The employee UI is **not** being redesigned in this task. Its existing leave behavior should eventually consume the real policy/balance data rather than hard-coded values.

### Manager Portal reference

Use `Manager Portal.dc.html` as the downstream approval reference.

The manager portal already exposes:

- Leave requests.
- Leave approval.
- Pending leave requests.
- Reporting-manager approval behavior.

Do not rebuild the manager approval workflow in this task unless an API contract requires compatibility.

---

# 3. Existing Database Model

Use the existing PostgreSQL tables.

## 3.1 `leave_type_masters`

Relevant columns:

```text
id
care_delivery_program_master_id
name
code
is_paid
unit
allow_half_day
requires_approval
requires_document
doc_required_after_days
max_consecutive_days
min_notice_days
allow_negative_balance
gender_applicable
applicable_after_days
exclude_week_offs
exclude_holidays
display_order
color_code
is_active
effctv_dt
trmntn_dt
archive
archived_by_id
archived_at
created_by_id
updated_by_id
created_at
updated_at
```

The schema comments establish:

- `code`: CL / SL / EL / ML / LOP examples.
- `unit`: Day / Hour.
- `gender_applicable`: maternity/paternity gating.
- `applicable_after_days`: probation/eligibility gate.

This table represents the **leave type itself** and request/application behavior.

---

# 4. `leave_policy_details`

Use the existing table as the main policy configuration table.

Relevant columns:

```text
id
care_delivery_program_master_id
leave_type_master_id
corp_master_id
employee_type_master_id
accrual_frequency
accrual_quantity
max_balance
carry_forward
max_carry_forward
encashable
max_encashment
prorate_on_joining
reset_month
is_active
effctv_dt
trmntn_dt
archive
archived_by_id
archived_at
created_by_id
updated_by_id
created_at
updated_at
```

The schema documents `accrual_frequency` as:

```text
Monthly
Quarterly
Yearly
OnJoining
```

and `reset_month` as:

```text
1–12, leave-year start
```

The schema also explicitly says that `leave_policy_details` exists because accrual can differ by employee type/corporation for the same leave type.

Do not introduce JSONB for policy configuration.

Store policy attributes in relational columns.

---

# 5. Important Separation of Responsibility

Do not duplicate fields unnecessarily.

## Leave Type controls application/request rules

`leave_type_masters` controls:

- Paid/unpaid.
- Day/hour unit.
- Half-day support.
- Whether approval is required.
- Whether documentation is required.
- Documentation threshold.
- Maximum consecutive days.
- Minimum notice.
- Negative balance.
- Gender applicability.
- Eligibility after joining/probation.
- Week-off exclusion.
- Holiday exclusion.
- Active/effective state.

## Leave Policy controls entitlement/balance rules

`leave_policy_details` controls:

- Accrual frequency.
- Accrual quantity.
- Maximum balance.
- Carry-forward.
- Maximum carry-forward.
- Encashment.
- Maximum encashment.
- Proration on joining.
- Leave-year reset month.
- Applicability by corporation.
- Applicability by employee type.
- Effective/termination period.

Do not create duplicate columns in another table for these existing concepts.

---

# 6. Target Admin Information Architecture

Implement:

```text
Admin Console
  ↓
Control Center
  ↓
Leave Policies
  ↓
Leave types
      ├── Annual / Earned Leave
      ├── Sick Leave
      ├── Casual Leave
      ├── Maternity Leave
      └── Comp-off
```

The secondary panel should continue using the visual pattern already implemented in `Admin Console.dc.html`.

The selected policy should have:

- Teal background.
- Teal border.
- Stronger label.
- White/icon treatment consistent with the current Admin Console.

The current mock implementation already follows this pattern.

---

# 7. Leave Policy List Screen

The left/secondary panel should display leave types.

For each leave type show:

```text
Leave type name
Short policy summary
Status indicator
```

Example:

```text
Annual / Earned Leave
21 days · Monthly accrual
● Active
```

Do not hard-code these values.

Generate the summary from the database.

For example:

```text
Annual / Earned Leave
21 days · Monthly
```

or:

```text
Sick Leave
12 days · Yearly
```

The existing UI currently uses summaries such as:

- `21 days · accrual`
- `12 days · certificate`
- `12 days · monthly cap`
- `26 weeks · statutory`

These are design references only; the backend values must become the source of truth.

---

# 8. Main Policy Form

When a leave type is selected, display the policy form.

The existing Admin Console already defines the intended fields.

For Annual/Earned Leave the mock contains:

### Entitlement

```text
Annual quota
Accrual
Accrual rate
Pro-rate for new joiners
```

### Rules

```text
Allow carry-forward
Max carry-forward
Encashment allowed
Minimum notice
```

The actual implementation must map these concepts to the existing relational schema rather than retaining the mock form model.

---

# 9. Form Design

Do not create one giant form.

Organize the page into logical cards/sections.

Recommended structure:

## A. Leave Type

Show basic type information:

```text
Leave type
Code
Paid / Unpaid
Unit
Active
```

Where appropriate, provide a link/action to edit leave-type configuration.

However, keep leave-type master configuration logically separate from policy configuration.

---

## B. Applicability

Fields:

```text
Corporation
Employee Type
Effective From
Effective Until
```

Rules:

- Corporation may be `All corporations`.
- Employee type may be `All employee types`.
- Effective date is required when creating a policy.
- Termination date must be >= effective date.
- Only active policies should participate in current policy resolution.
- Do not silently overwrite historical policies when a new effective period is created.

`corp_master_id` and `employee_type_master_id` are existing columns specifically intended for this applicability layer.

If employee type master does not currently exist in the database, do not invent a fake foreign-key implementation. Keep the API field nullable and expose the selector only when the backend has a valid employee-type source.

---

# 10. Entitlement Section

Use:

```text
Accrual frequency
Accrual quantity
Maximum balance
Prorate on joining
Reset month
```

Accrual frequency options:

```text
Monthly
Quarterly
Yearly
On Joining
```

These options are directly supported by the schema.

Examples:

### Monthly

```text
Accrual frequency = Monthly
Accrual quantity = 1.75
```

means:

```text
1.75 days per monthly accrual event
```

### Yearly

```text
Accrual frequency = Yearly
Accrual quantity = 21
```

### On Joining

Use `OnJoining` exactly as the database frequency value.

Do not create a separate enum table unless the existing application architecture requires it.

---

# 11. Carry Forward Section

Fields:

```text
Allow carry-forward
Maximum carry-forward
```

Behavior:

If:

```text
carry_forward = false
```

then:

```text
max_carry_forward
```

must not be accepted as an effective configuration.

The UI should disable/hide the maximum field when carry-forward is disabled.

Backend must still validate this.

Example:

```text
carry_forward = true
max_carry_forward = 10
```

means up to 10 days can be carried into the next leave year.

---

# 12. Encashment Section

Fields:

```text
Encashment allowed
Maximum encashment
```

If:

```text
encashable = false
```

then:

```text
max_encashment
```

must be null/ignored.

Do not implement encashment using a free-form JSON configuration.

Use:

```text
encashable
max_encashment
```

from `leave_policy_details`.

---

# 13. Joining / Proration

Expose:

```text
Pro-rate on joining
```

This maps directly to:

```text
prorate_on_joining
```

Do not calculate the actual employee balance inside the Admin API.

The policy API stores the configuration.

The balance/accrual service is responsible for applying the configuration to employees.

---

# 14. Leave Year

Expose:

```text
Leave year starts in
```

Options:

```text
January
February
...
December
```

Persist as:

```text
reset_month = 1..12
```

Do not store month names in the database.

---

# 15. Leave Type Request Rules

The UI should make it clear that some settings belong to the leave type, not `leave_policy_details`.

Where the Admin Console already has policy concepts such as:

```text
Minimum notice
Require medical certificate
Certificate needed after X days
Allow backdated application
Maximum consecutive days
```

verify whether the corresponding value already exists in `leave_type_masters`.

Do not add duplicate columns to `leave_policy_details`.

For example:

```text
min_notice_days
requires_document
doc_required_after_days
max_consecutive_days
```

already exist on `leave_type_masters`.

Use those columns.

---

# 16. API Architecture

Implement REST APIs.

Base path:

```text
/api/admin/leave
```

## 16.1 List leave types

```http
GET /api/admin/leave/types
```

Response should provide enough information for the secondary navigation:

```text
id
name
code
is_paid
unit
is_active
display_order
policy_summary
```

Do not return unnecessary employee-level data.

---

# 17. Get Leave Type + Policy

```http
GET /api/admin/leave/types/:leaveTypeId/policy
```

Return:

```text
leaveType
policy
applicability
entitlement
carryForward
encashment
dates
```

Do not use JSONB.

A normal relational response object is fine at the API layer.

---

# 18. Create Leave Type

If the Leave Policies screen supports adding a new leave type:

```http
POST /api/admin/leave/types
```

Request:

```text
name
code
is_paid
unit
allow_half_day
requires_approval
requires_document
doc_required_after_days
max_consecutive_days
min_notice_days
allow_negative_balance
gender_applicable
applicable_after_days
exclude_week_offs
exclude_holidays
display_order
color_code
effctv_dt
```

Validate:

- Name required.
- Code required.
- Code unique within tenant.
- Unit valid.
- Numeric values non-negative.
- Effective date valid.

The schema already has a unique index on tenant + code.

---

# 19. Create Policy

```http
POST /api/admin/leave/types/:leaveTypeId/policies
```

Request:

```text
corp_master_id
employee_type_master_id
accrual_frequency
accrual_quantity
max_balance
carry_forward
max_carry_forward
encashable
max_encashment
prorate_on_joining
reset_month
effctv_dt
trmntn_dt
```

Backend must inject:

```text
care_delivery_program_master_id
created_by_id
updated_by_id
```

from authenticated context.

Do not accept tenant identity blindly from the browser.

---

# 20. Update Policy

```http
PATCH /api/admin/leave/policies/:policyId
```

Only update fields that are allowed to change.

Because policy configuration can affect future balance calculations, do not blindly mutate a historical policy that has already been used for accrual.

Implement one of these behaviors according to the existing application architecture:

### Preferred

If the policy is already effective/used:

```text
close existing policy
create new effective-dated policy
```

rather than rewriting historical policy history.

The schema has:

```text
effctv_dt
trmntn_dt
archive
archived_at
```

which supports this effective-dated approach.

---

# 21. Activate / Deactivate

```http
PATCH /api/admin/leave/policies/:policyId/status
```

Request:

```text
is_active
```

Do not delete the policy.

Use:

```text
is_active
```

and, where required for historical records:

```text
archive
archived_at
archived_by_id
```

---

# 22. Policy Resolution

Create a service such as:

```text
resolveLeavePolicy(
  tenantId,
  leaveTypeId,
  employeeId,
  effectiveDate
)
```

The service should resolve the applicable policy using:

1. Tenant.
2. Leave type.
3. Employee's corporation.
4. Employee type when available.
5. Effective date.
6. Active status.
7. Applicable policy specificity.

Do not put this logic into the React/UI layer.

Do not let the browser decide which policy applies.

---

# 23. Policy Conflict Validation

Prevent overlapping active policies that would create ambiguous resolution.

Examples:

```text
Annual Leave
Corporation = All
Employee Type = All
Effective = 2026-01-01
```

and another:

```text
Annual Leave
Corporation = All
Employee Type = All
Effective = 2026-06-01
```

must not both be active for the same effective period unless the implementation deliberately supports versioning.

For corporation/employee-type-specific policies, define deterministic precedence.

Preferred precedence:

```text
Employee Type + Corporation
        ↓
Employee Type + All Corporation
        ↓
All Employee Types + Corporation
        ↓
All + All
```

If the current schema/application has a different established resolution rule, follow that instead.

---

# 24. Database Transaction Rules

Creating/updating a leave policy must be transactional.

For example:

```text
BEGIN

validate leave type
validate tenant
validate applicability
validate dates
validate overlapping policy
insert/update leave_policy_details

write audit record

COMMIT
```

On failure:

```text
ROLLBACK
```

Do not leave partially updated policy data.

---

# 25. Validation Rules

Backend validation is mandatory even if the frontend validates.

### Numeric

```text
accrual_quantity >= 0
max_balance >= 0
max_carry_forward >= 0
max_encashment >= 0
```

### Carry forward

If:

```text
carry_forward = false
```

then:

```text
max_carry_forward = null
```

### Encashment

If:

```text
encashable = false
```

then:

```text
max_encashment = null
```

### Accrual

`accrual_frequency` must be one of:

```text
Monthly
Quarterly
Yearly
OnJoining
```

### Reset month

Must be:

```text
1..12
```

or null where appropriate.

### Dates

```text
trmntn_dt >= effctv_dt
```

### Tenant

Every query must be scoped by:

```text
care_delivery_program_master_id
```

---

# 26. Audit

Leave policy changes are configuration changes.

The existing Admin Console already has an Audit concept and contains examples such as:

```text
Updated leave policy
Sick Leave · accrual rate ...
```

and categorizes configuration activity under `Configuration`.

Every successful policy mutation should therefore create an audit entry containing at minimum:

```text
actor
action
entity
entity_id
timestamp
```

Preferably include changed fields/diff if the existing audit architecture supports it.

Do not create audit records for failed transactions.

---

# 27. Save UX

Follow the Admin Console pattern.

The existing policy screen already uses:

```text
Save
```

as the primary action and gives feedback such as:

```text
Annual / Earned Leave policy saved
```

after saving.

Implement:

### Unsaved changes

If form is dirty:

```text
Save
```

enabled.

If no changes:

```text
Save
```

disabled or visually subdued.

### Successful save

Show the existing Admin Console toast style:

```text
Leave policy saved
```

Then refresh the policy data from the backend.

Do not assume the local form state is the source of truth.

---

# 28. Loading State

When switching leave types:

```text
secondary list remains visible
main panel shows skeleton/loading state
```

Do not flash stale data from the previously selected policy.

---

# 29. Error State

API errors should appear inline or as an Admin Console-compatible alert/toast.

Examples:

```text
Unable to load leave policy.
```

```text
Another policy already covers this effective period.
```

```text
Maximum carry-forward is required when carry-forward is enabled.
```

Do not expose raw PostgreSQL errors to the user.

---

# 30. Empty State

If a leave type has no policy:

Display:

```text
No leave policy configured

Configure entitlement, accrual and balance rules for this leave type.

[Create policy]
```

Do not display fake values.

---

# 31. New Leave Type Flow

When admin clicks:

```text
Add leave type
```

open a modal/drawer consistent with the existing Admin Console modal styling.

Minimum fields:

```text
Leave type name
Code
Paid / Unpaid
Unit
Allow half day
Requires approval
Active
Effective from
```

After creation:

```text
create leave_type_masters
↓
open its policy page
↓
show empty policy state
↓
admin configures policy
↓
Save
```

Do not automatically create a fake policy containing arbitrary defaults unless there is an explicit business default.

---

# 32. Leave Type Examples

The current UI mock contains these examples:

### Annual / Earned Leave

```text
Quota: 21
Accrual: Monthly
Rate: 1.75/month
Prorate: Yes
Carry forward: Yes
Maximum carry forward: 10
Encashment: Yes
Minimum notice: 3
```

### Sick Leave

```text
Quota: 12
Medical certificate: Yes
Certificate after: 2 days
Backdated application: Yes
```

### Casual Leave

```text
Quota: 12
Monthly cap: 2
Clubbing: No
```

### Maternity Leave

```text
Duration: 26 weeks
Eligibility: 2.5 months
Fully paid: Yes
```

### Comp-off

```text
Enabled: Yes
Expiry: 60 days
Manager approval: Yes
```

These values are **UI reference/mock data**, not mandatory seed values. The actual implementation must derive persisted values from the database.

Also note that some of these mock fields do not map directly to `leave_policy_details`; where an equivalent already exists in `leave_type_masters`, use that existing column instead of extending the policy table.

---

# 33. Employee Leave Balance Integration

Do not calculate balances directly from `leave_policy_details` on every employee request.

The existing architecture already has:

```text
employee_leave_balance_ledgers
```

which is explicitly designed as an append-only balance ledger. Its transaction types include:

```text
Opening
Accrual
Availed
Reversal
CarryForward
Encashment
LapseExpiry
Adjustment
```

and quantity is signed.

Therefore:

```text
Leave Policy
     ↓
Accrual/Balance service
     ↓
employee_leave_balance_ledgers
     ↓
Employee Portal balance
```

Do not modify balances merely because an admin opened or edited the policy form.

Policy changes affect future accrual/application behavior according to the effective date.

---

# 34. Leave Request Integration

Existing `leave_request_details` contains:

```text
employee_master_id
leave_type_master_id
from_date
to_date
total_days
status
approver_user_id
```

and existing day-detail rows contain:

```text
leave_date
day_fraction
is_week_off
is_holiday
```

The database comments explicitly state that day details make attendance joining and LOP arithmetic straightforward.

The Leave Policy implementation must therefore provide the policy data required by the leave-request service to determine:

- Eligibility.
- Minimum notice.
- Maximum consecutive days.
- Whether holidays count.
- Whether week-offs count.
- Whether negative balance is allowed.
- Required documentation.
- Applicable balance.

Do not duplicate these calculations in the Admin frontend.

---

# 35. API-to-UI Flow

Implement this exact flow:

```text
Admin logs in
    ↓
Admin Console
    ↓
Control Center
    ↓
Leave Policies
    ↓
GET /api/admin/leave/types
    ↓
Render leave types in secondary panel
    ↓
Admin selects Annual / Earned Leave
    ↓
GET /api/admin/leave/types/{id}/policy
    ↓
Render policy form
    ↓
Admin changes accrual / carry-forward / encashment
    ↓
Frontend validates
    ↓
PATCH /api/admin/leave/policies/{policyId}
    ↓
Backend validates
    ↓
Database transaction
    ↓
Audit record
    ↓
Return updated policy
    ↓
Frontend refreshes state
    ↓
Success toast
```

For a leave type without a policy:

```text
GET policy
    ↓
404 / NO_POLICY
    ↓
Empty state
    ↓
Create policy
    ↓
POST policy
```

---

# 36. Frontend State

Replace the existing static state:

```text
selectedPolicy
seg
toggles
...
```

with server-backed state.

Recommended conceptual state:

```text
leaveTypes
selectedLeaveTypeId
selectedPolicy
loading
saving
error
dirty
form
```

Do not maintain independent copies of the same policy values in multiple components.

Use one normalized form state.

---

# 37. Frontend Components

Keep the existing Admin Console shell.

Implement components logically equivalent to:

```text
LeavePoliciesPage
LeaveTypeList
LeaveTypeListItem
LeavePolicyForm
PolicyApplicabilitySection
PolicyEntitlementSection
PolicyCarryForwardSection
PolicyEncashmentSection
PolicyEffectiveDateSection
CreateLeaveTypeModal
UnsavedChangesGuard
```

Use the existing Admin Console typography, spacing, border, teal accent, cards and buttons.

Do not introduce a completely different design system.

---

# 38. Responsive Behavior

The current Admin Console is desktop-oriented.

Preserve the current desktop layout but ensure:

- Secondary panel does not overlap the form.
- Main form scrolls independently.
- Long policy forms remain usable.
- Header actions remain visible.
- Form controls wrap gracefully at smaller widths.

Do not redesign the entire Admin Console for mobile in this task.

---

# 39. Security / Authorization

Respect the existing permission model.

The Admin Console's permission matrix already defines Leave permissions with actions such as:

```text
View
Create
Edit
Delete
Approve
```

and includes role-specific leave permissions.

For this feature:

### View

Required to load policies.

### Create

Required to create a leave type/policy.

### Edit

Required to modify a policy.

### Delete

Do not use physical delete for historical policies.

If deletion is exposed, implement archive/deactivate semantics.

Do not rely solely on hiding buttons in the frontend. Backend authorization is mandatory.

---

# 40. Important: Do Not Implement These in This Task

Do not expand the scope into:

- Employee leave application redesign.
- Manager approval redesign.
- New workflow builder.
- Payroll calculation.
- Attendance regularization.
- Holiday management.
- Work-location management.
- Shift scheduling.
- New employee-type master.
- New organization structure.
- Mobile UI redesign.

Only implement the Leave Policy Admin flow and the backend contracts required to make it functional.

---

# 41. Avoid JSONB

The PostgreSQL architecture should remain relational.

Do not create:

```text
policy_config JSONB
rules JSONB
accrual JSONB
eligibility JSONB
```

The existing schema already has dedicated relational columns.

Use them.

API response JSON is normal and expected; the restriction is specifically against using JSONB as the persistence model for this policy.

---

# 42. Migration Requirement

Before writing a migration:

1. Inspect the existing schema.
2. Confirm whether `leave_policy_details` already exists in the deployed database.
3. Do not recreate an existing table.
4. Only add missing indexes/constraints if genuinely required.
5. Do not change existing column names casually.

The supplied SQL already contains the table and foreign keys:

```text
leave_policy_details.care_delivery_program_master_id
    → care_delivery_program_masters.id

leave_policy_details.leave_type_master_id
    → leave_type_masters.id

leave_policy_details.corp_master_id
    → corp_masters.id
```

Use these existing relationships.

---

# 43. Testing Requirements

Implement tests for:

## API

- List leave types.
- Get policy.
- Create policy.
- Update policy.
- Activate/deactivate.
- Unauthorized access.
- Cross-tenant access prevention.
- Invalid accrual frequency.
- Invalid reset month.
- Negative numeric values.
- Carry-forward validation.
- Encashment validation.
- Date overlap.
- Missing leave type.
- Missing policy.

## Database

Test:

```text
tenant isolation
foreign keys
effective dates
policy uniqueness/overlap
```

## Frontend

Test:

```text
loading
empty policy
existing policy
dirty form
save
save failure
leave-type switching
validation
conditional fields
```

---

# 44. Acceptance Criteria

The feature is complete only when all of the following work against the real PostgreSQL database.

### Admin

- [ ] Admin can open Leave Policies.
- [ ] Leave types are loaded from DB.
- [ ] Leave types are not hard-coded.
- [ ] Selecting a leave type loads its policy.
- [ ] Existing policy values are populated from DB.
- [ ] Admin can edit policy.
- [ ] Admin can save policy.
- [ ] Save persists to `leave_policy_details`.
- [ ] Admin receives success feedback.
- [ ] Refreshing the browser preserves saved values.
- [ ] Admin can create a policy where none exists.
- [ ] Admin can deactivate a policy.
- [ ] Historical policy data is not physically destroyed.
- [ ] Effective dates are enforced.
- [ ] Corporation applicability is persisted.
- [ ] Employee-type applicability is persisted when supported.
- [ ] Carry-forward configuration works.
- [ ] Encashment configuration works.
- [ ] Accrual configuration works.
- [ ] Proration configuration works.
- [ ] Leave-year reset month works.
- [ ] Audit entry is created for successful mutations.

### Architecture

- [ ] PostgreSQL remains the source of truth.
- [ ] No policy configuration is persisted as JSONB.
- [ ] No fake/mock policy data remains in the production flow.
- [ ] Tenant isolation is enforced server-side.
- [ ] Authorization is enforced server-side.
- [ ] Policy resolution remains backend/service responsibility.
- [ ] Existing leave balance ledger architecture is preserved.
- [ ] Existing Employee and Manager UI contracts are not unnecessarily broken.

### UI

- [ ] Admin Console visual language is preserved.
- [ ] Secondary panel follows the existing configuration pattern.
- [ ] Main policy form follows existing grouped-card styling.
- [ ] Save action remains in the Admin Console header.
- [ ] Loading/empty/error states are implemented.
- [ ] Toast feedback follows existing Admin Console styling.
- [ ] No new unrelated design system is introduced.

---

# 45. Final Implementation Principle

Treat the feature as:

```text
leave_type_masters
        │
        │ defines WHAT leave is
        ▼
leave_policy_details
        │
        │ defines HOW entitlement/accrual works
        ▼
policy resolution service
        │
        ├───────────────┐
        ▼               ▼
leave requests     balance ledger
        │               │
        ▼               ▼
Manager Portal     Employee Portal
```

The Admin Leave Policy screen is therefore a **configuration layer**, not the place where employee balances are manually calculated.

Build the backend around the existing relational schema, expose clean REST APIs, connect the Admin Console UI to those APIs, and preserve the existing NanoHealth Admin Console UX exactly as the visual reference.

Do not replace existing schema concepts with new abstractions unless the current database genuinely cannot support the requirement.