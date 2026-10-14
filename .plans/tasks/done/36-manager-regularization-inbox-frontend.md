---
task: 36
title: Manager Regularization Inbox screen
status: done
depends_on: [33]
---

# 36 — Manager Regularization Inbox frontend

## Discussion

`docs/leave-and-attendance/shared/implementation-structure.md §7.3` lists
`hrManager/RegularizationInbox.tsx` as a not-yet-built file with **"no mockup — built to the
minimum spec in `../attendance/manager-approvals.md §3`."** That section is this task's design
spec in full (columns, filters, actions, the recorded-vs-requested detail layout). There is no
existing mock file to replace — this is new UI, not a rewire like tasks 34-35.

Follow the visual language already established in this same dashboard's `Attendance.tsx` (cards,
table styling, badge treatment, `AttendanceSkeleton`-style shimmer) and `ShiftScheduling.tsx`
(nav wiring pattern, since it's the most recently added real nav item in `hrManager`) rather than
inventing a new visual style for one screen.

## Files

### New

- `frontend/src/dashboards/hrManager/RegularizationInbox.tsx`:

  ```tsx
  export function RegularizationInboxSkeleton() { /* shimmer, mirrors AttendanceSkeleton's shape */ }

  export function RegularizationInbox({ me }: { me: Me }) {
    // fetch listManagerRequests() on mount + on filter change
    // Columns: Employee · Type · Date · Requested times · Reason · Status · Action
    //   (manager-approvals.md §3 — Type is always "Regularization" in this task set, still
    //   render the column since the schema/API already carry it for future request types)
    // Filters: status segmented control (All/Pending/Approved/Rejected/Cancelled),
    //   request_type (fixed to Regularization for now — render the filter control anyway,
    //   disabled or single-valued, so adding OnDuty/WFH later is a data change, not a UI one)
    // Row actions: "Details" opens a detail drawer/modal; Pending rows additionally show
    //   inline "Approve"/"Reject" buttons for a fast path without opening details
  }
  ```

  Detail view (opened via "Details" or via the inline Approve action needing a remarks field):
  a two-column comparison exactly per `manager-approvals.md §3`'s example:

  ```
                Recorded              Requested
  Clock in      —                     09:00
  Clock out     18:04                 18:04
  Status        Present (0.00 payable) Present (1.00 payable)
  ```

  plus the employee block (Name, Employee ID, Department, Shift) and the reason/note/attachment
  the employee submitted. Approve requires an optional remarks field; Reject requires a non-blank
  remarks field (client-side validation mirroring the backend's required-reason rule) — disable
  the Reject submit button until non-empty.

### Edited

- `frontend/src/lib/api.ts` — add under `// ── Attendance: manager regularization inbox ──`:

  ```ts
  export type ManagerRequestRow = RegularizationRequest & {
    employee: { employee_master_id: number; emp_id: string | null; name: string; department: string | null; shift_name: string | null };
  };

  export async function listManagerRequests(status?: string): Promise<ManagerRequestRow[]> {
    // GET /api/v1/attendance/requests?status=
  }

  export type AttendanceSnapshot = { clock_in: string | null; clock_out: string | null; status: string | null; payable_day_fraction: number };

  export async function getManagerRequestDetail(id: number): Promise<ManagerRequestRow & { recorded: AttendanceSnapshot; requested: AttendanceSnapshot }> {
    // GET /api/v1/attendance/requests/{id}
  }

  export async function approveRequest(id: number, approver_remarks?: string): Promise<{ id: number; status: "Approved" }> {
    // POST /api/v1/attendance/requests/{id}/approve
  }

  export async function rejectRequest(id: number, approver_remarks: string): Promise<{ id: number; status: "Rejected" }> {
    // POST /api/v1/attendance/requests/{id}/reject
  }
  ```

- `frontend/src/dashboards/hrManager/index.tsx` — add a `regularizations` nav item per
  `manager-approvals.md §2.3`'s table (view key `regularizations`), rendering
  `<RegularizationInbox me={me} />` and `<RegularizationInboxSkeleton />` while loading — follow
  exactly how the existing `attendance`/`roster` nav items are wired in this file (same `NAV`
  array entry shape, same `views` map entry shape); this file was last touched by task 12/16, so
  re-read its current `NAV`/`views` structure before editing rather than assuming task 16's shape
  is unchanged.

## Acceptance criteria

- [ ] A manager sees a Regularization Inbox nav item listing only their direct reports' pending
      (and, via filter, all-status) requests.
- [ ] A request from a non-report employee never appears, and a direct API probe for its detail
      (if reachable through devtools) returns 403 — the UI doesn't rely on hiding it, the backend
      enforces it (task 33).
- [ ] Detail view shows the recorded-vs-requested comparison exactly per the spec table above.
- [ ] Approve and Reject both work end-to-end; Reject is blocked client-side until a reason is
      entered, matching the backend's required-reason validation.
- [ ] After approving, the request disappears from the Pending filter and the (manually
      cross-checked) employee's daily log for that date reflects the corrected punch.
- [ ] Loading state is a shimmer skeleton matching this dashboard's existing pattern — no spinner.
- [ ] Manually verified in the browser: as a manager, approve one request and reject another,
      confirm both leave the Pending queue and the employee's own My Attendance regularization
      list (task 35) reflects the new status.

Completed: 2026-08-18
