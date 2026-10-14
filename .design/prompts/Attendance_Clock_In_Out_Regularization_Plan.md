# Attendance Clock In / Clock Out & Request Regularization — Implementation Plan

## 1. Purpose
Implement employee attendance clock-in/clock-out and attendance regularization as a full-stack HRMS flow using the existing Employee Portal and Manager Portal design patterns.

**Design references**
- `Employee Portal.dc.html` — My Attendance, clock card, live timer, attendance history, regularization modal.
- `Manager Portal.dc.html` — attendance analytics, employee attendance details, and approval patterns.

The Employee Portal already contains a My Attendance screen with the employee's shift, clock state, elapsed worked time, clock-in time, attendance rate, and attendance table. fileciteturn4file17

The source regularization state includes date, punch type, in/out times, reason, note, attachment, and request status. Example statuses include Approved and Pending. fileciteturn4file0

---

## 2. Scope

### Employee
- View today's attendance and assigned shift.
- Clock in.
- Clock out.
- See live worked duration.
- View attendance history.
- Request regularization.
- View regularization status/history.

### Manager
- View employee attendance.
- View clock-in/clock-out details and attendance status.
- Review pending regularization requests.
- Approve/reject regularization.
- View regularization history.

### Backend
- Persist attendance sessions/punches.
- Validate clock actions server-side.
- Calculate worked time and attendance status.
- Persist regularization requests.
- Apply approved corrections.
- Maintain audit history and notifications.

---

## 3. Shift relationship

The assigned shift is the source of the expected work window.

Example:

**Morning Shift**
- Start: 09:00
- End: 17:30

Actual punches:
- In: 09:07
- Out: 17:42

The attendance engine can determine lateness, worked hours, early departure, and potential overtime according to configured policy.

The Employee Portal already displays `Morning shift (09:00 – 17:30)` on My Attendance. fileciteturn4file17

For this phase, **do not add `work_location_id`**.

---

# 4. Employee — My Attendance

Use the existing Employee Portal layout.

Header:
- `My Attendance`
- Current month/date period
- Today's assigned shift and expected time

Example:
`July 2026 · Morning shift (09:00 – 17:30)`

All values must come from backend data.

---

# 5. Clock Card

Follow the existing source design.

### Clocked out
- Status: `Clocked out`
- No active elapsed timer
- Primary action: `Clock in`

### Clocked in
- Status: `On the clock`
- Live elapsed duration
- Clock-in time
- Primary action: `Clock out`

The source implementation switches between Clock in and Clock out according to the employee's current state and calculates elapsed time from the clock-in timestamp. fileciteturn4file14

The frontend timer is display-only. The server is authoritative.

---

# 6. Clock In Flow

Employee selects **Clock in**.

Backend must:
1. Identify the authenticated employee.
2. Resolve today's shift assignment.
3. Record server timestamp.
4. Check for an existing open attendance session.
5. Determine attendance status from shift start/grace rules.
6. Persist the punch/session.
7. Return the authoritative attendance state.

If already clocked in, reject the duplicate action.

Example error:
`You are already clocked in.`

On success:
`Clocked in — welcome back`

---

# 7. Clock Out Flow

Employee selects **Clock out**.

Backend must:
1. Identify the authenticated employee.
2. Find the open attendance session.
3. Record server timestamp.
4. Calculate worked duration.
5. Determine final attendance state.
6. Close the session.

If no active clock-in exists:
`No active clock-in found.`

Worked time must be calculated from persisted timestamps, not from a client-side timer.

---

# 8. Overnight shifts

Support shifts such as:

`22:00 – 06:00`

A clock-in on 17 Aug at 22:05 and clock-out on 18 Aug at 06:03 must belong to the same attendance session.

---

# 9. Attendance statuses

Use the existing HRMS terminology where supported:
- Present
- Late
- Absent
- On Leave
- Half Day
- Holiday
- Weekly Off
- Regularization Pending
- Regularized

The Manager Portal already uses Present/Late and attendance hours in its analytics. fileciteturn4file12

Do not invent additional business rules without a corresponding attendance policy.

---

# 10. Attendance history

Employee should see:

| Date | Shift | Clock In | Clock Out | Worked | Status |
|---|---|---|---|---|---|
| 17 Aug | Morning | 09:04 | 17:38 | 8h 34m | Present |
| 16 Aug | Morning | 09:19 | 17:30 | 8h 11m | Late |
| 15 Aug | Holiday | — | — | — | Holiday |

Reuse the existing Employee Portal attendance-table design. fileciteturn4file17

---

# 11. Request Regularization

Purpose:

**Correct a missed or wrong punch.**

The Employee Portal already contains a `Request regularization` modal with this purpose. fileciteturn4file8

## Fields

### Date
Required.

### Punch
Required:
- Clock-in
- Clock-out
- Both

### In time
Required when Clock-in or Both is selected.

### Out time
Required when Clock-out or Both is selected.

### Reason
Required.

Initial reason choices based on the source/example:
- Forgot to punch
- Wrong punch time
- Biometric error
- Device issue
- System issue
- Other

### Note
Additional explanation.

### Attachment
Optional unless attendance policy requires proof.

The source already includes an attachment state in the regularization form. fileciteturn4file0

---

# 12. Regularization validation

Before submission:
- Date must be valid for the employee's attendance history.
- Future dates should be rejected unless explicitly allowed by policy.
- Punch type is required.
- Required in/out times must be supplied.
- Normal same-day out time cannot precede in time.
- Overnight shifts must be handled correctly.
- Duplicate active regularization requests for the same employee/date/punch should be prevented unless policy permits resubmission.

---

# 13. Submit regularization

Employee selects **Submit request**.

Backend creates a request with:

`Pending`

Employee sees:
`Regularization request submitted.`

The request appears in the employee's regularization history.

---

# 14. Employee regularization history

Use the existing source pattern:

| Date | Punch | Reason | Status |
|---|---|---|---|
| 02 Jul 2026 | Clock-out | Forgot to punch | Approved |
| 28 Jun 2026 | Both | Biometric error | Pending |

The source explicitly contains this pattern. fileciteturn4file0

Statuses:
- Pending
- Approved
- Rejected

Rejected requests should show the rejection reason.

---

# 15. Manager regularization queue

Manager should have a pending regularization view.

Example:

| Employee | Date | Punch | Reason | Submitted | Action |
|---|---|---|---|---|---|
| Rohan Desai | 24 Jun | Both | Forgot to punch | 24 Jun | Review |

The Admin Console source also represents Regularization as a pending approval item. fileciteturn4file5

---

# 16. Manager review

Open a regularization request and show:

### Employee
- Name
- Employee ID
- Department
- Shift

### Existing attendance
- Date
- Scheduled shift
- Existing clock-in
- Existing clock-out
- Existing worked time
- Existing status

### Requested correction
- Requested clock-in
- Requested clock-out
- Reason
- Note
- Attachment

Actions:
- **Approve**
- **Reject**

---

# 17. Approve

On approval:
1. Confirm request is still Pending.
2. Validate manager authorization.
3. Apply corrected punch values.
4. Recalculate attendance.
5. Mark request Approved.
6. Store approver and timestamp.
7. Create audit entry.
8. Notify employee.

The official attendance record changes only after approval.

---

# 18. Reject

On rejection:
1. Require rejection reason.
2. Mark request Rejected.
3. Store reviewer and timestamp.
4. Create audit entry.
5. Notify employee.

The official attendance remains unchanged.

---

# 19. Notification

The Admin Console already defines an Attendance Regularization notification template:
- Event: `Punch missed`
- Channel: `In-app`
- Example subject: `Missing punch on {{date}}`
- Template references a configured regularization window. fileciteturn4file1

Support notifications for:
- Missing punch
- Request submitted
- Request approved
- Request rejected

Notification enablement/channel should remain controlled by the notification configuration.

---

# 20. Audit trail

Every attendance-changing action must be auditable.

Record:
- Employee
- Attendance record
- Regularization request, if applicable
- Action
- Old value
- New value
- Actor
- Actor role
- Timestamp
- Reason/source

Examples:
- Employee clocked in
- Employee clocked out
- Employee submitted regularization
- Manager approved regularization
- Manager rejected regularization

---

# 21. Recommended PostgreSQL model

## `attendance_records`
- `id`
- `employee_id`
- `attendance_date`
- `shift_id`
- `status`
- `clock_in_at`
- `clock_out_at`
- `worked_minutes`
- `late_minutes`
- `early_departure_minutes`
- `created_at`
- `updated_at`

## `attendance_regularizations`
- `id`
- `employee_id`
- `attendance_record_id`
- `attendance_date`
- `punch_type`
- `requested_in_at`
- `requested_out_at`
- `reason_code`
- `reason_note`
- `attachment_id`
- `status`
- `submitted_at`
- `reviewed_by`
- `reviewed_at`
- `rejection_reason`
- `created_at`
- `updated_at`

## `attendance_audit_log`
- `id`
- `employee_id`
- `attendance_record_id`
- `regularization_id`
- `action`
- `old_value`
- `new_value`
- `actor_id`
- `actor_role`
- `created_at`

No `work_location_id` is required in this phase.

---

# 22. API plan

## Employee clock

`POST /api/me/attendance/clock-in`

Request:
```json
{}
```

The server determines employee, timestamp, shift, and attendance status.

`POST /api/me/attendance/clock-out`

Request:
```json
{}
```

The server determines timestamp, worked duration, and final state.

## Employee attendance

`GET /api/me/attendance/today`

`GET /api/me/attendance?from=&to=&status=`

## Employee regularization

`GET /api/me/attendance/regularizations`

`GET /api/me/attendance/regularizations/{id}`

`POST /api/me/attendance/regularizations`

`POST /api/me/attendance/regularizations/{id}/cancel`

## Manager

`GET /api/manager/attendance`

`GET /api/manager/attendance/{employeeId}`

`GET /api/manager/attendance/regularizations`

`GET /api/manager/attendance/regularizations/{id}`

`POST /api/manager/attendance/regularizations/{id}/approve`

`POST /api/manager/attendance/regularizations/{id}/reject`

---

# 23. Security

### Employee
Can only:
- Clock themselves in/out.
- View their own attendance.
- Submit their own regularization.
- View their own regularization requests.

### Manager
Can only review employees inside their authorized scope.

Authorization must be enforced server-side, not only through UI visibility.

Never trust a client-supplied employee ID for ownership.

---

# 24. Duplicate protection

Protect clock operations against:
- Double-clicks
- Network retries
- Browser refresh
- Multiple tabs

Rules:
- One employee cannot have two active clock-in sessions.
- A closed session cannot receive another clock-out.
- Active regularization duplicates must be blocked according to policy.

---

# 25. Shift and regularization example

Scheduled:
`Morning · 09:00–17:30`

Actual:
`09:15 – 17:30`

Employee requests:
`Clock-in → 09:00`

After manager approval:
`09:00 – 17:30`

The system must retain the audit fact that the original punch was corrected through regularization.

---

# 26. UI design rules

Follow the existing Employee Portal:
- White cards
- Light application background
- Teal primary actions
- Compact status badges
- Inter typography
- JetBrains Mono for durations/times
- Rounded 10–16px controls/cards
- Existing toast treatment
- Existing modal overlay

The existing My Attendance screen already provides the clock card and attendance summary pattern. fileciteturn4file17

The existing regularization modal should be the direct visual reference. fileciteturn4file8

For manager review, use the existing Manager Portal attendance analytics and employee detail patterns. fileciteturn4file12 fileciteturn4file13

---

# 27. End-to-end flows

## Normal day

`Employee opens portal`
→ `Today's shift displayed`
→ `Clock in`
→ `Attendance session created`
→ `Live worked timer`
→ `Clock out`
→ `Attendance finalized`
→ `Attendance history updated`

## Missed punch

`Missing/incomplete attendance`
→ `Employee notified`
→ `Request regularization`
→ `Select date`
→ `Select punch`
→ `Enter corrected time`
→ `Enter reason`
→ `Submit`
→ `Pending`
→ `Manager review`
→ `Approve`
→ `Attendance corrected`
→ `Employee notified`

If rejected:
`Pending → Rejected → Attendance unchanged`

---

# 28. Acceptance criteria

## Clock in
- [ ] Employee can clock in.
- [ ] Server records authoritative timestamp.
- [ ] Duplicate clock-in is prevented.
- [ ] Today's shift is resolved.
- [ ] Attendance status is calculated.
- [ ] UI changes to On the clock.
- [ ] Live timer starts from persisted clock-in.
- [ ] Refresh retains clock state.

## Clock out
- [ ] Employee can clock out.
- [ ] Server records authoritative timestamp.
- [ ] Worked duration is calculated server-side.
- [ ] Duplicate clock-out is prevented.
- [ ] UI changes to Clocked out.
- [ ] Attendance history updates.

## Regularization
- [ ] Employee can open Request regularization.
- [ ] Date is required.
- [ ] Punch type is required.
- [ ] Required punch times are validated.
- [ ] Reason is required.
- [ ] Note and attachment are supported.
- [ ] Request starts Pending.
- [ ] Employee can see request status.
- [ ] Manager can review.
- [ ] Manager can approve.
- [ ] Manager can reject.
- [ ] Rejection reason is stored.
- [ ] Approved request updates attendance.
- [ ] Rejected request leaves official attendance unchanged.
- [ ] Audit history is created.

## Security
- [ ] Employee cannot clock another employee.
- [ ] Employee cannot modify another employee's attendance.
- [ ] Employee cannot approve their own regularization.
- [ ] Manager authorization is enforced server-side.
- [ ] Attendance changes are auditable.

---

# 29. Phase boundary

### Include
- Clock in
- Clock out
- Shift-based attendance
- Attendance history
- Regularization request
- Manager approval/rejection
- Notifications
- Audit trail

### Do not include yet
- `work_location_id`
- Geofencing
- GPS validation
- Biometric-device integration
- Face recognition
- Mobile location tracking
- Complex payroll overtime calculations

The Admin Console does show attendance integrations such as BioTime Access and eSSL SmartOffice, but those should be a later integration phase rather than a dependency for the initial employee clock-in/out flow. fileciteturn4file11

# 30. Core rule

**Shift Assignment**
→ expected work time

**Clock In / Clock Out**
→ actual punches

**Attendance Engine**
→ attendance result

**Regularization**
→ controlled correction request

**Manager Approval**
→ authorized attendance correction

**Audit**
→ permanent record of what changed, who changed it, and why
