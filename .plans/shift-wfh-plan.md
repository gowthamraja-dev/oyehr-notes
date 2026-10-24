# Employee WFH requests → remote work location

Working copy: `workspace-1/hrms/` (user-directed for the shift-scheduling series; branch `feature/gowtham_go_live`).
Status: PLAN — schema approved 24-Oct-26, no code written yet.
Schema (approved, the contract): [`shift-wfh-schema.dbml`](shift-wfh-schema.dbml) — one new boolean
`work_location_masters.is_remote` + partial unique index + CHECK. Do not restate or edit it here.
Follows task 246 (read-only WFH marker on the roster) and the open items in task 247.

## 1. Scope

**In**
- HR marks one work location per tenant as the **remote** site (Work Locations screen).
- An employee raises a WFH request for a date range; their reporting manager (or an admin) approves or
  rejects it; the employee can cancel while it is Pending.
- **Approval switches each eligible day's work location to the remote site.** That is the whole effect.
- Roster shows it already: the remote site's badge (task 240) plus the WFH marker (task 246).

**Out (explicit)**
- Any attendance-status or payroll effect. WFH writes no `employee_attendance_details` row, and nothing in
  payroll reads it. (Decided 24-Oct-26.)
- Undo: an Approved request cannot be cancelled / revoked (Decided 24-Oct-26).
- `OnDuty` / `ShortLeave` requests (still no surface; `attendance/gaps.md` gap 6 keeps them open).
- A `work_mode` enum / several remote sites per tenant.
- The mobile app screen. The endpoint is built and documented for it, but `employeeapp` is a separate task.

## 2. Flow

```
HR: Work Locations → pick a site → "Remote (WFH) site" on          [248, 249]
        service: only one live remote site per tenant; not the org default;
                 mobile punch mode must be NoCheck (web must be NoCheck if web punching is on)

Employee: Attendance → "Work from home" → From / To / Reason       [247, 250]
        form footer: "Approver · <name>"; blocked with a message when there is no approver
        or the tenant has no remote site
        POST /attendance/requests/wfh  → attendance_request_details(request_type='WFH', Pending)

Manager / admin: Requests inbox → Approve | Reject (reason)         [247, 251]
        approve (one transaction): status → Approved
                                   + location-only write to the remote site, from_date..to_date
        reject: status → Rejected, nothing else changes

Employee: cancel a Pending request                                  [247, 250]
```

Approval write = the task-242 location-only range logic: keep each day's shift and holiday calendar, set
`work_location_master_id` to the remote site, through `_plan_and_apply_employee_days` (the helper range
assign and copy-week already share). Per-day skip rules are the same: outside employment, locked,
no standing shift (a location needs a shift row to live on), weekly off, unchanged. Skipped days come
back in the approve response so the approver sees what did not change. `overwrite_manual = true`: an approver's
explicit decision replaces an earlier manual location on those days.

## 3. Backend

| Area | Change |
|---|---|
| Model + migration (248) | `is_remote` on `WorkLocationMaster`; partial unique index `ix_work_location_masters_one_remote_per_cdp` (`WHERE is_remote = true AND archive = false`); CHECK `ck_work_location_masters_remote_not_default`. One Alembic revision on the HRMS branch, plus a hand-written, existence-guarded copy of the DDL for the shared hrms-dev DB (applied only with the user's go-ahead) |
| Work-location API (248) | `is_remote` on `WorkLocationIn` / `Patch` / `Out`. Rules in `create_work_location` / `update_work_location`: 409 naming the current remote site when another live one exists; 422 if the site is the org default; 422 unless `mobile_punch_check_mode = 'NoCheck'` (and `web_punch_check_mode = 'NoCheck'` when `web_punch_enabled`); while remote, changing either mode away from NoCheck is refused. `organizations._sync_default_work_location` unchanged (never touches the flag). Archiving the remote site is allowed |
| Requests (247) | `WfhRequestIn`, `submit_wfh_request`, `RequestOut` / `ManagerRequestOut` carry `request_type` and a date range, `list_my_requests` / `list_requests_for_manager` accept `?request_type=`, `cancel_my_request` confirmed type-agnostic (Pending only), `approve_request` / `reject_request` branch on type. Gates: raise / cancel are self-service (ungated); approve / reject keep `APPROVE ATTENDANCE` |
| Rules (247) | Range `to >= from`, ≤ 31 days; reason required; no Pending/Approved WFH overlapping any date; no overlap with the caller's Pending/Approved leave; no locked days; dates inside employment; resolvable approver; tenant has a live remote site; past dates only within `regularization_window_days` |
| Audit / logging | `log_activity` on raise, cancel, approve, reject; INFO on success, WARNING at each guard; no PII |

## 4. Frontend

| Screen | Change |
|---|---|
| Work Locations (249) | "Remote (WFH) site" switch on the site form and a chip on the list; tells HR which site currently holds it; explains the NoCheck rule |
| Employee (250) | `WfhRequestModal` (From / To via `DateField`, reason, live approver footer, shimmer body), entry beside Regularization, WFH rows in the request list with a range and a Cancel (`useConfirm`) |
| Inbox (251) | WFH rows in the existing inbox: type chip, range, reason, Approve / Reject; after approve, a toast and a panel for skipped days (reuse `RangeResultBody`) |

## 5. Tests
- Backend: each task ships its own (see the task files): remote-site rules + cross-tenant (248); the full request
  lifecycle, location write, skips, atomicity, no attendance/payroll row written, 401/403 and cross-tenant (247).
- Browser smoke per UI task against a local DB (never the shared dev DB); final end-to-end: HR marks site →
  employee raises → manager approves → roster shows the remote badge + WFH marker.

## 6. Order and dependencies
`248` (model + migration + work-location API) → `249` (Work Locations UI) ‖ `247` (requests backend) →
`250` (employee UI) ‖ `251` (inbox UI).

## 7. Open decisions
- **Web punch mode on the remote site.** The approved Q2 covers the app's mode. This plan applies the same
  `NoCheck` rule to the web mode when web punching is on, because a browser at home can't satisfy a geofence.
  Confirm, or relax it to a warning.
- **Past-dated WFH** window: defaults to `regularization_window_days`.
- **Range cap**: 31 days.
- **Inbox shape**: one combined inbox with a type filter (task 251 assumes this).
- **Mobile**: `employeeapp` endpoint docs go into the `hrms-mobile-api-integration` skill when 247 lands.
