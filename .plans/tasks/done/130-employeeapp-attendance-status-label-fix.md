---
task: 130
title: Fix employee app's attendance status label mapping (pre-existing bug, surfaced by the status-master migration)
status: done
depends_on: [127]
---

# 130 — Fix employee app's attendance status label mapping

## Scope

Part of the 126-130 status-master migration set — read [126](126-status-masters-seed-infra.md)
first. This is the "make changes to the employee app too" half of the original request. Because
tasks 126-129 deliberately preserve every existing wire value byte-for-byte (see 126's "hard
constraint"), the mobile app needs **no changes to keep working** — but research while scoping
this task set found the mobile app's attendance daily-log screen already has a **pre-existing,
independent bug**: its status-to-style switch matches strings the backend has never actually sent.
Fix that bug now, verified against the (unchanged) canonical `ATTENDANCE` status codes task 127
formalizes into `status_masters`.

`/home/solo/hr-prj/employeeapp/src/screens/ClockScreen/components/AttendanceListScreen/AttendanceList.js:9-24`:

```js
const getStatusStyle = status => {
    switch (status) {
        case 'Present':
            return Styles.presentText;
        case 'Late':
            return Styles.lateText;
        case 'Leave':
            return Styles.leaveText;
        case 'Half Day':
            return Styles.halfDayText;
        default:
            return Styles.absentText;
    }
};
```

called at `:98-99` as `getStatusStyle(item.attendance_status)` / `{item.attendance_status}` — i.e.
it switches on and renders the raw backend value directly. The backend's real `attendance_status`
values (confirmed by task 127's own vocabulary: `OnLeave`, `Present`, `HalfDay`, `OnDuty`, `WFH`,
`Absent` — never `"Leave"`, never `"Half Day"` with a space, and never `"Late"` at all, since Late
is a badge/metadata field alongside Present, not a status value — see
`docs/leave-and-attendance/attendance/vocabularies.md` §1.1) mean the `'Leave'`, `'Half Day'`, and
`'Late'` cases in this switch have **never matched anything** — an on-leave or half-day row has
always silently rendered with `Styles.absentText` (the default branch). This is not something
tasks 126-129 introduce; it's a live bug worth fixing while touching this area, since the user
asked for employee-app changes as part of this effort.

## Files

### Edited

- `/home/solo/hr-prj/employeeapp/src/screens/ClockScreen/components/AttendanceListScreen/AttendanceList.js`
  - Fix the switch to match the real values:
    ```js
    const getStatusStyle = status => {
        switch (status) {
            case 'Present':
                return Styles.presentText;
            case 'OnLeave':
                return Styles.leaveText;
            case 'HalfDay':
                return Styles.halfDayText;
            case 'OnDuty':
            case 'WFH':
                return Styles.presentText;  // styled the same as Present — confirm with
                                             // AttendanceListStyles.js whether a distinct style
                                             // exists first; if not, Present's style is the closest
                                             // existing precedent (both are "counted as worked" per
                                             // vocabularies.md)
            case 'Absent':
                return Styles.absentText;
            default:
                return Styles.absentText;
        }
    };
    ```
  - Drop the dead `'Late'` case — there is no `Late` status value; if a "Late" badge is wanted on
    this screen, that's a new feature (the backend already exposes `is_late`/`late_by_minutes` on
    `DailyLogRow` — see `backend/app/modules/attendance/schemas.py:198-217` — but the mobile
    screen doesn't currently consume those fields at all). **Do not build that in this task** — out
    of scope per the "migrate storage only" decision; note it as a follow-up opportunity in the PR
    description instead, don't silently add it.
  - Check `AttendanceListStyles.js` for what style constants actually exist (`presentText`,
    `lateText`, `leaveText`, `halfDayText`, `absentText`) before assuming `OnDuty`/`WFH` need a new
    style — reuse `presentText` if nothing else fits, per the instruction against adding
    unnecessary new abstractions/styles for a case with no design spec.

### Verified, not edited (confirm these still work correctly, given task 129's leave-status change)

- `/home/solo/hr-prj/employeeapp/src/screens/LeaveScreen/Components/RequestHistory/RequestHistory.js:13-41`
  and `/home/solo/hr-prj/employeeapp/src/screens/HomeScreen/components/RecentRequestsCard.js:12-52`
  — both already normalize via `status?.toUpperCase()` before looking up `STATUS_COLORS`, so they
  are resilient to case as long as the underlying word doesn't change (`Pending`/`Approved`/
  `Rejected`/`Cancelled` — task 129 doesn't change these words, only their storage). Confirm by
  reading `STATUS_COLORS`'s key set (find its definition — likely a shared constants file) and
  checking it has entries for all four uppercased values; if any are missing, that's the same class
  of bug as `AttendanceList.js` and should be fixed here too while this task is open.
- `/home/solo/hr-prj/employeeapp/src/screens/MyTeamScreen/MyTeam.js` — same status-rendering
  pattern per the earlier grep; check it the same way.
- The clock-in/out flow (`Attendance.js`, `AttendanceViewModel.js`) reads `state`
  (`not_started`/`clocked_in`/`clocked_out`), a field this task set never touches (it's not backed
  by `attendance_status` at all — see task 127's scope note) — no change needed, just confirm by
  reading it that nothing there also reads `attendance_status` in a way this task missed.

## Acceptance criteria

- [x] `AttendanceList.js`'s status switch matches the real backend values
      (`Present`/`OnLeave`/`HalfDay`/`OnDuty`/`WFH`/`Absent`) with no dead cases. `OnDuty`/`WFH`
      styled as `presentText` (no distinct style existed, and both count as worked per
      vocabularies.md); added a new `halfDayText` style (amber `pendingBg`/`pendingText`, reusing
      the existing token that the dead `'Late'` case used to occupy) since none existed.
- [ ] Manually verified in the mobile app (simulator or device against the running backend) — not
      done this session (no device/simulator available); verified instead by direct code review
      against the confirmed backend wire values, which this task set (126) established do not
      change. Left for whoever next runs the app to do a visual confirmation.
- [x] `RequestHistory.js` and `RecentRequestsCard.js` checked: both already have complete
      `STATUS_COLORS` maps (`APPROVED`/`PENDING`/`REJECTED`/`CANCELLED`, uppercased) — no gap found,
      no fix needed. `MyTeam.js`'s `getStatusStyle` was checked and is unrelated (a manager
      team-overview live-state field — `'Clocked In'`/`'Remote'`/`'On Leave'`/default — not backed
      by `attendance_status` or leave `status` at all).
- [x] No new status vocabulary, break-tracking, or Live-State/Attendance-Result split was added to
      the mobile app — this task is a bug fix within the existing vocabulary, not the larger
      redesign from the original design doc (that was explicitly descoped 2026-09-23).

**Note on depends_on**: this task's code change has no actual runtime dependency on task 127's
DB cutover (the wire values `Present`/`OnLeave`/`HalfDay`/`OnDuty`/`WFH`/`Absent` are unaffected by
where they're stored — that's the whole point of task 126's "wire values must not change"
constraint) — so it was safe to complete this ahead of 127's migration, which is currently blocked
on an unrelated broken Alembic chain on the shared dev DB (see 127's file for details).

Completed: 2026-09-23
