---
task: 82
title: Employee attendance session timer flow
status: done
depends_on: []
---

# 82 — Employee attendance session timer flow

## Scope
Make the employee attendance clock represent the current active clock-in session. The timer must
survive navigation or refresh, reset after clock-out, and restart from the new active punch after a
subsequent clock-in. Preserve aggregate worked-time reporting outside the clock card.

## Files
- `backend/app/modules/attendance/schemas.py`
- `backend/app/modules/attendance/service.py`
- `backend/app/tests/modules/test_attendance.py`
- `frontend/src/lib/api.ts`
- `frontend/src/dashboards/Employee/MyAttendance.tsx`

## Acceptance criteria
- [x] The today-attendance API exposes the active IN punch timestamp only while clocked in.
- [x] The clock card is anchored to the active IN timestamp across refresh/remount.
- [x] Clock-out stops and resets the clock card to `00:00:00`.
- [x] A later clock-in starts a new session timer without including the prior break.
- [x] Backend attendance flow tests, frontend TypeScript, and changed-file lint checks pass.

Completed: 2026-08-19
