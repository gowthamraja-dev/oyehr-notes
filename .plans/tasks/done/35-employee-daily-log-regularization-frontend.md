---
task: 35
title: Employee daily log, regularization history, and Request Regularization modal
status: done
depends_on: [32, 34]
---

# 35 — Employee daily log + regularization request frontend

## Discussion

Replaces `MyAttendance.tsx`'s two remaining mock datasets — `DAILY_LOG` and
`REGULARIZATION_REQUESTS` (both hardcoded arrays at the top of the file) — with real data, and
builds the "Request regularization" modal the existing button (line ~137-142, currently with no
`onClick`) doesn't yet open. Spec: `docs/leave-and-attendance/attendance/employee-self-service.md
§2.3-2.5`, form fields per `.design/prompts/Attendance_Clock_In_Out_Regularization_Plan.md §11`.

**Reason dropdown scope.** Per task 32's reconciliation, only the Regularization-mapped reasons
are offered: *Forgot to punch, Wrong punch time, Biometric error, Device issue, System issue,
Other* — not "On-duty / field work" or "Work from home" (those map to out-of-scope request types).

## Files

### Edited

- `frontend/src/lib/api.ts` — add under a new `// ── Attendance: daily log & regularization ──`
  banner:

  ```ts
  export type DailyLogRow = {
    id: number; attendance_date: string; day_label: string; day_type: string;
    attendance_status: string | null; first_in_at: string | null; last_out_at: string | null;
    worked_minutes: number; late_by_minutes: number; early_exit_minutes: number;
    is_late: boolean; is_regularized: boolean; payable_day_fraction: number;
    overtime_minutes: number; shift_name: string | null; source: string;
    is_locked: boolean; remarks: string | null;
  };

  export async function getMyDaily(from?: string, to?: string): Promise<{ items: DailyLogRow[]; total: number }> {
    // GET /api/v1/attendance/me/daily?from=&to=
  }

  export type RegularizationRequest = {
    id: number; status: "Pending" | "Approved" | "Rejected" | "Cancelled";
    attendance_date: string; punch: "Clock-in" | "Clock-out" | "Both";
    requested_in_at: string | null; requested_out_at: string | null; reason: string;
    applied_at: string; approver: { name: string; designation: string | null } | null;
    actioned_at: string | null; approver_remarks: string | null;
  };

  export async function listMyRequests(): Promise<RegularizationRequest[]> {
    // GET /api/v1/attendance/me/requests
  }

  export async function submitRegularization(payload: {
    attendance_date: string; punch: "Clock-in" | "Clock-out" | "Both";
    requested_in_at?: string; requested_out_at?: string;
    reason_code: string; note?: string;
  }): Promise<RegularizationRequest> {
    // POST /api/v1/attendance/requests — throw with the server's detail message on !ok,
    // callers show it inline in the modal (the window/monthly-cap/duplicate errors are
    // meant to be read by the employee, not swallowed into a generic "failed" toast)
  }

  export async function cancelMyRequest(id: number): Promise<RegularizationRequest> {
    // POST /api/v1/attendance/requests/{id}/cancel
  }
  ```

  Attachment upload uses plain `fetch` (not `secureFetch`), same shape as `uploadOrgImage` in this
  file — multipart to `POST /api/v1/attendance/requests/{id}/attachment`.

- `frontend/src/dashboards/Employee/MyAttendance.tsx`:
  - Delete the `DAILY_LOG` and `REGULARIZATION_REQUESTS` mock arrays.
  - Daily Log table: fetch `getMyDaily()` for the current month on mount; render the existing
    table markup (unchanged columns/classes) from real rows. `attendance_status: null` renders as
    `—`, never as a status pill — per `vocabularies.md §1`, NULL must never render as "Absent."
    `is_late` adds a small amber "Late" badge next to the status pill (a derived predicate, not a
    stored status — do not add a `"Late"` entry to `ATTENDANCE_STATUS_STYLES`, which keys on the
    real `attendance_status`).
  - Regularization list (the small card above Daily Log): fetch `listMyRequests()`, render
    date/punch/reason from real data; a `Cancelled`/`Rejected` row's status shows in a small badge
    (reuse `ATTENDANCE_STATUS_STYLES`'s color-coding idiom, extended with Pending/Approved/
    Rejected/Cancelled shades — pick colors consistent with the existing palette, e.g. amber for
    Pending, teal for Approved, a muted red for Rejected, ink-gray for Cancelled).
  - "Request regularization" button: `onClick` opens a new `RegularizationModal` component (new
    file, `frontend/src/dashboards/Employee/RegularizationModal.tsx`, following this codebase's
    existing modal convention — `px-5 py-4` header/body/footer padding, overlay treatment matching
    e.g. `ShareCredentialsModal.tsx`/`AddOrganizationModal.tsx`, per the `hrms-spacing` project
    convention for modal internals).
    - Fields, in order, per the prompt §11: Date (date picker, cannot be future), Punch
      (segmented control or select: Clock-in / Clock-out / Both), conditional In-time / Out-time
      inputs shown per the punch selection, Reason (select from the six values above), Note
      (textarea, optional unless reason is "Other" — require it then, since "Other" without a note
      is meaningless), Attachment (optional file input).
    - Footer: *"Approver · {name} ({designation})"* resolved from... the approver isn't known
      until submit in this API shape (task 32 returns it in the response, not before). Either (a)
      add a lightweight client-side resolution by reusing whatever endpoint already exposes the
      caller's reporting manager (check `Me`/`getMe()` in `api.ts` and the employee profile
      endpoints for one that already returns it — do not add a new backend endpoint just for this
      footer if one already exists), or (b) show the approver name only after a successful submit,
      in the success state. Prefer (a) if a suitable existing call is found during implementation;
      fall back to (b) rather than inventing new backend surface for a footer label.
    - Submit calls `submitRegularization`; on the window/cap/duplicate `422` errors, show the
      server's message inline (not a generic toast) since those are actionable ("try a date within
      the last 7 days"). On success, close the modal, show the existing toast success treatment,
      and refresh the regularization list.
  - Regularization list rows optionally get a "Cancel" action for `Pending` rows, calling
    `cancelMyRequest` and refreshing the list.

## Acceptance criteria

- [ ] Daily Log table renders real data for the current month; a NULL `attendance_status` shows
      as `—`, never "Absent."
- [ ] A late arrival shows both its real status (Present/HalfDay) and a separate amber Late badge
      — not a fabricated "Late" status.
- [ ] "Request regularization" opens a modal with Date, Punch, conditional time fields, Reason,
      Note, Attachment — matching the prompt's field list.
- [ ] Submitting outside the window, over the monthly cap, or for a duplicate date shows the
      server's specific error message inline in the modal.
- [ ] A successful submission closes the modal, shows a success toast, and the new request appears
      Pending in the list without a full page reload.
- [ ] A Pending request can be cancelled from the list; Approved/Rejected/Cancelled requests
      cannot.
- [ ] No new `.module.css`; modal follows the existing `px-5 py-4` header/body/footer convention.
- [ ] Manually verified in the browser: submit a request, confirm it appears Pending, confirm
      cancel works.

Completed: 2026-08-18
