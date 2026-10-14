# HRMS Shift Assignment APIs + UI Walkthrough Prompt

## 1. Source alignment

This design is based on the existing HRMS Manager Portal and its current Shift Scheduling behavior.

The existing UI already has a **Shift Scheduling** module, a weekly roster, filters for **All / By department / By role**, and an **Assign shift** modal. The current prototype uses these shift types:

- **Morning** — 06:00–14:00
- **General** — 09:00–18:00
- **Afternoon** — 14:00–22:00
- **Night** — 22:00–06:00
- **Off** — Rest day

The current prototype displays a weekly roster with one shift cell per employee per day and opens the assignment modal when a cell is selected. fileciteturn2file1 fileciteturn2file4

The Manager Portal already exposes Shift Scheduling in its navigation and models the roster by employee and day. fileciteturn1file13 fileciteturn2file10

---

# 2. Recommended PostgreSQL data model

Avoid storing the roster as JSONB. Keep shifts and assignments normalized so they are easy to query, constrain, audit, and report.

## 2.1 `shift_definitions`

Stores reusable shift definitions.

```sql
CREATE TABLE shift_definitions (
    id              BIGSERIAL PRIMARY KEY,
    code            VARCHAR(30) NOT NULL UNIQUE,
    name            VARCHAR(80) NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    crosses_midnight BOOLEAN NOT NULL DEFAULT FALSE,
    is_day_off      BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_shift_day_off
        CHECK (
            (is_day_off = TRUE AND code = 'OFF')
            OR is_day_off = FALSE
        ),

    CONSTRAINT chk_shift_time
        CHECK (
            is_day_off = TRUE
            OR start_time IS NOT NULL
        )
);
```

Seed values:

```sql
INSERT INTO shift_definitions
    (code, name, start_time, end_time, crosses_midnight, is_day_off)
VALUES
    ('MORNING',   'Morning',   '06:00', '14:00', FALSE, FALSE),
    ('GENERAL',   'General',   '09:00', '18:00', FALSE, FALSE),
    ('AFTERNOON', 'Afternoon', '14:00', '22:00', FALSE, FALSE),
    ('NIGHT',     'Night',     '22:00', '06:00', TRUE,  FALSE),
    ('OFF',       'Off',       '00:00', '00:00', FALSE, TRUE);
```

The times above match the existing Manager Portal prototype. fileciteturn2file1

---

## 2.2 `employee_shift_assignments`

One normalized row represents one employee's shift for one calendar date.

```sql
CREATE TABLE employee_shift_assignments (
    id                  BIGSERIAL PRIMARY KEY,
    employee_id         BIGINT NOT NULL,
    assignment_date     DATE NOT NULL,
    shift_definition_id  BIGINT NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'ASSIGNED',
    note                VARCHAR(500),
    assigned_by         BIGINT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_assignment_shift
        FOREIGN KEY (shift_definition_id)
        REFERENCES shift_definitions(id),

    CONSTRAINT chk_assignment_status
        CHECK (status IN ('ASSIGNED', 'CANCELLED')),

    CONSTRAINT uq_employee_assignment_date
        UNIQUE (employee_id, assignment_date)
);
```

### Why this structure

- No JSONB roster column.
- Simple lookup by employee/date.
- Simple lookup for a department/week.
- Unique constraint prevents two shifts for the same employee on the same day.
- Foreign key guarantees that the assigned shift exists.
- `assigned_by` supports auditability.
- `status` allows cancellation without deleting history.

If the business later supports multiple shifts in one day, replace the unique constraint with a range/overlap model. For the current UI, one shift per employee per day is the cleaner match.

---

## 2.3 Recommended indexes

```sql
CREATE INDEX idx_shift_assignment_date
    ON employee_shift_assignments (assignment_date);

CREATE INDEX idx_shift_assignment_employee_date
    ON employee_shift_assignments (employee_id, assignment_date);

CREATE INDEX idx_shift_assignment_shift_date
    ON employee_shift_assignments (shift_definition_id, assignment_date);

CREATE INDEX idx_shift_definition_active
    ON shift_definitions (is_active);
```

If employee filtering frequently starts from department, use the existing employee/department relationship and join through the employee table rather than duplicating department data into the assignment table.

---

# 3. API conventions

Base path:

```text
/api/v1
```

Authentication:

```text
Authorization: Bearer <access-token>
```

Roles that should normally be allowed to manage assignments:

- HR Admin
- HR Manager
- Department Head / Manager, subject to department scope

The existing Admin Console permission model already distinguishes View/Create/Edit/Delete/Approve capabilities and includes Attendance permissions, so Shift Scheduling should follow the same authorization approach rather than inventing a separate permission system. fileciteturn1file18

Use normal relational request/response payloads at the API layer. JSON responses are fine; the restriction here is specifically to avoid using JSONB as the primary PostgreSQL storage model.

---

# 4. API endpoints

## 4.1 List shift definitions

### `GET /api/v1/shifts`

Returns active shift definitions for dropdowns, legends, and assignment controls.

Query parameters:

```text
active=true
```

Example response:

```json
{
  "data": [
    {
      "id": 1,
      "code": "MORNING",
      "name": "Morning",
      "startTime": "06:00",
      "endTime": "14:00",
      "crossesMidnight": false,
      "isDayOff": false
    },
    {
      "id": 2,
      "code": "GENERAL",
      "name": "General",
      "startTime": "09:00",
      "endTime": "18:00",
      "crossesMidnight": false,
      "isDayOff": false
    }
  ]
}
```

---

# 5. Get weekly roster

## `GET /api/v1/shift-assignments`

Query parameters:

```text
from=2026-07-06
to=2026-07-12
departmentId=12
roleId=5
employeeId=142
status=ASSIGNED
```

At minimum, `from` and `to` should be required for roster requests.

Recommended response:

```json
{
  "data": [
    {
      "employee": {
        "id": 3,
        "employeeCode": "EMP-0210",
        "name": "Priya Nair",
        "department": "ICU",
        "role": "Head Nurse"
      },
      "assignments": [
        {
          "assignmentId": 501,
          "date": "2026-07-06",
          "shift": {
            "id": 4,
            "code": "NIGHT",
            "name": "Night",
            "startTime": "22:00",
            "endTime": "06:00",
            "crossesMidnight": true,
            "isDayOff": false
          },
          "status": "ASSIGNED"
        },
        {
          "assignmentId": 502,
          "date": "2026-07-07",
          "shift": {
            "id": 4,
            "code": "NIGHT",
            "name": "Night",
            "startTime": "22:00",
            "endTime": "06:00",
            "crossesMidnight": true,
            "isDayOff": false
          },
          "status": "ASSIGNED"
        }
      ]
    }
  ],
  "meta": {
    "from": "2026-07-06",
    "to": "2026-07-12",
    "totalEmployees": 8
  }
}
```

### SQL shape

Do not construct the roster from JSONB. Query relational rows:

```sql
SELECT
    a.id,
    a.assignment_date,
    a.status,
    e.id AS employee_id,
    e.employee_code,
    e.first_name,
    e.last_name,
    sd.id AS shift_id,
    sd.code AS shift_code,
    sd.name AS shift_name,
    sd.start_time,
    sd.end_time,
    sd.crosses_midnight,
    sd.is_day_off
FROM employee_shift_assignments a
JOIN employees e
    ON e.id = a.employee_id
JOIN shift_definitions sd
    ON sd.id = a.shift_definition_id
WHERE a.assignment_date BETWEEN $1 AND $2
  AND a.status = 'ASSIGNED'
ORDER BY e.department_id, e.first_name, a.assignment_date;
```

Apply department/role/employee filters through SQL predicates.

---

# 6. Assign a shift

## `POST /api/v1/shift-assignments`

Request:

```json
{
  "employeeId": 3,
  "assignmentDate": "2026-07-06",
  "shiftDefinitionId": 4,
  "note": "ICU night coverage"
}
```

Response:

```json
{
  "data": {
    "assignmentId": 501,
    "employeeId": 3,
    "assignmentDate": "2026-07-06",
    "shiftDefinitionId": 4,
    "status": "ASSIGNED"
  }
}
```

### Server-side rules

1. Employee must exist.
2. Employee must be active.
3. Shift definition must exist and be active.
4. Assignment date must be valid.
5. Caller must have permission to manage that employee.
6. Existing assignment for the employee/date must either be updated intentionally or rejected.
7. Leave/absence conflicts should be checked if the HRMS policy requires it.
8. Department/manager scope must be checked server-side.
9. Write an audit event.

Recommended conflict response:

```http
409 Conflict
```

```json
{
  "error": {
    "code": "SHIFT_ASSIGNMENT_EXISTS",
    "message": "A shift is already assigned for this employee on this date."
  }
}
```

---

# 7. Change an existing assignment

## `PUT /api/v1/shift-assignments/{assignmentId}`

Request:

```json
{
  "shiftDefinitionId": 2,
  "note": "Changed from Night to General"
}
```

Response:

```json
{
  "data": {
    "assignmentId": 501,
    "employeeId": 3,
    "assignmentDate": "2026-07-06",
    "shiftDefinitionId": 2,
    "status": "ASSIGNED"
  }
}
```

Use `PUT` for a direct replacement of the shift on an existing assignment.

---

# 8. Cancel/unassign

## `DELETE /api/v1/shift-assignments/{assignmentId}`

Prefer a soft cancellation in the service layer:

```sql
UPDATE employee_shift_assignments
SET
    status = 'CANCELLED',
    updated_at = NOW()
WHERE id = $1;
```

Response:

```json
{
  "data": {
    "assignmentId": 501,
    "status": "CANCELLED"
  }
}
```

Do not physically delete assignment history unless there is a deliberate data-retention policy.

---

# 9. Bulk shift assignment

This is useful for the weekly roster UI.

## `POST /api/v1/shift-assignments/bulk`

Request:

```json
{
  "assignments": [
    {
      "employeeId": 3,
      "assignmentDate": "2026-07-06",
      "shiftDefinitionId": 4
    },
    {
      "employeeId": 3,
      "assignmentDate": "2026-07-07",
      "shiftDefinitionId": 4
    },
    {
      "employeeId": 11,
      "assignmentDate": "2026-07-06",
      "shiftDefinitionId": 4
    }
  ]
}
```

Process inside one PostgreSQL transaction.

Recommended behavior:

- Validate every employee.
- Validate every shift.
- Check permissions.
- Check conflicts.
- Insert/update only after validation passes.
- Return per-row results if partial success is intentionally supported.
- Otherwise use all-or-nothing transaction behavior.

For HRMS scheduling, **all-or-nothing is safer for a weekly publish operation**.

---

# 10. Recommended UPSERT behavior

For the single-cell UI, the cleanest backend behavior is:

```sql
INSERT INTO employee_shift_assignments (
    employee_id,
    assignment_date,
    shift_definition_id,
    status,
    note,
    assigned_by
)
VALUES ($1, $2, $3, 'ASSIGNED', $4, $5)
ON CONFLICT (employee_id, assignment_date)
DO UPDATE SET
    shift_definition_id = EXCLUDED.shift_definition_id,
    status = 'ASSIGNED',
    note = EXCLUDED.note,
    assigned_by = EXCLUDED.assigned_by,
    updated_at = NOW()
RETURNING *;
```

This matches the current UI interaction: selecting a different shift in the assignment modal changes the cell's shift. The prototype currently updates the selected employee/day cell immediately. fileciteturn2file12

For production, perform authorization and business-rule validation before this statement.

---

# 11. Audit trail

Create a normal relational audit table instead of putting audit details into JSONB.

```sql
CREATE TABLE shift_assignment_audit (
    id              BIGSERIAL PRIMARY KEY,
    assignment_id   BIGINT,
    employee_id     BIGINT NOT NULL,
    assignment_date DATE NOT NULL,
    old_shift_id    BIGINT,
    new_shift_id    BIGINT,
    action           VARCHAR(30) NOT NULL,
    performed_by    BIGINT NOT NULL,
    reason          VARCHAR(500),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_shift_audit_action
        CHECK (action IN ('ASSIGNED', 'CHANGED', 'CANCELLED'))
);
```

This supports questions such as:

- Who changed Priya Nair's shift?
- What was the previous shift?
- When was it changed?
- Why was it changed?

---

# 12. API error model

Use one consistent error format.

```json
{
  "error": {
    "code": "SHIFT_EMPLOYEE_ON_LEAVE",
    "message": "The employee is on approved leave for this date.",
    "field": "assignmentDate"
  }
}
```

Recommended error codes:

```text
SHIFT_NOT_FOUND
SHIFT_INACTIVE
EMPLOYEE_NOT_FOUND
EMPLOYEE_INACTIVE
SHIFT_ASSIGNMENT_EXISTS
SHIFT_ASSIGNMENT_NOT_FOUND
SHIFT_EMPLOYEE_ON_LEAVE
SHIFT_PERMISSION_DENIED
SHIFT_INVALID_DATE
SHIFT_INVALID_TIME
SHIFT_CONFLICT
VALIDATION_ERROR
```

HTTP mapping:

```text
400 Validation
401 Unauthenticated
403 Permission denied
404 Resource not found
409 Business conflict
422 Business validation
500 Unexpected server error
```

---

# 13. Frontend API flow

## Initial page load

```text
GET /api/v1/shifts?active=true
GET /api/v1/shift-assignments?from=...&to=...
```

The UI builds:

- employee rows
- weekday columns
- shift cells
- shift legend
- department filters
- role filters

The current prototype has exactly this conceptual structure: weekly `weekDays`, employee roster rows, shift cells, filters, and a shift legend. fileciteturn2file1

## User changes department

Call:

```text
GET /api/v1/shift-assignments?from=...&to=...&departmentId=...
```

## User changes role

Call:

```text
GET /api/v1/shift-assignments?from=...&to=...&roleId=...
```

## User clicks a shift cell

Open the existing **Assign shift** modal.

Do not immediately save just because the modal opened.

## User selects a shift

Call:

```text
POST /api/v1/shift-assignments
```

or, if the assignment already exists:

```text
PUT /api/v1/shift-assignments/{assignmentId}
```

## Successful save

1. Close modal.
2. Update the cell.
3. Keep current week/filter.
4. Show a small success toast.
5. Refresh only the affected row/cell if possible.

## Conflict

Keep the modal open and show the backend message directly below the relevant field/action.

---

# 14. UI walkthrough prompt

Use the following prompt with the UI/code-generation tool.

> Build the production Shift Scheduling flow inside the existing NanoHealth HRMS Manager Portal.
>
> Preserve the existing visual language from the Manager Portal: dark teal left sidebar, white top navigation, light gray-green page canvas, Inter typography, compact cards, 9–14px border radii, teal primary actions, subtle borders, and the existing status-color treatment. Do not redesign the overall HRMS shell.
>
> The existing Manager Portal already has a **Shift Scheduling** navigation item. Make it the active module and build the complete functional flow around it. The current prototype uses these shifts:
>
> - Morning — 06:00–14:00
> - General — 09:00–18:00
> - Afternoon — 14:00–22:00
> - Night — 22:00–06:00
> - Off — Rest day
>
> The existing prototype uses a weekly employee roster and opens an **Assign shift** modal when a roster cell is clicked. Preserve that interaction pattern. fileciteturn2file1 fileciteturn2file4
>
> ### Screen 1 — Shift Scheduling overview
>
> Create:
>
> 1. Page heading: **Shift Scheduling**
> 2. Supporting text: show the selected week/date range.
> 3. Week navigation:
>    - Previous week
>    - Current week
>    - Next week
>    - Date range label
> 4. View controls:
>    - All
>    - By department
>    - By role
> 5. Filters:
>    - Department
>    - Role
>    - Employee search
> 6. Shift legend:
>    - Morning
>    - General
>    - Afternoon
>    - Night
>    - Off
> 7. Weekly roster table.
>
> ### Roster table
>
> Use employees as rows and seven days as columns.
>
> Each row should show:
>
> - Avatar/initials
> - Employee name
> - Employee ID
> - Department
> - Role
>
> Each day cell should show:
>
> - Shift name
> - Shift time
> - Compact color treatment
> - Hover affordance
> - Click interaction
>
> Make the grid horizontally scrollable on smaller screens.
>
> Do not store or model the frontend roster as one JSON blob. Treat each employee/date combination as a normal shift assignment returned from the API.
>
> ### Screen 2 — Assign shift modal
>
> When a roster cell is clicked, open a centered modal titled:
>
> **Assign shift**
>
> Subtitle:
>
> `{employee name} · {weekday/date}`
>
> Show five selectable options:
>
> 1. Morning — 06:00–14:00
> 2. General — 09:00–18:00
> 3. Afternoon — 14:00–22:00
> 4. Night — 22:00–06:00
> 5. Off — Rest day
>
> Clearly mark the currently assigned shift.
>
> Add:
>
> - Optional note field
> - Cancel button
> - Save shift button
>
> Disable Save until a valid selection exists.
>
> For an existing assignment, label the primary action **Change shift** instead of **Save shift**.
>
> ### Loading state
>
> When saving:
>
> - Disable controls.
> - Show a compact spinner/loading state.
> - Keep the modal visible.
>
> ### Success state
>
> On success:
>
> - Close the modal.
> - Update only the affected cell.
> - Show toast: **Shift assigned successfully**
> - Keep the current filters and week.
>
> ### Conflict state
>
> If the API returns HTTP 409:
>
> - Keep the modal open.
> - Show an inline warning.
> - Explain that an existing assignment or scheduling conflict was detected.
> - Do not silently overwrite data.
>
> ### Leave conflict
>
> If the backend reports that the employee is on approved leave:
>
> - Show a warning state.
> - Message: **Employee is on approved leave for this date.**
> - Require the manager to explicitly resolve the conflict according to HR policy.
>
> ### Empty state
>
> If no employees match the current filters:
>
> Show:
>
> **No employees found**
>
> with a secondary action:
>
> **Clear filters**
>
> ### API integration
>
> Use these API calls:
>
> `GET /api/v1/shifts?active=true`
>
> `GET /api/v1/shift-assignments?from={date}&to={date}`
>
> Optional filters:
>
> `departmentId`
>
> `roleId`
>
> `employeeId`
>
> Create:
>
> `POST /api/v1/shift-assignments`
>
> Update:
>
> `PUT /api/v1/shift-assignments/{assignmentId}`
>
> Cancel:
>
> `DELETE /api/v1/shift-assignments/{assignmentId}`
>
> Do not introduce JSONB-dependent frontend or backend storage assumptions. PostgreSQL should use normalized relational tables for shift definitions and employee shift assignments.
>
> ### UX requirements
>
> - Preserve the existing Manager Portal shell.
> - Preserve the dark-teal sidebar and teal primary action.
> - Keep the roster dense enough to view a full week without excessive vertical scrolling.
> - Make shift cells visually distinct but not overly saturated.
> - Use accessible focus states.
> - Support keyboard navigation through filters and modal controls.
> - Confirm destructive/unassign actions.
> - Never lose unsaved modal input when an API error occurs.
> - Show server-side validation messages near the relevant control.
> - Use optimistic UI only after basic validation; rollback if the API fails.
>
> ### Responsive behavior
>
> Desktop:
>
> - Full seven-day roster.
> - Fixed employee identity columns where practical.
>
> Tablet:
>
> - Horizontally scrollable roster.
> - Filters collapse into a filter button.
>
> Mobile:
>
> - Replace the seven-column grid with an employee-first daily list.
> - Selecting an employee shows their seven-day schedule.
> - Keep the same Assign shift modal.
>
> ### Important implementation rule
>
> The API is the source of truth. The UI must not permanently mutate a local roster object without persisting through the API.
>
> After a successful assignment, refresh or reconcile the affected assignment from the API so the displayed state matches PostgreSQL.

---

# 15. Suggested service-layer structure

```text
src/
  modules/
    shift/
      shift.controller.ts
      shift.service.ts
      shift.repository.ts
      shift.routes.ts
      shift.validation.ts
      shift.types.ts
```

Responsibilities:

### Controller

- Parse request.
- Authenticate user.
- Call service.
- Map service errors to HTTP responses.

### Service

- Authorization.
- Employee validation.
- Shift validation.
- Leave conflict checks.
- Transaction boundary.
- Assignment + audit creation.

### Repository

Only database access:

```text
findShiftDefinitions()
findRoster()
findAssignment()
insertAssignment()
updateAssignment()
cancelAssignment()
insertAudit()
```

Do not put business rules into SQL controllers.

---

# 16. Transaction for assignment

Recommended flow:

```text
BEGIN

1. Lock/check employee.
2. Verify employee is active.
3. Verify caller can manage employee.
4. Verify shift definition is active.
5. Check leave/absence rules.
6. Read existing assignment.
7. Insert or update assignment.
8. Insert audit row.
9. COMMIT
```

If any business rule fails:

```text
ROLLBACK
```

Return the appropriate 4xx response.

---

# 17. Testing checklist

## API

- [ ] Create assignment for active employee.
- [ ] Change assignment.
- [ ] Cancel assignment.
- [ ] Assign Off.
- [ ] Assign Night shift.
- [ ] Handle overnight shift correctly.
- [ ] Reject inactive employee.
- [ ] Reject inactive shift.
- [ ] Reject unauthorized manager.
- [ ] Detect leave conflict.
- [ ] Detect duplicate assignment.
- [ ] Bulk assignment is transactional.
- [ ] Audit row is created.
- [ ] Week roster returns correct dates.
- [ ] Department filter works.
- [ ] Role filter works.
- [ ] Employee filter works.

## UI

- [ ] Shift Scheduling appears in sidebar.
- [ ] Current week loads from API.
- [ ] Previous/next week works.
- [ ] Department filter reloads roster.
- [ ] Role filter reloads roster.
- [ ] Employee search works.
- [ ] Clicking a cell opens Assign shift modal.
- [ ] Current shift is selected.
- [ ] Selecting a shift saves through API.
- [ ] Cell updates after success.
- [ ] API errors keep modal open.
- [ ] 409 conflicts are visible.
- [ ] Leave conflicts are visible.
- [ ] Off shift displays as rest day.
- [ ] Night shift displays 22:00–06:00.
- [ ] Mobile layout remains usable.

---

# 18. Important design decision

For this HRMS, keep the PostgreSQL model relational:

```text
employees
    |
    +---- employee_shift_assignments ---- shift_definitions
    |
    +---- departments
    |
    +---- roles
```

Do **not** use:

```text
employee.shift_roster JSONB
weekly_roster JSONB
employee_schedule JSONB
```

The roster is a relational projection of assignment rows, not a document.

This will make attendance integration, leave conflict detection, shift reports, payroll calculations, audit history, and future shift-swap workflows substantially easier.
