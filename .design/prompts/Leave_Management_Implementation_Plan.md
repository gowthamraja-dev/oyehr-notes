Yeah. Good. I# Leave Management — Implementation Plan

## 1. Purpose

Implement the HRMS Leave Management module as an end-to-end employee and manager workflow.

The module must integrate with the existing:
- Employee Dashboard
- Attendance
- Shift Assignment
- Manager approval workflow
- Notifications
- Audit trail

### Design references

**Employee UI**
- `Employee Portal.dc.html`
- Existing My Leave screen
- Leave balance card
- Leave request form
- Leave history/list
- Existing dashboard Leave Balance and Open Requests cards

**Manager UI**
- `Manager Portal.dc.html`
- Existing approvals patterns
- Employee/team views
- Existing manager leave-related workflows

The Employee Portal already represents Leave as a core employee module and the dashboard exposes Leave Balance and Open Requests. Use those existing patterns rather than introducing a new visual system.

---

# 2. Scope

## Employee

Implement:

1. View leave balance.
2. View leave history.
3. View leave requests.
4. Apply for leave.
5. See pending/approved/rejected status.
6. Cancel a leave request where allowed.
7. See applicable holidays.
8. Receive leave notifications.

## Manager

Implement:

1. View pending leave requests.
2. Review leave request details.
3. Approve leave.
4. Reject leave.
5. Provide rejection reason.
6. View employee leave history/balance.
7. View team leave calendar/list.
8. Receive approval notifications.

## Backend

Implement:

1. Leave types.
2. Leave policies/balances.
3. Employee leave balances.
4. Leave requests.
5. Approval workflow.
6. Leave calculation.
7. Attendance integration.
8. Notifications.
9. Audit trail.

---

# 3. Core Leave Flow

The primary workflow is:

**Employee**

`View balance`
→ `Apply for leave`
→ `Pending`

**Manager**

`Review`
→ `Approve / Reject`

If approved:

`Approved`
→ `Leave balance updated`
→ `Attendance affected`
→ `Employee notified`

If rejected:

`Rejected`
→ `Leave balance unchanged`
→ `Employee notified`

---

# 4. Leave Types

Leave types should be master data rather than hard-coded in the employee UI.

Examples can include:

- Casual Leave
- Sick Leave
- Annual/Earned Leave
- Unpaid Leave

The actual production list must come from the configured leave setup.

Each leave type should have:

- ID
- Name
- Code
- Description
- Paid/unpaid indicator
- Active/inactive status
- Applicable policy
- Whether supporting document is required
- Whether half-day is allowed
- Whether cancellation is allowed

Do not introduce leave types that are not configured.

---

# 5. Leave Balance

Employee dashboard already exposes a **Leave Balance** KPI.

The value must come from the backend.

Display:

### Leave Balance

`21 days`

Optionally provide a breakdown:

| Leave Type | Available | Used | Pending |
|---|---:|---:|---:|
| Annual | 12 | 4 | 2 |
| Sick | 7 | 1 | 0 |
| Casual | 2 | 0 | 1 |

The exact balance calculation must follow the configured leave policy.

Do not hard-code the dashboard value.

---

# 6. Leave Balance Rules

The system should distinguish:

- Allocated
- Used
- Pending
- Available

Recommended conceptual calculation:

`Available = Allocated - Approved Used - Other Policy Adjustments`

Pending requests should be tracked separately unless the leave policy explicitly reserves them.

Do not silently deduct a pending request from the official used balance.

---

# 7. Employee — My Leave

Use the existing Employee Portal visual language.

The screen should contain:

### Summary

- Available leave
- Used leave
- Pending requests

### Actions

Primary:

**Apply for Leave**

### Leave history

Display:

| Leave Type | From | To | Days | Status |
|---|---|---|---:|---|
| Annual Leave | 20 Aug | 22 Aug | 3 | Pending |
| Sick Leave | 04 Aug | 04 Aug | 1 | Approved |
| Casual Leave | 28 Jul | 29 Jul | 2 | Rejected |

Use existing portal cards, badges, typography and spacing.

---

# 8. Apply for Leave

Employee selects:

**Apply for Leave**

Open the leave request form.

Fields:

### Leave Type

Required.

Select from active leave types available to the employee.

### From Date

Required.

### To Date

Required.

### Duration

Calculated from the selected dates.

Do not allow the client to freely submit a calculated number of days as authoritative data.

### Half Day

If enabled for the leave type:

- First half
- Second half

### Reason

Required according to configured policy.

### Supporting document

Optional or required according to leave type/policy.

### Contact/notes

Optional if supported by policy.

---

# 9. Leave Date Validation

Before submitting:

Validate:

- From date is not after To date.
- Dates are valid.
- Employee is eligible for the leave type.
- Leave type is active.
- Employee has sufficient available balance where applicable.
- Existing approved leave conflicts are detected.
- Existing pending leave conflicts are detected.
- Half-day rules are respected.
- Holiday/weekend treatment follows the configured leave policy.

The UI should show useful errors rather than allowing an invalid request to reach the approval queue.

---

# 10. Leave Day Calculation

The backend must calculate leave days.

The calculation must consider configured policy rules for:

- Weekends
- Holidays
- Half days
- Working days
- Consecutive leave
- Leave type rules

Example:

Requested:

`Thursday 20 Aug → Monday 24 Aug`

If Saturday/Sunday are non-working days, the payable/requested leave days may be:

`3 days`

The exact rule must come from the configured leave policy.

Do not hard-code Monday-Friday behavior into the frontend.

---

# 11. Leave Request Status

Initial workflow statuses:

- Draft, if drafts are implemented
- Pending
- Approved
- Rejected
- Cancelled

The Employee Portal should clearly show the current status.

Pending requests must appear in the dashboard's **Open Requests** count/list.

---

# 12. Submit Leave Request

Employee selects:

**Submit request**

Backend:

1. Authenticate employee.
2. Validate leave type.
3. Calculate leave days.
4. Validate balance.
5. Validate conflicts.
6. Create request.
7. Set status to Pending.
8. Create audit event.
9. Notify the appropriate manager/approver.

Employee sees:

`Leave request submitted.`

---

# 13. Leave Approval

Manager opens:

**Leave Requests / Approvals**

Show:

- Employee
- Department
- Leave type
- From date
- To date
- Number of days
- Reason
- Supporting document
- Current balance
- Submitted date
- Status

Actions:

**Approve**

**Reject**

---

# 14. Manager Approval Validation

At approval time, the backend must revalidate:

- Employee is still active.
- Leave type is still active.
- Leave dates are still valid.
- No conflicting approved leave has appeared.
- Balance is still sufficient where required.
- Manager is authorized to approve the employee.

Do not rely only on validations performed when the employee submitted the request.

This prevents stale requests from being approved incorrectly.

---

# 15. Approve Leave

When manager approves:

1. Confirm request is Pending.
2. Confirm manager authorization.
3. Recalculate leave days.
4. Revalidate balance/conflicts.
5. Set status to Approved.
6. Update leave balance/ledger.
7. Create attendance impact for applicable dates.
8. Create audit record.
9. Notify employee.

---

# 16. Reject Leave

When manager selects:

**Reject**

Require:

`Rejection reason`

Then:

1. Set status to Rejected.
2. Store rejection reason.
3. Store reviewer.
4. Store review timestamp.
5. Create audit event.
6. Notify employee.

Leave balance remains unchanged.

---

# 17. Cancellation

Employees may need to cancel a leave request.

Support:

`Cancel request`

Rules:

- Pending requests can normally be cancelled.
- Approved leave cancellation must follow configured policy.
- Past leave should not be cancelled through a simple employee action.
- Cancellation must be audited.

For approved leave cancellation:

`Approved → Cancellation requested → Manager review`

if the policy requires approval.

Do not assume cancellation behavior if the leave policy has not yet defined it.

---

# 18. Leave and Attendance Integration

Approved leave must affect attendance.

Example:

Employee has:

`Annual Leave`
`20 Aug – 22 Aug`

Attendance for applicable dates should resolve as:

`On Leave`

rather than:

`Absent`

or:

`Missing Punch`

The attendance engine should check approved leave when calculating daily attendance.

Conceptual priority:

`Holiday / Weekly Off`
→ `Approved Leave`
→ `Attendance Punch`
→ `Absent`

The exact precedence must be finalized in the attendance policy.

---

# 19. Leave and Shift Integration

Shift assignment determines the employee's expected work schedule.

Leave determines whether the employee is expected to attend on a particular date.

Example:

**Shift**

`Morning · 09:00–17:30`

**Approved leave**

`20 Aug`

Attendance for 20 Aug:

`On Leave`

No clock-in should be required for that leave date.

If an employee clocks in on an approved leave date, the system should preserve the punch and flag the policy conflict rather than silently deleting it.

---

# 20. Holiday Integration

Leave calculation should use the applicable holiday calendar.

Example:

If an employee requests:

`15 Aug – 18 Aug`

and 15 Aug is an applicable holiday, the leave-day calculation should follow the configured holiday policy.

The Employee Portal already exposes a Holiday Calendar module, so leave should consume the same holiday data rather than maintaining a separate holiday list.

---

# 21. Team Leave View

Manager should be able to see team leave.

Recommended view:

| Employee | Leave | From | To | Days | Status |
|---|---|---|---|---:|---|
| Ananya Sharma | Annual | 20 Aug | 22 Aug | 3 | Approved |
| Rohan Desai | Sick | 21 Aug | 21 Aug | 1 | Pending |

Optional calendar representation can be added later.

The manager must only see employees within their authorization scope.

---

# 22. Leave Conflict Detection

When submitting or approving leave, detect:

### Employee conflict

Existing approved leave overlaps requested dates.

### Pending conflict

Another pending leave request overlaps requested dates.

### Attendance conflict

Existing attendance/punch data exists for the requested leave date.

### Policy conflict

Leave violates configured policy.

The system should explain the conflict.

Example:

`You already have approved Annual Leave from 20 Aug to 22 Aug.`

---

# 23. Leave Balance Ledger

Do not rely only on a mutable balance number.

Recommended approach:

Maintain a leave ledger.

Examples:

- Opening allocation
- Accrual
- Approved leave deduction
- Adjustment
- Carry-forward
- Expiry
- Reversal

Then derive the employee's balance from the ledger according to policy.

This will make cancellation and corrections auditable.

---

# 24. Recommended PostgreSQL Model

## `leave_types`

- `id`
- `code`
- `name`
- `description`
- `is_paid`
- `requires_document`
- `allows_half_day`
- `status`
- `created_at`
- `updated_at`

## `leave_policies`

- `id`
- `name`
- `description`
- `accrual_rule`
- `carry_forward_rule`
- `approval_rule`
- `status`
- `created_at`
- `updated_at`

Policy-specific configuration should use normal relational columns/tables where possible rather than putting the core model into JSONB.

## `employee_leave_balances`

- `id`
- `employee_id`
- `leave_type_id`
- `leave_year`
- `allocated_days`
- `used_days`
- `pending_days`
- `available_days`
- `created_at`
- `updated_at`

## `leave_requests`

- `id`
- `employee_id`
- `leave_type_id`
- `from_date`
- `to_date`
- `requested_days`
- `duration_type`
- `half_day_period`
- `reason`
- `status`
- `submitted_at`
- `reviewed_by`
- `reviewed_at`
- `rejection_reason`
- `created_at`
- `updated_at`

## `leave_request_documents`

- `id`
- `leave_request_id`
- `file_id`
- `created_at`

## `leave_ledger`

- `id`
- `employee_id`
- `leave_type_id`
- `leave_request_id`
- `transaction_type`
- `days`
- `reference`
- `created_at`

## `leave_audit_log`

- `id`
- `leave_request_id`
- `action`
- `old_value`
- `new_value`
- `actor_id`
- `actor_role`
- `created_at`

---

# 25. API Plan

## Employee

### Leave summary

`GET /api/me/leave/balance`

### Leave requests

`GET /api/me/leave/requests`

Filters:
- status
- from date
- to date

### Request leave

`POST /api/me/leave/requests`

### View request

`GET /api/me/leave/requests/{id}`

### Cancel request

`POST /api/me/leave/requests/{id}/cancel`

### Leave calendar

`GET /api/me/leave/calendar`

---

# 26. Manager APIs

`GET /api/manager/leave/requests`

Filters:
- status
- employee
- department
- date range

`GET /api/manager/leave/requests/{id}`

`POST /api/manager/leave/requests/{id}/approve`

`POST /api/manager/leave/requests/{id}/reject`

`GET /api/manager/leave/team-calendar`

---

# 27. Admin / Configuration APIs

These are configuration APIs rather than employee workflows.

`GET /api/leave/types`

`POST /api/leave/types`

`PUT /api/leave/types/{id}`

`PATCH /api/leave/types/{id}/status`

Policy APIs should be added once the exact leave-policy rules are finalized.

---

# 28. Dashboard Integration

The Employee Dashboard already exposes:

### Leave Balance

This must come from:

`GET /api/me/leave/balance`

### Open Requests

Pending leave requests must contribute to the existing Open Requests count.

The dashboard must not separately calculate leave requests using a different definition.

Flow:

`Leave Request Pending`
→ `Open Requests +1`

`Leave Request Approved/Rejected/Cancelled`
→ `Open Requests -1`

---

# 29. Notifications

Support at minimum:

### Employee submits

`Leave request submitted`

### Manager receives

`New leave request from {{employee}}`

### Approved

`Your {{leave_type}} request from {{from_date}} to {{to_date}} has been approved.`

### Rejected

`Your leave request has been rejected.`

Include rejection reason.

### Cancellation

Notify the appropriate manager/employee according to workflow.

Use the existing HRMS notification framework rather than creating a leave-specific notification mechanism.

---

# 30. Security

## Employee

Employee can:
- View own balance.
- View own leave requests.
- Create own requests.
- Cancel own eligible requests.

Employee cannot:
- Modify another employee's balance.
- Approve/reject requests.
- Change leave policy.
- Change leave types.

## Manager

Manager can:
- View authorized employees.
- Review authorized employee requests.
- Approve/reject authorized requests.

Manager cannot modify global leave policy unless separately authorized.

All authorization must be enforced server-side.

---

# 31. Idempotency and concurrency

Approval and leave-balance updates must be transaction-safe.

Example:

Two managers must not both approve the same request.

When approving:
- Lock/check the request.
- Confirm status is still Pending.
- Revalidate balance/conflicts.
- Apply balance transaction.
- Change status.
- Commit as one transaction.

If the transaction fails, the request and balance must remain consistent.

---

# 32. Audit requirements

Audit:

- Leave request created
- Leave request edited
- Leave request submitted
- Leave request approved
- Leave request rejected
- Leave request cancelled
- Leave balance adjusted
- Leave balance restored
- Policy/admin changes

Record:
- Actor
- Role
- Timestamp
- Old value
- New value
- Reason/reference

---

# 33. UI acceptance criteria

## Employee

- [ ] My Leave opens from Employee Portal.
- [ ] Current balance is shown.
- [ ] Leave breakdown is shown where configured.
- [ ] Employee can apply for leave.
- [ ] Active leave types are loaded from backend.
- [ ] Leave days are calculated by backend rules.
- [ ] Invalid/conflicting dates are rejected.
- [ ] Supporting documents are supported where required.
- [ ] Submitted request appears as Pending.
- [ ] Employee can view status.
- [ ] Approved request appears as Approved.
- [ ] Rejected request shows rejection reason.
- [ ] Eligible requests can be cancelled.
- [ ] Pending leave contributes to dashboard Open Requests.

## Manager

- [ ] Manager can open pending leave requests.
- [ ] Manager can view complete request details.
- [ ] Manager sees employee balance/context.
- [ ] Manager can approve.
- [ ] Manager can reject.
- [ ] Rejection reason is required.
- [ ] Approval revalidates balance/conflicts.
- [ ] Team leave can be viewed.
- [ ] Manager sees only authorized employees.

## Attendance integration

- [ ] Approved leave prevents the date from being treated as Absent.
- [ ] Approved leave is reflected in attendance.
- [ ] Shift assignment remains available for the date.
- [ ] Existing punches on leave dates are not silently deleted.
- [ ] Conflicting punch/leave conditions are handled according to policy.

---

# 34. Phase boundary

## Include now

- Leave types
- Employee leave balance
- Apply for leave
- Leave history
- Manager approval/rejection
- Leave cancellation
- Leave/attendance integration
- Holiday-aware leave calculation
- Dashboard integration
- Notifications
- Audit trail

## Do not include yet unless separately specified

- Complex accrual automation
- Payroll deduction
- Encashment
- Advanced carry-forward rules
- Multi-level approval chains
- External HR/payroll integration
- Work location dependency

These can be added after the core leave workflow is stable.

---

# 35. Implementation order

Build in this order:

### Phase 1 — Data foundation
`Leave Types`
→ `Leave Policy`
→ `Employee Leave Balance`
→ `Leave Ledger`

### Phase 2 — Employee
`My Leave`
→ `Apply for Leave`
→ `Leave History`
→ `Cancel`

### Phase 3 — Manager
`Pending Requests`
→ `Review`
→ `Approve / Reject`

### Phase 4 — Integration
`Approved Leave`
→ `Attendance`
→ `Dashboard`
→ `Notifications`

### Phase 5 — Hardening
`Audit`
→ `Concurrency`
→ `Authorization`
→ `Edge Cases`
→ `Testing`

---

# 36. Core business flow

**Leave Type**
→ defines what can be requested

**Leave Policy**
→ defines how it behaves

**Employee Balance**
→ defines available entitlement

**Leave Request**
→ employee asks for leave

**Manager Approval**
→ authorized decision

**Leave Ledger**
→ records the financial/entitlement effect

**Attendance**
→ reflects approved absence

**Dashboard**
→ reflects balance and open requests

**Audit**
→ records every important change

---

# 37. Important design principle

Do not make the Employee Portal responsible for deciding whether leave is valid.

The frontend should provide a good user experience, but the backend must be authoritative for:

- Leave-day calculation
- Balance
- Policy eligibility
- Conflicts
- Approval
- Attendance impact

The UI should display backend decisions consistently across Employee and Manager screens.
