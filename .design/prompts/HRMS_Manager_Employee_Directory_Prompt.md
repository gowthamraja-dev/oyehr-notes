So we So, I I I I Okay, I didn't know, I ID in place, you see, and the department is in the Now task complete, say, I want to have a ticket. My team, my team, what I want to do I What I I think the answer I Who's I I think it's about the The the grade is a C D P zero grade.# HRMS Manager Portal — Employee Directory + Directory Home Page
## Full-stack implementation prompt

### 1. Objective

Implement the **Employee Directory** module in the **Manager Portal**, including:

1. Employee Directory home/list page.
2. Employee search.
3. Employee filters.
4. Employee list/table.
5. Employee quick-view drawer.
6. Full employee profile view.
7. Add Employee flow.
8. Directory navigation and breadcrumbs.
9. Backend APIs and PostgreSQL persistence.
10. Proper loading, empty, validation and error states.

The implementation must follow the existing HRMS design language and must use the provided Manager Portal design as the primary UI reference.

---

## 2. Mandatory UI reference

Use this uploaded design file as the **primary visual and interaction reference**:

- `Manager Portal.dc.html`

Relevant existing design characteristics to preserve:

- NanoHealth HRMS Console shell.
- 248px dark-teal sidebar.
- Inter typography.
- Teal `#093D3C / #0E5E5C / #14716F` palette.
- Light `#F4F6F5` application canvas.
- White cards with subtle borders/shadows.
- Existing top search bar.
- Existing sidebar module named **Employee Directory**.
- Existing breadcrumb pattern:
  `Dashboard > Employee Directory > Employee/Profile`
- Existing directory list layout and employee profile navigation.
- Existing responsive behavior and compact enterprise-HRMS visual density.

Do **not** redesign the application shell. Extend the existing Manager Portal structure.

The Employee Portal design may be used only as a secondary reference for employee-facing terminology/profile concepts. The Manager Portal remains the source of truth for manager-side UI.

---

## 3. Existing design intent to preserve

The current Manager Portal already establishes Employee Directory as the foundation for other HRMS modules. The sidebar includes:

- Dashboard
- Employee Directory
- Attendance
- Leave
- Payroll
- Expenses
- Recruitment
- Onboarding
- Shift Scheduling
- Reports & Analytics

The Manager Portal design explicitly describes the Employee Directory as the foundation whose records, roles and organization structure are reused by other modules.

The directory already has:

- `Employee Directory` page title.
- Employee count summary.
- Department count summary.
- Directory tabs.
- Search by ID/name/mobile from the top bar.
- Filter action.
- Add employee action.
- Employee table.
- Employee quick-view drawer.
- Full profile navigation.

Preserve this structure rather than introducing a new directory UX.

---

# 4. Directory home page

Route/state example:

`/manager/employees`

or the project's existing Manager Portal routing convention.

### Header

Show:

- Page title: **Employee Directory**
- Supporting text such as:
  `812 employees across 14 departments`
  but make the values API-driven.
- `Export` secondary action.
- `Add employee` primary action.

Do not hard-code employee counts.

### Directory tabs

The existing design contains directory tabs. Preserve the tab architecture and make the selected tab stateful.

At minimum support:

- **Employees**
- **Headcount**
- **Role**
- **Organization**

If the existing implementation already defines these tabs, wire them to real data rather than replacing the UI.

### Employees tab

The default tab should be the employee list.

Provide:

- Search.
- Filters.
- Employee table.
- Pagination.
- Sortable columns where appropriate.
- Row click / quick-view interaction.
- Empty state.
- Loading state.
- Error state.

---

# 5. Employee search

The existing Manager Portal search behavior searches across:

- Employee name
- Employee ID
- Role/designation
- Department

The top search also supports directory navigation.

Implement server-side search for production.

Search should be debounced.

Suggested API:

`GET /api/manager/employees?search=<query>`

The API should safely search relevant fields and return paginated results.

Do not fetch the entire employee table and filter it only in the browser.

---

# 6. Employee filters

The current design already has a filter drawer/modal with three logical sections:

### Demographic

Reserve this section for demographic filters supported by the schema.

### Employment

Support filters such as:

- Department
- Employment status
- Reporting manager
- Joining-date range where supported

### Contact

Support contact-related filters only when corresponding data exists in the database.

Do not invent fields merely because they appear in a mockup.

The existing design has:

- `All`
- `Active`
- `On Leave`
- `Inactive`

status concepts.

These must map to actual persisted employment/attendance/leave state rather than being arbitrary UI-only values.

### Filter behavior

Actions:

- Apply
- Reset
- Close

When filters are applied:

- Update URL/query state where routing supports it.
- Refresh the employee list.
- Preserve search/filter state during pagination.
- Do not lose filters when opening and closing an employee drawer.

---

# 7. Employee table

Use the existing Manager Portal table visual style.

Recommended columns:

| Column | Purpose |
|---|---|
| Employee | Avatar/initials, name, employee ID |
| Designation | Current role/designation |
| Department | Department |
| Reporting Manager | Reporting relationship |
| Joining Date | Employment start date |
| Status | Active / On Leave / Inactive |
| Actions | View / contextual actions |

Do not add salary, bank, PAN, Aadhaar or other sensitive information to the directory table.

The table should be optimized for manager scanning.

### Row behavior

Clicking an employee opens the existing quick-view drawer.

The row should not navigate away immediately unless the existing design specifically uses full-page navigation.

---

# 8. Employee quick-view drawer

Use the existing Manager Portal drawer pattern.

The drawer should show a compact summary:

- Employee avatar/initials.
- Full name.
- Employee ID.
- Designation.
- Department.
- Employment status.
- Joining date.
- Reporting manager.

Then provide quick actions:

- **View full profile**
- **View attendance**
- **View leave details**

These actions already exist in the design and should be wired to the relevant module/profile state.

Do not duplicate the entire employee profile inside the drawer.

---

# 9. Full employee profile

Route/state example:

`/manager/employees/:employeeId`

The existing Manager Portal uses breadcrumb navigation:

`Dashboard > Employee Directory > Employee Name`

Preserve this pattern.

### Profile header

Show:

- Avatar/initials.
- Employee name.
- Employee ID.
- Designation.
- Department.
- Employment status.
- Joining date.
- Reporting manager.

### Profile tabs

The existing Manager Portal already defines:

- **Overview**
- **Attendance**
- **Leave**
- **Documents**

Preserve these tabs.

### Overview

Show grouped information supported by the backend, such as:

- Personal details.
- Contact details.
- Job details.
- Reporting information.

Sensitive fields should be permission-controlled.

### Attendance

Do not build a separate attendance data model here.

Reuse the Attendance module's employee-level API/data.

The existing design supports per-employee attendance analytics for:

- Day
- Week
- Month

Keep this as a read-only employee profile view.

### Leave

Reuse leave data.

Show the employee's leave requests/details relevant to the manager's permissions.

Do not create duplicate leave records.

### Documents

Show employee documents only when the existing schema and permissions support them.

Do not expose sensitive documents simply because they exist in storage.

---

# 10. Add Employee flow

The existing Manager Portal has an `Add employee` action and an `add` view.

Implement the complete flow.

### Minimum employee creation information

Use the database schema as the source of truth.

At minimum, the creation flow needs to establish:

- Employee ID.
- User/login identity when applicable.
- Corporate entity.
- Reporting manager.
- Joining date.
- Employment status.

Additional employee information should be added only where supported by existing HRMS tables.

### Validation

Validate:

- Required fields.
- Employee ID uniqueness within the appropriate tenant/company scope.
- Valid reporting manager.
- Valid joining date.
- Valid employment status.
- Valid user association if required.

Do not silently create duplicate login identities.

### Save behavior

On successful creation:

1. Persist the employee.
2. Return the created employee.
3. Refresh/invalidate directory queries.
4. Close the form.
5. Show a success message.
6. Optionally open the newly created employee profile.

On failure:

- Keep the entered values.
- Display field-level errors where possible.
- Display a useful server error for unexpected failures.

---

# 11. PostgreSQL / existing schema alignment

The supplied `HRMS.sql` defines `employee_masters` as:

- `id`
- `emp_id`
- `corp_master_id`
- `user_id`
- `reporting_manager_id`
- `joining_date`
- `employment_status`

The schema also defines:

- `users`
- `corp_masters`
- `status_masters`
- `address_details`
- `image_details`
- `work_location_masters`

`employee_masters.reporting_manager_id` references `employee_masters.id` and is explicitly described as part of the approval chain.

Use the existing tables instead of creating a parallel `employees` table.

Do not duplicate employee master data into a new JSON/JSONB document.

Prefer normalized relational tables and joins.

The current project decision is to **not require `work_location_id` for this implementation**. Do not make Employee Directory creation depend on work location assignment.

Work location remains available in the existing schema for future use.

---

# 12. Tenant/data isolation

The schema identifies:

- `care_delivery_program_masters` as the tenant boundary.
- `corp_masters` as the corporate/employer entity.
- `employee_masters` reaches the tenant through `corp_master_id`.

Every directory API must enforce the authenticated manager's tenant/company scope.

Never accept a client-supplied employee/corporate scope and trust it blindly.

Example principle:

`authenticated user -> manager permissions -> allowed corp -> employee_masters`

Do not allow a manager to retrieve employees belonging to another corporate entity.

---

# 13. Suggested backend API contract

### List employees

`GET /api/manager/employees`

Query parameters:

- `search`
- `department_id`
- `employment_status`
- `reporting_manager_id`
- `joining_date_from`
- `joining_date_to`
- `page`
- `page_size`
- `sort_by`
- `sort_order`

Response:

```json
{
  "data": [],
  "pagination": {
    "page": 1,
    "page_size": 25,
    "total": 0,
    "total_pages": 0
  }
}
```

Use normal relational response structures. JSON is acceptable at the API boundary; do not introduce JSONB database storage for employee directory records.

### Get employee

`GET /api/manager/employees/:employeeId`

Return:

- employee master information.
- user identity information allowed by permission.
- reporting manager.
- department/org information where available.
- profile-related information from existing normalized tables.

### Create employee

`POST /api/manager/employees`

Payload should contain only fields supported by the schema.

### Update employee

`PATCH /api/manager/employees/:employeeId`

Support only fields the manager is authorized to edit.

### Employee attendance summary

`GET /api/manager/employees/:employeeId/attendance`

### Employee leave summary

`GET /api/manager/employees/:employeeId/leave`

### Employee documents

`GET /api/manager/employees/:employeeId/documents`

Only expose this endpoint if the existing document model supports it.

### Directory metadata

Provide API(s) for:

- Departments.
- Employment status options.
- Reporting managers.
- Headcount aggregates.
- Role aggregates.
- Organization aggregates.

Avoid hard-coded filter options when those values are database-driven.

---

# 14. Headcount tab

Implement the existing Headcount directory concept as a read-oriented view.

Show:

- Total employees.
- Headcount by department.
- Active headcount.
- Inactive/on-leave counts where supported.
- Department percentage/share.

Use real employee data.

Do not use the mock value `812` except as demo/seed data.

---

# 15. Role tab

Implement the existing Role directory concept as a read-oriented aggregation.

Show:

- Role/designation.
- Employee count.
- Active count where useful.
- Open/vacant information only if it is backed by recruitment/position data.

Do not infer vacancies from employee counts.

---

# 16. Organization tab

Implement the existing organization view.

Show the organization structure available to the manager.

Use:

- Reporting manager relationships.
- Department relationships.
- Corporate scope.

Provide the existing design's full/dept viewing behavior where applicable.

Do not introduce a second organizational hierarchy.

---

# 17. Permissions

Employee Directory must be permission-aware.

At minimum distinguish:

- View employee.
- Create employee.
- Edit employee.
- View attendance.
- View leave.
- View documents.

The Manager Portal's UI should hide or disable actions the current manager cannot perform.

The backend must enforce the same permissions independently.

Never rely on frontend visibility for authorization.

---

# 18. State management

Preserve the existing Manager Portal state concepts where possible:

- `view`
- `selectedId`
- `profileTab`
- `drawerOpen`
- `filterOpen`
- `filterTab`
- `query`
- `dept`
- `status`

If the production application uses a router/store instead, map these concepts to the project's architecture rather than duplicating state.

---

# 19. Loading / empty / error states

Implement all three.

### Loading

Use skeleton rows/cards consistent with the existing visual system.

### Empty

Examples:

- `No employees found`
- `No employees match these filters`
- `No employees in this department`

Provide:

- Clear message.
- Reset filters action where applicable.
- Add employee action where appropriate.

### Error

Show a compact error card/toast with:

- What failed.
- Retry action.

Do not expose raw SQL/database errors.

---

# 20. Pagination and performance

Employee Directory is expected to scale beyond the demo dataset.

Implement:

- Server-side pagination.
- Server-side filtering.
- Server-side search.
- Indexed lookup fields.
- Reasonable page sizes such as 25/50/100.
- Avoid N+1 queries for department/reporting-manager information.

Do not load every employee on initial page load.

---

# 21. Security and privacy

Employee Directory contains sensitive HR data.

Rules:

- Enforce authentication.
- Enforce manager authorization.
- Enforce tenant/company isolation.
- Never expose passwords.
- Never expose raw authentication secrets.
- Mask sensitive financial/identity information unless explicitly authorized.
- Do not put sensitive employee data into logs.
- Validate all IDs server-side.
- Parameterize all SQL queries.
- Do not trust client-provided `corp_master_id`.

---

# 22. UI interaction walkthrough

### Flow A — Open directory

1. Manager clicks **Employee Directory** in sidebar.
2. Directory page opens.
3. Employees tab is active.
4. API loads paginated employees.
5. Count/header metadata is loaded.
6. Employee table renders.

### Flow B — Search

1. Manager enters employee name/ID/role/department.
2. Search is debounced.
3. API receives query.
4. Table updates.
5. Search remains active while navigating pagination.

### Flow C — Filter

1. Manager clicks filter.
2. Filter panel opens.
3. Manager chooses department/status/etc.
4. Manager clicks Apply.
5. API request uses filters.
6. Results update.
7. Active filter state remains visible.

### Flow D — Quick view

1. Manager clicks employee row.
2. Drawer opens.
3. Employee summary loads.
4. Manager can:
   - View full profile.
   - View attendance.
   - View leave.

### Flow E — Full profile

1. Manager clicks View full profile.
2. Drawer closes.
3. Profile page opens.
4. Breadcrumb becomes:
   `Dashboard > Employee Directory > Employee Name`
5. Overview is selected by default.

### Flow F — Add employee

1. Manager clicks Add employee.
2. Add employee form opens.
3. Required fields are validated.
4. API creates employee.
5. Directory cache/list refreshes.
6. Success feedback appears.
7. User returns to directory or opens created profile.

---

# 23. Frontend implementation rules

Use the existing Manager Portal design rather than introducing a different component library or visual language.

Preserve:

- Colors.
- Typography.
- Spacing.
- Border radius.
- Button hierarchy.
- Sidebar.
- Top bar.
- Breadcrumb.
- Table density.
- Drawer pattern.
- Status badges.
- Toast/feedback pattern.

Make the directory responsive without breaking the desktop HRMS workflow.

On smaller screens:

- Table may become a card/list presentation.
- Filters can become a full-screen drawer.
- Employee profile should remain usable.
- Do not remove essential actions.

---

# 24. Backend implementation rules

Use the project's existing backend framework and conventions.

Do not create a second API architecture.

For PostgreSQL:

- Use normalized relational queries.
- Use joins instead of duplicating employee attributes.
- Avoid JSONB for core employee master data.
- Use transactions for employee creation when multiple related records are created.
- Return consistent API error structures.
- Add appropriate indexes only after checking existing schema/indexes.

Potential useful indexes should be evaluated for:

- `employee_masters.emp_id`
- `employee_masters.corp_master_id`
- `employee_masters.reporting_manager_id`
- `employee_masters.employment_status`
- `employee_masters.joining_date`

Do not blindly add duplicate indexes.

---

# 25. Definition of Done

The module is complete when:

- [ ] Employee Directory is accessible from Manager Portal sidebar.
- [ ] Existing Manager Portal shell is preserved.
- [ ] Employees tab works with real API data.
- [ ] Search works server-side.
- [ ] Filters work server-side.
- [ ] Pagination works.
- [ ] Employee count is API-driven.
- [ ] Employee rows open the quick-view drawer.
- [ ] Full employee profile works.
- [ ] Overview tab works.
- [ ] Attendance tab uses attendance data.
- [ ] Leave tab uses leave data.
- [ ] Documents tab respects available data and permissions.
- [ ] Add employee works end-to-end.
- [ ] Employee ID uniqueness is validated.
- [ ] Reporting manager relationship is supported.
- [ ] Tenant/company isolation is enforced.
- [ ] Manager permissions are enforced on both frontend and backend.
- [ ] Headcount tab is functional.
- [ ] Role tab is functional.
- [ ] Organization tab is functional.
- [ ] Loading states exist.
- [ ] Empty states exist.
- [ ] Error states exist.
- [ ] No hard-coded production employee counts remain.
- [ ] No parallel employee table is created.
- [ ] No unnecessary JSONB employee storage is introduced.
- [ ] Work location is not required for this phase.
- [ ] Existing design language is preserved.

---

## 26. Primary reference files

### UI
**Primary:** `Manager Portal.dc.html`

Relevant existing implementation references include the Manager Portal's Employee Directory list, employee drawer, profile tabs, search/filter state, and employee actions. fileciteturn2file2 fileciteturn2file5 fileciteturn2file18

### Secondary UI terminology/reference
`Employee Portal.dc.html`

The employee-facing profile structure contains concepts such as personal details, contact, job details, employee ID, designation, department, joining date and reporting relationship. fileciteturn2file14

### Database
`HRMS.sql`

The employee master is represented by `employee_masters`, with `corp_master_id`, `user_id`, `reporting_manager_id`, `joining_date`, and `employment_status`. `reporting_manager_id` references `employee_masters.id`. fileciteturn2file5

---

## Final implementation instruction

Build this as a **production-ready Employee Directory module**, not a static mock.

Start from the existing Manager Portal UI and progressively replace demo/static employee data with real PostgreSQL-backed APIs.

Do not redesign unrelated Manager Portal modules.

Do not implement work-location assignment in this phase.

The goal of this phase is:

**Manager Portal → Employee Directory Home → Search/Filter → Employee List → Quick View → Full Profile → Add Employee**

with a clean foundation that future Attendance, Leave, Payroll, Onboarding and Shift Scheduling modules can reuse.
