# Manager Portal — Attendance Dashboard

## Objective

Build the **Attendance Dashboard** inside the existing Manager Portal as a complete full-stack module.

Use the existing `Manager Portal.dc.html` as the primary UI/design reference. Preserve the existing NanoHealth HRMS visual language, navigation, typography, spacing, colors, cards, tables, filters, drawers, and interaction patterns.

The Manager Portal already contains an Attendance module and an attendance analytics foundation. Extend and productionize that flow instead of creating a new unrelated dashboard.

The existing design already uses:

- Manager Portal sidebar with **Attendance** as a module.
- Today attendance snapshot/KPI cards.
- Employee attendance status such as `Present`, `Late`, `On leave`, `Absent`, and `Week off`.
- Employee attendance rows with clock-in, clock-out and worked hours.
- Day / Week / Month attendance analytics.
- Employee attendance analytics popup/drawer.
- Employee search/filter patterns.
- Existing Manager Portal notification and quick-action patterns.

Relevant existing implementation references include the Attendance navigation and today's attendance structures in `Manager Portal.dc.html`. 
---

# 1. Attendance Dashboard Entry

When the manager clicks:

**Sidebar → Attendance**

open the Attendance Dashboard.

Do not create a second Attendance module elsewhere.

The page should use the existing Manager Portal shell:

- Left sidebar.
- Existing top search/header.
- Existing notification area.
- Main content canvas.
- Existing NanoHealth teal/neutral design system.

The Attendance page title should be:

**Attendance**

Subtitle:

**Monitor team attendance, working hours and exceptions**

---

# 2. Dashboard Scope

The dashboard should be manager-scoped.

A manager should only see employees belonging to the manager's permitted team/scope.

Do not expose organization-wide attendance unless the logged-in manager has the appropriate permission.

Backend authorization must enforce this scope. Do not rely only on frontend filtering.

---

# 3. Top Controls

At the top of the Attendance page provide:

### Date selector

Default:

**Today**

Allow:

- Previous day
- Next day
- Date picker
- Today shortcut

The selected date controls the attendance table and daily KPIs.

Do not allow selecting future attendance dates for operational attendance data unless the backend explicitly supports planned attendance.

### Period selector

Provide:

- Day
- Week
- Month

This follows the existing Manager Portal attendance analytics pattern.

The selected period controls analytics cards/charts but should not unexpectedly change the daily employee table.

### Filters

Provide filters for:

- Department
- Team
- Shift
- Attendance status
- Employee
- Location, only if/when work-location support is introduced

For the current implementation, **do not require `work_location_id`**.

### Search

Search by:

- Employee name
- Employee ID
- Mobile number if available

Use server-side search for the production API.

---

# 4. Today KPI Row

Create a compact KPI row at the top.

Recommended cards:

### Present

Number of employees who have a valid attendance record and are present.

### Late

Employees who checked in after their configured shift/grace threshold.

### On Leave

Employees whose approved leave covers the selected date.

### Absent

Employees expected to work but with no valid attendance/punch and no approved leave/week-off condition.

### Yet to Check In

Employees expected to work today who have not checked in yet.

### Attendance %

Attendance percentage for the selected date.

Use the existing Manager Portal terminology where possible. The current prototype already has concepts such as `Present`, `On leave`, `Yet to check-in`, and `Late check-in`.

Do not duplicate KPIs unnecessarily.

---

# 5. Attendance Status Logic

Attendance status must be derived from backend attendance/shift/leave data.

Use a deterministic precedence.

Recommended precedence:

1. Approved leave
2. Week off / holiday
3. Present
4. Late
5. Missing punch / incomplete
6. Absent
7. Yet to check in

The exact business rules should be configurable through the attendance/shift policy layer rather than hardcoded into the UI.

For example:

A person who has approved leave should not appear as `Absent`.

A person who has checked in after the configured late threshold should appear as `Late`.

A person who has checked in but has no clock-out should appear as an incomplete attendance state rather than falsely showing a completed work duration.

---

# 6. Main Attendance Table

Below the KPI section, create the primary employee attendance table.

Columns:

| Column | Purpose |
|---|---|
| Employee | Avatar, name and employee ID |
| Department | Department/team |
| Shift | Assigned shift |
| Status | Present/Late/On Leave/Absent/etc. |
| Clock In | First valid clock-in |
| Clock Out | Final valid clock-out |
| Worked Hours | Calculated duration |
| Late By | Late duration when applicable |
| Attendance | Daily attendance result |
| Actions | Open attendance details |

Use the existing employee row visual style from the Manager Portal.

Status should use the existing semantic treatment:

- Present → green
- Late → amber
- On leave → neutral
- Absent → red
- Week off → neutral

The prototype already defines these attendance status tones.

---

# 7. Table Behaviour

The table must support:

- Pagination.
- Server-side filtering.
- Server-side search.
- Sorting.
- Empty state.
- Loading state.
- Error state.

Default sorting:

**Status priority + employee name**

Optionally allow sorting by:

- Employee
- Clock-in
- Clock-out
- Worked hours
- Late duration

Do not load the entire organization attendance dataset into the browser.

---

# 8. Employee Attendance Drawer

Clicking an attendance row should open the existing employee attendance analytics drawer pattern rather than navigating away from the dashboard.

The existing prototype already provides an employee attendance drawer containing:

- Employee identity.
- Current status.
- Role.
- Department.
- Employee ID.
- Shift.
- Clock-in/out.
- Attendance analytics.
- Day / Week / Month selector.

Retain this interaction model.

The production drawer should show:

### Employee header

- Avatar/initials
- Name
- Employee ID
- Department
- Role
- Shift
- Current attendance status

### Today's attendance

- Clock in
- Clock out
- Worked hours
- Late duration
- Attendance status
- Punch source if available

### Period analytics

Day:

- Worked hours
- Average hours
- Timely days
- Late days
- Attendance %

Week:

- Total hours
- Average hours
- Timely days
- Late days
- Attendance %

Month:

- Total hours
- Average hours
- Timely days
- Late days
- Attendance %
- Worked days

The existing prototype already models these Day/Week/Month values.

---

# 9. Attendance Exceptions

Add an **Exceptions** section to the dashboard.

This should surface actionable attendance problems rather than forcing managers to inspect every employee.

Examples:

- Missing clock-in
- Missing clock-out
- Late arrival
- Early departure
- Incomplete punch
- Unresolved attendance regularization
- Attendance record requiring manager review

Show a count and allow the manager to filter the main table to that exception.

---

# 10. Regularization Integration

Attendance Dashboard should integrate with the existing regularization workflow.

Do not build an unrelated regularization system inside the dashboard.

If an employee has a pending regularization request:

Show:

**Regularization pending**

with an action:

**Review**

Clicking Review should open the existing regularization approval flow.

The employee portal already contains an attendance regularization concept for missed punches, including date, punch type, reason and status.

The manager dashboard should therefore consume the corresponding manager-side request rather than modifying attendance directly.

---

# 11. Clock/Punch Data Model

The dashboard should not calculate attendance from frontend timestamps.

Attendance must be derived from persisted punch records.

At minimum support:

- Employee
- Attendance date
- Clock-in timestamp
- Clock-out timestamp
- Source
- Status
- Worked duration
- Late duration
- Early departure duration
- Regularization reference where applicable

Potential punch sources:

- Employee portal clock-in/out
- Biometric device
- Attendance integration
- Manual/approved regularization

The Admin Console already models attendance integrations such as biometric attendance devices, so the architecture should allow attendance records to originate from integrated devices.

---

# 12. Backend API Design

Build APIs around attendance records rather than returning dashboard-specific hardcoded objects.

Recommended endpoints:

### Dashboard summary

`GET /api/manager/attendance/summary`

Parameters:

- `date`
- `department_id`
- `team_id`
- `shift_id`

Returns:

- present_count
- late_count
- on_leave_count
- absent_count
- yet_to_checkin_count
- attendance_percentage

### Attendance list

`GET /api/manager/attendance`

Parameters:

- `date`
- `page`
- `limit`
- `search`
- `department_id`
- `team_id`
- `shift_id`
- `status`
- `sort`
- `direction`

### Employee attendance analytics

`GET /api/manager/attendance/employees/:employeeId`

Parameters:

- `date`
- `period`

Return:

- daily attendance
- total hours
- average hours
- timely count
- late count
- attendance percentage
- shift information

### Exceptions

`GET /api/manager/attendance/exceptions`

Parameters:

- `date`
- `type`
- `department_id`
- `shift_id`
- pagination/search parameters

### Regularization queue

Use the existing regularization API/module.

Do not duplicate regularization records.

---

# 13. Database Rules

Use the existing PostgreSQL HRMS schema.

Do not introduce JSONB for ordinary attendance attributes.

Prefer relational columns and foreign keys.

Attendance should reference:

- employee
- shift/shift assignment where applicable
- attendance date
- punch records
- regularization record where applicable

Do not introduce `work_location_id` as a required dependency at this stage because the current project is intentionally being developed without work-location support.

Use timestamps for punch events and derive the attendance date using the organization's configured timezone.

---

# 14. Attendance Calculation

Do not calculate attendance percentage using arbitrary frontend formulas.

Backend should calculate based on:

- Expected working days
- Approved leave
- Week offs
- Holidays
- Valid attendance records

For daily dashboard:

`attendance % = employees considered present / employees expected to work`

Exclude:

- Approved leave
- Week off
- Holiday

from the denominator according to the configured policy.

For monthly analytics:

calculate against the employee's actual expected working days for that month.

---

# 15. Shift Awareness

Attendance calculations must respect the employee's assigned shift.

This is particularly important for shifts crossing midnight.

Example:

Night shift:

**21:00 → 06:00**

The clock-out at 06:00 belongs to the same attendance work session even though it occurs on the following calendar date.

Do not naïvely compare timestamps using calendar dates only.

Use the assigned shift's business-day boundary.

The existing Manager Portal already displays shift information alongside attendance analytics.

---

# 16. Late Calculation

Late status must come from:

- Shift start time
- Grace period
- Actual first valid punch

Example:

Shift start: 09:00

Grace period: 10 minutes

Clock-in: 09:07

Result:

**Present**

Clock-in: 09:18

Result:

**Late · 8m**

Do not hardcode these values in the UI.

---

# 17. Worked Hours

Worked hours should be calculated from valid punch pairs.

For a normal day:

`clock_out - clock_in`

For multiple punch sessions:

sum valid work intervals according to the attendance policy.

Do not simply use the difference between the earliest and latest timestamps if break punches are supported.

If the employee is still clocked in:

display the live/ongoing duration only where appropriate.

If clock-out is missing:

show:

**Incomplete**

rather than presenting a misleading completed duration.

---

# 18. Charts / Analytics

The dashboard should contain a lightweight analytics section below the employee table or alongside it depending on screen width.

Provide:

### Attendance trend

Day/Week/Month selectable trend.

### Status distribution

Present / Late / Absent / Leave.

### Working hours

Average worked hours for the selected period.

Do not overbuild this into a BI dashboard.

The manager's primary job is monitoring today's attendance and exceptions.

The existing Manager Portal already has Day/Week/Month attendance analytics with metrics such as timely count, late count, total hours, average hours, attendance percentage and punctuality. Reuse this conceptual model.

---

# 19. Export

Provide:

**Export attendance**

Export should respect the current:

- Date
- Period
- Department
- Team
- Shift
- Status
- Search

filters.

Export CSV initially.

The backend should generate the export rather than assembling large datasets in the browser.

---

# 20. Permissions

Attendance dashboard access should be permission-based.

Example permissions:

- `attendance.view`
- `attendance.view_team`
- `attendance.view_all`
- `attendance.regularization.review`
- `attendance.export`

A manager with team-level access should only see their permitted employees.

---

# 21. Audit

Record important manager actions:

- Attendance viewed
- Regularization reviewed
- Attendance correction approved/rejected
- Attendance export generated

Use the project's existing audit-log approach.

Do not allow silent modification of attendance records.

---

# 22. Frontend State

Implement real state instead of prototype constants.

Required state:

- selected date
- selected period
- filters
- search
- pagination
- sorting
- summary loading/error
- attendance list loading/error
- selected employee
- employee drawer open/closed
- employee analytics period
- exceptions
- regularization state
- export state

Use API-driven state.

Remove prototype-only hardcoded attendance datasets such as the current `ATT_TODAY` and `ATT_BYPERIOD` objects when connecting the production API. Those existing structures should be treated as UI/reference data only. 
---

# 23. Loading / Empty / Error States

Implement proper states.

### Loading

Show skeleton KPI cards and table rows.

### No employees

Show:

**No employees found**

### No attendance

Show:

**No attendance records for this date**

### Filtered empty

Show:

**No employees match your filters**

### API failure

Show:

**Attendance data could not be loaded**

with:

**Retry**

Do not display zero values as though they were real data when the API has failed.

---

# 24. Responsive Behaviour

Desktop-first because this is the Manager Portal.

At smaller widths:

- KPI cards wrap.
- Filters wrap.
- Table becomes horizontally scrollable.
- Employee drawer becomes full-width.
- Analytics cards stack.

Do not redesign the Manager Portal into a mobile application.

---

# 25. UI Consistency

Follow the exact visual language already present in `Manager Portal.dc.html`:

- Inter typography.
- NanoHealth dark teal sidebar.
- Teal active navigation.
- White cards.
- Light grey canvas.
- Subtle borders.
- Rounded 9–14px cards/buttons.
- Green success status.
- Amber warning status.
- Red exception status.
- Compact enterprise HRMS density.

Do not introduce a different color system, component library aesthetic, or dashboard style.

The existing Manager Portal uses this design system consistently across Dashboard, Directory, Leave, Payroll, Expenses and Attendance. 

---

# 26. Important Separation of Responsibilities

Attendance Dashboard is for:

- Monitoring
- Filtering
- Analytics
- Employee attendance inspection
- Exception visibility
- Regularization review entry
- Reporting/export

It is **not** responsible for:

- Creating shifts
- Assigning shifts
- Creating leave policies
- Assigning leave balances
- Creating employees
- Creating work locations
- Configuring biometric devices

Those remain separate modules.

---

# 27. End-to-End Flow

Implement the following flow:

1. Manager logs into Manager Portal.
2. Manager clicks **Attendance**.
3. Backend identifies manager's permitted employee scope.
4. Dashboard loads today's attendance summary.
5. Dashboard loads today's employee attendance records.
6. Manager changes date.
7. KPI summary refreshes.
8. Attendance table refreshes.
9. Manager filters by department/shift/status.
10. Backend returns filtered attendance.
11. Manager clicks an employee.
12. Attendance drawer opens.
13. Drawer loads employee attendance analytics.
14. Manager switches Day / Week / Month.
15. Analytics refreshes.
16. If an exception exists, manager can open the relevant action.
17. If a regularization request exists, manager can review it through the regularization flow.
18. Manager can export the currently filtered attendance dataset.

---

# 28. Acceptance Criteria

The module is complete only when:

- [ ] Attendance exists as a first-class Manager Portal module.
- [ ] Manager scope is enforced server-side.
- [ ] Today's KPIs are API-driven.
- [ ] Attendance table is API-driven.
- [ ] Date selection works.
- [ ] Day/Week/Month analytics work.
- [ ] Department/team/shift/status filters work.
- [ ] Employee search works.
- [ ] Pagination works.
- [ ] Sorting works.
- [ ] Employee attendance drawer works.
- [ ] Daily attendance details are correct.
- [ ] Weekly analytics are correct.
- [ ] Monthly analytics are correct.
- [ ] Late calculation uses shift/grace rules.
- [ ] Night shifts are handled correctly.
- [ ] Missing punches are represented correctly.
- [ ] Leave/week-off/holiday employees are not incorrectly marked absent.
- [ ] Attendance exceptions are visible.
- [ ] Regularization integrates with the existing workflow.
- [ ] Export respects active filters.
- [ ] Attendance actions are audited.
- [ ] Loading, empty and error states exist.
- [ ] No JSONB is introduced for normal attendance attributes.
- [ ] `work_location_id` is not required.
- [ ] Existing Manager Portal UI/design patterns are preserved.
- [ ] Prototype hardcoded attendance data is replaced by real PostgreSQL-backed APIs.

# Primary UI Reference

Use:

**`Manager Portal.dc.html`**

as the primary design and interaction reference.

Use:

**`Employee Portal.dc.html`**

only for employee-side attendance/clock-in/clock-out and regularization behaviour. The employee portal already contains clock state and regularization concepts.

Use:

**`Admin Console.dc.html`**

as supporting reference for attendance integrations and the broader HRMS architecture.

Do not copy the prototype's mock data into production logic. Preserve its UX patterns while replacing the data layer with the actual PostgreSQL HRMS schema and APIs.