# Shift Assignment — Manager & Employee UI Implementation Prompt

## Objective

Implement the Shift Assignment functionality for the HRMS using the existing Manager Portal and Employee Portal designs as the visual and interaction references.

For this phase:

**DO NOT implement `work_location_id`.**

Shift assignment must work completely without a work-location foreign key.

The implementation should integrate into the existing HRMS rather than creating a separate visual system.

---

# 1. Design References

## Manager Screen Reference

Use:

**`Manager Portal.dc.html`**

This is the primary reference for the Manager-side Shift Assignment UI.

Follow its existing:
- HRMS Console layout
- Dark teal sidebar
- Top search/action bar
- Page header structure
- Cards
- Tables
- Roster grid
- Employee avatar treatment
- Status badges
- Modal/drawer patterns
- Typography
- Spacing
- Borders
- Teal/neutral color system

The existing Manager Portal already contains a weekly employee roster with:
- Employee rows
- Seven day columns
- Shift values inside each day
- Clickable shift cells
- Reassignment interaction
- Shift selection popup

Use that interaction pattern rather than inventing a completely new UI.

The existing roster data also demonstrates employees with:
- Morning
- Afternoon
- General
- Night
- Off
- Rotational

and shift reassignment from a roster cell. 
---

## Employee Screen Reference

Use:

**`Employee Portal.dc.html`**

This is the primary reference for the employee-facing Shift/Today view.

Follow its existing:
- Employee Portal sidebar
- Header
- Search
- Notification treatment
- Current attendance clock control
- Dashboard cards
- Quick actions
- Employee-specific information hierarchy
- Teal/white/gray visual language

The existing Employee Dashboard already displays:

`Today · Morning shift · Cardiology`

and has a clock-in/clock-out control in the top header.

The employee shift information should therefore feel like a natural extension of the existing dashboard rather than a separate application.

---

# 2. Manager Shift Assignment

## Manager navigation

Add/use:

**Manager Portal → Shift Management / Shift Roster**

Do not create a separate standalone application.

The primary screen should be a roster-oriented view.

---

# 3. Manager Shift Roster

Display a weekly roster.

### Header

Show:

- Page title: `Shift Roster`
- Description: `Assign and manage employee shifts`
- Date/week selector
- Previous week
- Next week
- Today
- Filter
- Search employee
- Add/Create Shift action if applicable

---

# 4. Roster Grid

Use the existing Manager Portal roster pattern.

Columns:

| Employee | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
|---|---|---|---|---|---|---|---|

Employee column should show:

- Avatar/initials
- Employee name
- Employee ID
- Department

Each day cell should show the assigned shift.

Example:

`Morning`
`09:00–18:00`

or compactly:

`Morning`

with the time shown beneath it when space permits.

---

# 5. Shift Types

The UI should support the configured shift definitions.

Initial examples from the existing design:

- Morning
- General
- Afternoon
- Night
- Off

Rotational employees may have different shifts on different days.

Do not hard-code the shift list in the final backend.

The UI must obtain active shift definitions from the backend.

---

# 6. Assign Shift

When the manager clicks a roster cell:

Open the existing-style shift selection interaction.

Show:

**Assign shift**

Employee:
`Dr. Ananya Sharma`

Date:
`Monday, 17 Aug 2026`

Available shifts:

- Morning — 06:00–14:00
- General — 09:00–18:00
- Afternoon — 14:00–22:00
- Night — 22:00–06:00
- Off

Current selection should be clearly indicated.

Manager selects one shift and clicks:

`Assign`

---

# 7. Shift Assignment Data

For this phase the assignment should contain:

- Employee ID
- Shift ID
- Assignment date
- Assignment status
- Created by
- Created timestamp
- Updated timestamp

Do NOT include:

`work_location_id`

Do not make work location a required field.

---

# 8. Fixed vs Rotational

The system must distinguish between:

### Fixed

Employee normally works the same shift.

Example:

`Dr. Ananya Sharma → Morning`

### Rotational

Employee may have different shifts on different dates.

Example:

| Date | Shift |
|---|---|
| Monday | Morning |
| Tuesday | Night |
| Wednesday | Off |
| Thursday | Afternoon |
| Friday | Morning |

The roster is therefore the source of the employee's actual shift for a specific date.

Do not assume that an employee whose pattern is `Rotational` has one permanent shift.

---

# 9. Manager Assignment Rules

Before saving an assignment:

Validate:

- Employee exists
- Shift exists
- Shift is active
- Date is valid
- Employee is eligible for the shift
- Existing assignment for the same employee/date is handled correctly

If an assignment already exists:

Do not create a duplicate.

Update the existing assignment or require an explicit reassignment action.

---

# 10. Conflict Handling

If the employee already has:

- Approved leave
- Another shift assignment
- A conflicting roster entry

show an appropriate warning.

Example:

**Shift conflict**

`Dr. Ananya Sharma is on approved leave for this date.`

Actions:

`Cancel`

`Assign anyway`

The exact business rule for overriding approved leave should be configurable/finalized separately. Do not silently overwrite it.

---

# 11. Employee Shift Screen

Use:

**`Employee Portal.dc.html`**

as the visual reference.

The employee should have a clear **My Shift / Today's Shift** area.

It can be part of the Employee Dashboard or the employee's attendance area.

---

# 12. Employee Today's Shift Card

Display:

### Today's Shift

**Morning Shift**

`09:00 – 18:00`

Department:

`Cardiology`

Status:

`Scheduled`

If currently working:

`On the clock`

with:

`Clocked in at 08:57`

and worked duration.

The existing Employee Portal already has the clock state and worked-time behavior, so the shift display should integrate with it.

---

# 13. Employee Shift Information

Employee should be able to see:

- Today's shift
- Start time
- End time
- Break duration, if configured
- Department
- Shift status
- Upcoming shifts

Example:

### Upcoming shifts

| Date | Shift | Time |
|---|---|---|
| Mon, 17 Aug | Morning | 09:00–18:00 |
| Tue, 18 Aug | Morning | 09:00–18:00 |
| Wed, 19 Aug | Night | 22:00–06:00 |

---

# 14. Employee Permissions

Employee must be able to **view** their assigned shifts.

Employee must NOT be able to:

- Change their own shift
- Assign another employee's shift
- Delete a shift assignment
- Modify shift definitions

If shift swap functionality is implemented later, it should be a separate employee workflow.

---

# 15. Shift → Attendance Relationship

The assigned shift for a date becomes the employee's expected attendance window.

Example:

Assigned shift:

`Morning — 09:00–18:00`

Employee clocks in:

`09:14`

The attendance system can determine whether the employee is late based on:

- Shift start time
- Configured grace period

The Manager Portal already displays attendance statuses such as `Present`, `Late`, and attendance hours, so the shift assignment must become the source for expected timing.

The shift assignment should therefore be available when calculating:

- Expected start
- Expected end
- Late arrival
- Early departure
- Worked hours
- Attendance status
- Potential overtime

The exact overtime/early-departure policy should not be invented as part of this UI task.

---

# 16. Overnight Shift

Support shifts crossing midnight.

Example:

`Night — 22:00–06:00`

The assignment date represents the shift's scheduled start date.

Example:

Assignment date:

`17 Aug 2026`

Shift:

`22:00–06:00`

The attendance system must associate the 06:00 clock-out with the same overnight shift rather than treating it as an unrelated next-day shift.

---

# 17. API Requirements

Implement backend APIs for:

### Shift definitions

`GET /api/shifts`

Return active shift definitions.

`POST /api/shifts`

Create a shift definition.

`PUT /api/shifts/{id}`

Update a shift definition.

`PATCH /api/shifts/{id}/status`

Activate/deactivate a shift.

---

### Shift assignments

`GET /api/shift-assignments`

Support filters:

- employee
- department
- date
- date range
- shift

`POST /api/shift-assignments`

Create an employee shift assignment.

`PUT /api/shift-assignments/{id}`

Update/reassign an assignment.

`DELETE /api/shift-assignments/{id}`

Remove an assignment where permitted.

---

### Employee

`GET /api/me/shifts`

Return the logged-in employee's upcoming/current shifts.

`GET /api/me/shifts/{date}`

Return the employee's shift for a specific date.

---

# 18. PostgreSQL Data Model

Do not use JSONB for the core shift assignment structure.

Recommended tables:

### `shifts`

- `id`
- `name`
- `code`
- `start_time`
- `end_time`
- `break_minutes`
- `grace_minutes`
- `is_overnight`
- `status`
- `created_at`
- `updated_at`

### `employee_shift_assignments`

- `id`
- `employee_id`
- `shift_id`
- `assignment_date`
- `status`
- `created_by`
- `created_at`
- `updated_at`

Add a unique constraint on:

`employee_id + assignment_date`

unless the final business rules explicitly allow multiple shifts for one employee on the same date.

There is intentionally **no `work_location_id` column at this stage**.

---

# 19. Important Separation

Do not combine these concepts:

### Shift

Defines:

`WHEN the employee is expected to work`

### Shift Assignment

Defines:

`WHICH employee works WHICH shift on WHICH date`

### Work Location

Defines:

`WHERE the employee works`

For this phase, the third concept is deliberately excluded from the shift-assignment database relationship.

---

# 20. UI Reference Rules

Do not redesign the HRMS visual language.

Reuse the existing design system from:

`Manager Portal.dc.html`

and

`Employee Portal.dc.html`

Maintain:

- Dark teal sidebar
- Teal primary actions
- White cards
- Light gray application background
- Compact enterprise tables
- Rounded 8–14px cards/controls
- Inter typography
- Existing badge/status treatment
- Existing employee avatar treatment
- Existing modal/drawer interaction style
- Existing spacing and border system

The Manager Portal already represents employees with department, shift, status, and location information, while the Employee Portal already exposes the logged-in employee's current shift in the dashboard context. 
---

# 21. Acceptance Criteria

## Manager

- [ ] Manager can open Shift Roster.
- [ ] Manager can select a week.
- [ ] Employees are displayed in rows.
- [ ] Seven days are displayed.
- [ ] Existing assignments are displayed.
- [ ] Manager can click a day/employee cell.
- [ ] Manager can assign a shift.
- [ ] Manager can change an existing shift.
- [ ] Manager cannot create duplicate employee/date assignments.
- [ ] Rotational employees can have different shifts on different dates.
- [ ] Overnight shifts are supported.
- [ ] No work-location ID is required.
- [ ] Existing Manager Portal design language is preserved.

## Employee

- [ ] Employee can see today's assigned shift.
- [ ] Employee can see shift start/end time.
- [ ] Employee can see upcoming assigned shifts.
- [ ] Employee cannot edit the assignment.
- [ ] Today's shift is available to the attendance system.
- [ ] Clock-in/out state remains integrated with the existing Employee Portal.
- [ ] Overnight shifts display correctly.
- [ ] No work-location ID is required.

## Backend

- [ ] Shift definitions are persisted.
- [ ] Shift assignments are persisted.
- [ ] Employee/date uniqueness is enforced.
- [ ] APIs enforce manager/employee authorization.
- [ ] Employee APIs only return the authenticated employee's assignments.
- [ ] Shift assignment data can be used by attendance calculations.
- [ ] Core shift data uses relational PostgreSQL columns, not JSONB.

# 22. Final Implementation Principle

Build this in two connected experiences:

**Manager**

`Shift Roster → Select Employee + Date → Assign Shift → Persist Assignment`

**Employee**

`My Dashboard → Today's Shift → Upcoming Shifts → Attendance uses assigned shift`

Do not add work-location dependency now.

The system should be designed so that **work location can be introduced later without redesigning the shift assignment workflow or breaking existing assignments.**