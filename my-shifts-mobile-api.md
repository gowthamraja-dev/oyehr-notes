# My Shifts — mobile API

Base: `/api/v1` · Auth: `Authorization: Bearer <JWT>` · All six routes are on the **encrypted** `/shifts` router (same RSA + AES
payload encryption as the other `/me/*` calls, GETs included; see the `hrms-mobile-api-integration` skill). Error bodies are plaintext.

Caller must be an employee (otherwise 403). Values in the examples are illustrative.

## Screen → endpoint

| Screen | Call |
| --- | --- |
| Home "Today's Shift" | `GET /shifts/me/{yyyy-mm-dd}` (`null` body if nothing assigned) |
| Home "This Week" | `GET /shifts/me/calendar?from=<Mon>&to=<Sun>` |
| Calendar tab | `GET /shifts/me/calendar?from=<1st>&to=<last>` |
| My Shifts tab | same calendar response, filter to today onwards on the client |
| Request form | `GET /shifts/me/available?date=` |
| Submit | `POST /shifts/me/change-requests` |
| Requests tab | `GET /shifts/me/change-requests?status=&page=&page_size=` |
| Request Details | `GET /shifts/me/change-requests/{id}` |
| Cancel Request | `POST /shifts/me/change-requests/{id}/cancel` |

## 1. Calendar

`GET /shifts/me/calendar?from=2026-10-01&to=2026-10-31` — range ≤ 62 days (else 422).

```json
{
  "from_date": "2026-10-01", "to_date": "2026-10-31", "time_zone": "Asia/Kolkata",
  "days": [{
    "date": "2026-10-27",
    "day_type": "Working",
    "is_half_day": false,
    "outside_employment": false,
    "shift": { "shift_master_id": 12, "name": "General", "code": "GEN", "color": "#14716F",
               "start_time": "10:30:00", "end_time": "19:30:00", "is_night_shift": false },
    "holiday": null,
    "day_override": null,
    "has_pending_change_request": false
  }],
  "summary": { "working_days": 20, "week_offs": 9, "holidays": 1, "unassigned_days": 0 }
}
```

- `day_type`: `Working` | `WeekOff` | `Holiday`; `null` + `outside_employment: true` before joining / after leaving (grey out).
- Dots: green = `Working` with a `shift`, blue = `WeekOff`, pink = `Holiday`. "Assigned" / "Off" come from `day_type`.
- `shift: null` on a working day = nothing assigned.
- `holiday`: `{name, holiday_type}`, Public holidays only. `day_override`: `WeekOff` / `Working` when HR swapped the day.
- `has_pending_change_request`: a Pending request exists for that date.
- Times are clock faces at the work location (`time_zone`), not UTC.

## 2. Available shifts

`GET /shifts/me/available?date=2026-10-27`

```json
{
  "date": "2026-10-27",
  "current_shift": { "shift_master_id": 12, "name": "General", "start_time": "10:30:00", "end_time": "19:30:00" },
  "shifts": [
    { "shift_master_id": 14, "name": "Morning", "start_time": "09:00:00", "end_time": "13:00:00", "is_current": false },
    { "shift_master_id": 12, "name": "General", "start_time": "10:30:00", "end_time": "19:30:00", "is_current": true }
  ]
}
```

`current_shift` fills the read-only "Current Shift" box. Show every item in `shifts`, disable the one with `is_current: true`.
Today is allowed; a past date or a date outside employment → 422.

## 3. Submit

`POST /shifts/me/change-requests`

```json
{ "date": "2026-10-27", "requested_shift_master_id": 14, "reason": "Personal work" }
```

`reason` is required, 1–500 characters after trimming. Returns **201** with the request object below.

## 4. Request object

Same shape for submit, detail, cancel and each list item.

```json
{
  "id": 507, "status": "Pending", "date": "2026-10-27",
  "current_shift":   { "shift_master_id": 12, "name": "General", "start_time": "10:30:00", "end_time": "19:30:00" },
  "requested_shift": { "shift_master_id": 14, "name": "Morning", "start_time": "09:00:00", "end_time": "13:00:00" },
  "reason": "Personal work",
  "applied_at": "2026-10-27T04:45:00Z",
  "actioned_at": null,
  "approver": { "employee_master_id": 3988, "name": "Manager" },
  "approver_remarks": null,
  "can_cancel": true
}
```

- `status`: `Pending` | `Approved` | `Rejected` | `Cancelled`.
- `applied_at` is "Submitted on" (UTC). `approver_remarks` is the "Remarks:" line on Rejected rows.
- `can_cancel` is true only while Pending — drive the Cancel button from it.
- `current_shift` is the shift when they asked and does not change after approval, so "Evening → General Shift" renders correctly.

## 5. List and cancel

- `GET /shifts/me/change-requests?status=Pending&page=1&page_size=20` → `{ items, total, page, page_size }`, newest first.
  Omit `status` for "All Status". `page_size` ≤ 100. Unknown status → 422.
- `POST /shifts/me/change-requests/{id}/cancel` → the updated request. Not Pending → 422 `Cannot cancel a request that is already Approved`.
- An id that isn't the caller's own, or isn't a shift change → 404.

## Errors

- Plain refusal: `{"detail": "<sentence>"}`, status 422 — show the sentence to the user.
- Missing employee record: 403.
- Field validation (empty / over-500 `reason`, missing field, bad date): 422 with FastAPI's list-style `detail`.
  Handle `detail` as a string **or** a list.

Submit refusals (422):

- `You can only ask for a shift change from today onwards`
- `There is no shift assigned on that date`
- `That day is a holiday, so no shift change is needed`
- `That day is a week off, so no shift change is needed`
- `There is approved leave on that day`
- `That shift is not available for the date you picked`
- `You are already on that shift on that date`
- `That shift has a week off on the date you picked`
- `You have already clocked in today, so today's shift can no longer be changed`
- `You already have a pending shift change request for that date`
- `No approver is configured for your profile — contact HR`
- `That date is outside the employee's employment dates`

## Behaviour to know

- Submitting changes nothing. The shift only changes when the manager approves (web), and then only for that one day. Refresh the list
  and calendar when the screens open.
- "Today" is the employee's work-location date, not the server's.
- Shift changes are not in `GET /attendance/me/requests` unless you pass `?request_type=ShiftChange`.
- The endpoints are live only after the API is rebuilt and deployed from the branch that contains them.

Full reference: `docs/leave-and-attendance/shifts/api-and-pages.md` §3.3 (in `workspace-2/hrms/`).
