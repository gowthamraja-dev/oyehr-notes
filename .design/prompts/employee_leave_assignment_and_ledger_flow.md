# HRMS — Employee Leave Assignment & Leave Ledger Flow


## 1. Objective


Build the leave-assignment flow for an individual employee so that assigning leave entitlement does **not** directly overwrite a balance.


The employee's leave balance must be derived from an auditable **employee leave ledger**.


The core rule is:


> **Every credit, debit, adjustment, reversal, or expiry affecting an employee's leave balance must be represented as a ledger transaction.**


The employee's current balance is calculated from ledger transactions, while the leave assignment record explains **why/how the entitlement was granted**.


---


## 2. Existing UI / Product Context


The existing HRMS has:


- A **Manager Portal** with Employee Directory and employee profile tabs including Overview, Attendance, Leave and Documents. The Manager Portal also has a Leave area for leave requests/holiday management. 
- An **Employee Portal** with `My Leave`, leave balances, leave requests and the employee home-page leave balance. The current prototype shows balances such as Casual Leave, Sick Leave and Earned Leave and supports submitting leave requests.
- An **Admin Console** containing leave-policy configuration and a leave approval workflow. The existing workflow explicitly indicates that the leave balance is updated on final approval.


Relevant source references:
- Employee Portal leave navigation and leave request UI: `Employee Portal.dc.html`
- Manager Portal leave queue and employee profile leave tab: `Manager Portal.dc.html`
- Admin leave workflow / policy configuration: `Admin Console.dc.html`


The prototype currently contains sample balances and sample leave requests; the production implementation must replace these with database-backed values.


---


# 3. Recommended Architecture


Separate these three concepts:


### A. Leave Policy


Defines the rules.


Examples:


- Casual Leave
- Sick Leave
- Earned Leave
- Comp-off


Policy controls may include:


- annual entitlement
- monthly accrual
- accrual frequency
- carry-forward rules

source can distinguish:

POLICY
MANUAL
OPENING_BALANCE
CARRY_FORWARD
ACCRUAL
COMP_OFF
IMPORT
REVERSAL

Do not use JSONB for these structured values.

C. Employee Leave Ledger

The ledger is the source of truth for the employee's leave movement.

Every movement becomes one ledger row.

Examples:

+12.00 Casual Leave  → annual assignment
+1.00  Casual Leave  → monthly accrual
-2.00  Casual Leave  → approved leave
+2.00  Casual Leave  → cancelled/reversed leave
+3.00  Earned Leave  → carry-forward
-1.00  Earned Leave  → manual adjustment

The ledger should be append-oriented.

Do not update historical ledger rows to make the balance "look right".

If something must be corrected, create a compensating transaction.

4. Ledger Direction

Use a single signed quantity field.

quantity > 0  = CREDIT
quantity < 0  = DEBIT

Example:

Transaction	Quantity
Annual entitlement	+12
Monthly accrual	+1
Leave approved	-2
Leave cancellation	+2
HR correction	+0.5
Expiry	-3

This keeps balance calculation simple:

current_balance =
    opening_balance
    + SUM(all valid ledger credits/debits)

If an explicit transaction_type is also stored, keep it as a controlled value:

CREDIT
DEBIT

The sign of quantity remains authoritative.

5. Assignment → Ledger Flow
Step 1 — Manager/HR selects employee

From the Manager Portal Employee Directory:

Employee Directory
    ↓
Employee
    ↓
Leave
    ↓
Leave Assignment

The assignment action should be available only to users with the required permission.

Suggested permission:

leave.assignment.create
Step 2 — Select leave type

Load active leave types from the configured leave-policy/master data.

Example:

Casual Leave
Sick Leave
Earned Leave
Comp-off

Do not hard-code these values in the UI.

Step 3 — Select assignment method

The assignment screen should support:

Policy entitlement

Used when assigning an employee's normal entitlement.

Example:

Leave Type: Earned Leave
Period: FY 2026–27
Entitlement: 18 days
Source: Policy
Manual assignment

Used for HR adjustments or exceptional grants.

Example:

Leave Type: Casual Leave
Quantity: 2 days
Reason: Additional entitlement approved by HR
Source: Manual
Carry-forward

Used when entitlement is carried from the previous leave period.

Opening balance

Used when migrating/importing an existing employee balance.

Comp-off

Used when earned through an eligible attendance/work event.

6. Important Rule: Assignment Must Create Ledger Credit

When an assignment is successfully created:

leave_assignment
        +
employee_leave_ledger

Example:

Employee:

EMP-0142

Assignment:

Casual Leave
12 days
FY 2026–27

Ledger entry:

employee_id = EMP-0142
leave_type_id = Casual Leave
transaction_type = CREDIT
quantity = +12
source_type = ASSIGNMENT
source_id = <assignment_id>

The assignment and ledger transaction must be created in one database transaction.

Do not create the assignment first and update the ledger later in a separate request.

7. Leave Request → Ledger Debit

The existing Admin workflow states that leave balance is updated on final approval.

Therefore:

Employee submits leave
        ↓
Pending
        ↓
Manager approval
        ↓
Other workflow approvals
        ↓
Final approval
        ↓
Ledger debit

Do not debit the employee ledger when the request is merely submitted.

Do not debit when the first approval happens unless that stage is explicitly configured as final approval.

The debit should happen exactly once when the leave request reaches its balance-impacting approved state.

Example:

Employee balance:

Casual Leave = 12

Employee requests:

2 days

After final approval:

Ledger:
-2 Casual Leave

Balance becomes:

10
8. Leave Cancellation / Reversal

If an approved leave is cancelled after it already affected the ledger:

Do not modify the original debit.

Create a reversal credit.

Original:

LEAVE_APPROVAL
quantity = -2

Cancellation:

LEAVE_CANCELLATION
quantity = +2

Both entries remain auditable.

Recommended relationship:

reversal_of_ledger_id

This allows the system to identify exactly which transaction was reversed.

9. Leave Modification

If an approved leave changes from:

3 days → 2 days

Do not update the original -3 ledger entry.

Create:

+1

as an adjustment/reversal transaction.

If it changes from:

2 days → 4 days

create:

-2

as an additional debit.

This preserves the complete audit trail.

10. Prevent Double Debit

The leave approval operation must be idempotent.

A leave request must not produce multiple ledger debits if:

the approval API is retried
the user double-clicks Approve
a network request is repeated
a workflow worker retries
the approval callback is processed twice

Recommended protection:

unique(source_type, source_id, transaction_type)

or an equivalent unique business key for balance-impacting transactions.

For a leave request:

source_type = LEAVE_REQUEST
source_id   = leave_request_id
transaction_type = DEBIT

Only one debit should be possible.

11. Balance Calculation

The system should not maintain an independently editable balance field as the source of truth.

Calculate:

balance =
    SUM(ledger.quantity)

for:

employee_id
leave_type_id

and the relevant balance period/rules.

For example:

Casual Leave


+12  Annual assignment
 +1  Monthly accrual
 -2  Approved leave
 +2  Cancelled leave
----------------------
=13 days

If the system later introduces opening balances or expiry, those are simply additional ledger transactions.

12. Current Balance vs Available Balance

For leave application, distinguish:

Ledger balance

Balance after all posted transactions.

ledger_balance = SUM(posted ledger quantity)
Reserved / pending amount

If business rules require pending requests to reserve balance, calculate pending/reserved separately.

Example:

Ledger balance: 10
Pending requests: 2
Available to apply: 8

Do not debit the ledger merely to reserve a pending request.

If the business does not reserve pending leave, then:

available = ledger balance

This must be a deliberate policy decision.

13. Employee Portal

The Employee Portal should read balance data from the ledger service/API.

The current prototype displays:

Leave balance
Casual Leave
Sick Leave
Earned Leave

The production version should replace static values with API-backed values.

Example response:

GET /employees/{employeeId}/leave-balances

Conceptual response:

[
  {
    "leaveTypeId": 1,
    "leaveType": "Casual Leave",
    "balance": 10.0,
    "reserved": 1.0,
    "available": 9.0
  },
  {
    "leaveTypeId": 2,
    "leaveType": "Sick Leave",
    "balance": 8.0,
    "reserved": 0.0,
    "available": 8.0
  }
]

The actual database implementation should use normal relational columns rather than JSONB.

14. Manager Portal — Employee Leave

The existing Manager Portal already has an employee profile Leave tab and a Leave module.

Recommended enhancement:

Employee Directory
  → Employee Profile
      → Leave
          → Balance
          → Assignment
          → Ledger
          → Leave History
Balance section

Show:

Leave Type	Assigned	Accrued	Used	Adjustments	Balance
Casual	12	1	2	0	11
Sick	12	0	4	0	8
Earned	18	0	5	0	13

The exact calculation should come from ledger transactions.

15. Assignment UI

Recommended drawer/modal:

Assign Leave
Employee

Read-only selected employee.

Dr. Ananya Sharma
EMP-0142
Cardiology
Leave Type

Dropdown.

Assignment Source

Dropdown:

Policy entitlement
Manual adjustment
Opening balance
Carry forward
Comp-off
Effective From

Date.

Effective To

Date.

Quantity

Number input.

Reason

Required for manual adjustments.

Reference

Optional/reference number where applicable.

Preview

Before saving:

Current balance       10 days
New credit             +2 days
Projected balance     12 days
Actions
Cancel
Assign leave
16. Assignment Validation

Before creating an assignment:

Required
employee exists
leave type exists
leave type is active
quantity > 0
effective period is valid
source is valid
current user has permission
Manual assignment

Require:

reason
Carry-forward

Validate against the previous period's eligible balance and carry-forward policy.

Comp-off

Validate the source event/work record if the business rule requires it.

Duplicate assignment

Prevent accidental duplicate annual entitlement assignment for the same employee, leave type and entitlement period unless explicitly allowed.

17. Database Transaction

Assignment operation:

BEGIN


1. Validate employee
2. Validate leave type
3. Validate assignment period
4. Validate permission
5. Create leave_assignment
6. Create employee_leave_ledger CREDIT
7. Write audit record


COMMIT

If any step fails:

ROLLBACK

There must never be:

assignment exists
ledger credit missing

or:

ledger credit exists
assignment missing
18. Leave Approval Transaction

Final approval operation:

BEGIN


1. Lock/check leave request
2. Confirm request is not already balance-posted
3. Validate available balance
4. Mark leave request approved
5. Create ledger DEBIT
6. Write audit record
7. Notify employee


COMMIT

If the debit cannot be created, the approval/balance-impacting operation must fail atomically.

19. Ledger Table — Recommended Shape

Use a relational table similar to:

employee_leave_ledger
----------------------
id
employee_id
leave_type_id
transaction_type
quantity
transaction_date
effective_date
source_type
source_id
assignment_id
leave_request_id
reversal_of_ledger_id
remarks
created_by
created_at

Possible transaction_type values:

CREDIT
DEBIT

Possible source_type values:

ASSIGNMENT
ACCRUAL
LEAVE_REQUEST
LEAVE_CANCELLATION
CARRY_FORWARD
OPENING_BALANCE
COMP_OFF
EXPIRY
MANUAL_ADJUSTMENT
REVERSAL

Do not store a generic unstructured "transaction metadata" JSONB column unless there is a demonstrated requirement.

20. Assignment Table — Recommended Shape
employee_leave_assignments
--------------------------
id
employee_id
leave_type_id
assignment_period_id
effective_from
effective_to
assigned_units
source_type
reference_id
reason
status
created_by
created_at
updated_at

The assignment is the entitlement record.

The ledger is the financial-style movement record for leave.

21. Optional Balance Snapshot

For performance, a balance snapshot table may be introduced later:

employee_leave_balance
----------------------
employee_id
leave_type_id
period_id
balance
last_ledger_id
updated_at

But this must be treated as a derived/cache value, not the audit source.

The ledger remains authoritative.

If a snapshot is used:

Ledger → update/rebuild snapshot

not:

Balance → overwrite ledger
22. Audit Requirements

Every assignment should record:

who assigned
when assigned
employee
leave type
quantity
source
reason
effective period

Every ledger transaction should be traceable back to its business event.

Examples:

+12 → Annual leave assignment #LA-102
-2  → Leave request #LR-884
+2  → Cancellation of leave request #LR-884
-1  → Manual adjustment #ADJ-41

This makes employee balance disputes explainable.

23. API Flow
Assign Leave
POST /employees/{employeeId}/leave-assignments

Request:

{
  "leave_type_id": 1,
  "effective_from": "2026-04-01",
  "effective_to": "2027-03-31",
  "assigned_units": 12,
  "source_type": "POLICY",
  "reason": "FY 2026-27 annual entitlement"
}

Backend:

validate
  ↓
create assignment
  ↓
create +12 ledger credit
  ↓
audit
  ↓
commit
Get Employee Balance
GET /employees/{employeeId}/leave-balances
Get Employee Ledger
GET /employees/{employeeId}/leave-ledger

Filters:

leave_type
date_from
date_to
source_type
transaction_type
Get Assignment History
GET /employees/{employeeId}/leave-assignments
24. Ledger UI

The Manager Portal employee Leave tab should have a ledger section.

Example:

Date	Leave Type	Description	Credit	Debit	Balance
01 Apr	Casual	FY entitlement	+12	—	12
01 May	Casual	Monthly accrual	+1	—	13
12 May	Casual	Leave approved	—	-2	11
20 May	Casual	Leave cancelled	+2	—	13

Clicking a row should open the source record.

Example:

Leave approved
Request: LR-884
2 days
18–19 May 2026
Approved by: HR Manager
25. Important Business Rules
Rule 1

Assignment creates a credit.

Rule 2

Approved leave creates a debit.

Rule 3

Pending leave does not automatically create a debit.

Rule 4

Cancellation creates a reversal credit.

Rule 5

Modification creates a compensating ledger transaction.

Rule 6

Historical ledger transactions are immutable.

Rule 7

No direct balance overwrite.

Rule 8

Every ledger transaction must have a source.

Rule 9

Ledger-affecting operations must be transactional.

Rule 10

Ledger posting must be idempotent.

Rule 11

Negative balance must be checked against the leave policy.

Rule 12

Assignment and ledger credit must be created atomically.

26. Handling Accrual

If leave accrues monthly:

Policy:
1 day/month

then the accrual engine creates:

+1
+1
+1
...

in the employee ledger.

The assignment does not need to be modified every month.

Example:

Assignment:
Annual entitlement policy → 12 eligible days


Ledger:
Apr +1
May +1
Jun +1
Jul +1
...

Whether the system creates an initial annual assignment or only monthly credits depends on the configured policy semantics. Do not create both unless the policy explicitly requires it, otherwise the employee will be double credited.

27. Carry Forward

At the end of a leave period:

previous balance = 5
carry-forward allowed = 3

Create:

+3
source_type = CARRY_FORWARD

If 2 days expire:

-2
source_type = EXPIRY

Never silently reset the balance to zero.

28. Manual Adjustment

HR should be able to add or remove leave.

Add:

+2
source_type = MANUAL_ADJUSTMENT
reason = "Approved by HR"

Remove:

-1
source_type = MANUAL_ADJUSTMENT
reason = "Correction for duplicate credit"

A negative manual adjustment must still obey authorization and audit rules.

29. Permissions

Recommended permissions:

leave.assignment.view
leave.assignment.create
leave.assignment.edit
leave.assignment.cancel
leave.ledger.view
leave.ledger.adjust

Managers may have:

leave.assignment.view
leave.ledger.view

HR/Admin may additionally have:

leave.assignment.create
leave.ledger.adjust

Do not expose manual ledger adjustment to ordinary managers unless explicitly required.

30. Notifications

After successful assignment:

Employee notification:
"2 Casual Leave days have been added to your balance."

After leave approval:

"Your leave request for 2 days has been approved.
2 days have been deducted from Casual Leave."

After cancellation:

"Your leave cancellation was processed.
2 Casual Leave days have been restored."
31. Failure Scenarios

The implementation must handle:

Insufficient balance
Requested: 5
Available: 3


Reject approval:
Insufficient Casual Leave balance.
Duplicate approval

Do not create another debit.

Duplicate assignment

Warn/block based on assignment-period rules.

Concurrent approvals

Use database locking / transactional consistency so two simultaneous approvals cannot consume the same balance incorrectly.

Failed notification

Do not roll back the ledger merely because notification delivery failed.

Notification delivery should be independently retryable after the successful business transaction.

32. Implementation Sequence
Phase 1 — Database
Create leave assignment table.
Create employee leave ledger table.
Add required foreign keys.
Add indexes.
Add uniqueness/idempotency constraints.
Add audit linkage.
Avoid JSONB for core fields.
Phase 2 — Assignment APIs
Create assignment.
List assignments.
Get assignment.
Cancel/reverse assignment where business rules permit.
Calculate balance.
Phase 3 — Leave Approval Integration

Connect final leave approval to ledger debit.

Final approval
    ↓
Ledger debit
Phase 4 — Cancellation / Modification

Implement compensating transactions.

Phase 5 — Manager UI

Add:

Employee
 → Leave
   → Balance
   → Assign Leave
   → Ledger
   → Assignment History
Phase 6 — Employee UI

Replace hard-coded leave balances with API data.

The current Employee Portal already exposes My Leave and displays leave balances, so this should consume the same backend balance calculation rather than maintain a separate employee-side balance.

Phase 7 — Audit & Notifications

Add audit records and employee notifications.

33. Acceptance Criteria
Assignment
 HR/authorized manager can select an employee.
 User can select a leave type.
 User can select assignment source.
 User can enter entitlement quantity.
 User can enter effective period.
 Manual assignments require a reason.
 Assignment creates a ledger credit.
 Assignment and credit are atomic.
 Duplicate assignment is prevented according to policy.
Balance
 Balance is derived from ledger transactions.
 Credits increase balance.
 Debits reduce balance.
 Pending leave does not incorrectly debit the ledger.
 Final approval creates exactly one debit.
 Cancellation creates a reversal credit.
 Modification creates a compensating transaction.
 Historical transactions remain unchanged.
Audit
 Every transaction has a source.
 Every assignment identifies creator and timestamp.
 Ledger entries can be traced to the originating assignment/request.
 Manual adjustments require a reason.
 Ledger history can be viewed by authorized users.
UI
 Manager can see current balance.
 Manager can assign leave.
 Manager can view assignment history.
 Manager can view employee ledger.
 Employee sees updated balance in My Leave.
 Employee sees leave approval/cancellation effects.
34. Final Design Decision

The recommended model is:

                    ┌─────────────────┐
                    │   Leave Policy  │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │ Leave Assignment│
                    └────────┬────────┘
                             │
                         creates
                             │
                             ▼
                    ┌─────────────────┐
                    │ Employee Leave  │
                    │     Ledger      │
                    └────────┬────────┘
                             │
                ┌────────────┼────────────┐
                ▼            ▼            ▼
             CREDIT        DEBIT       REVERSAL
                │            │            │
             Assign       Approved      Cancel
              leave         leave        leave
                │            │            │
                └────────────┼────────────┘
                             ▼
                    ┌─────────────────┐
                    │ Current Balance │
                    └─────────────────┘

The employee ledger is the authoritative balance movement history. Leave assignment is the entitlement/business record. Leave approval, cancellation, accrual, carry-forward, expiry and adjustments all become ledger transactions. No workflow should directly overwrite an employee's leave balance.
