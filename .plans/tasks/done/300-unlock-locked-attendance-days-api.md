---
task: 300
title: Unlock locked attendance days — API
status: done
depends_on: []
---

# 300 — Unlock locked attendance days — API

## Scope
`POST /attendance/unlock` `{targets: [{employee_id, dates[]}], reason}` (`backend/app/modules/attendance/unlock.py`, schemas `UnlockIn/UnlockOut`) clears `is_locked` for the listed employee-days.
Gate APPROVE ATTENDANCE + org-wide scope (`regularize_range._require_hr_for_all`: foreign id 404s the whole call). Days not locked → `skipped NOT_LOCKED`; days in a processed payroll period →
`failed PAYROLL_CLOSED`. Each unlocked day writes an `attendance_audit_logs` `DayUnlocked` row with the reason, each employee one `user_activity_details` row. The result flags unlocked days older
than the shift's `regularization_window_days` (`outside_window`, `window_days`) because the employee's own request is still bounded by it. Changes nothing but the flag — no recompute.

## Files
`backend/app/modules/attendance/{unlock.py,schemas.py,router.py}`, `backend/app/tests/modules/test_attendance_unlock.py`.

## Acceptance criteria
- [x] Unlock clears the flag only and writes the audit + activity rows (`test_attendance_unlock.py`)
- [x] Not-locked → skipped; payroll-closed → failed; window flag set per shift
- [x] 401 / 403 (manager) / 404 (foreign employee, nothing written) / 422 (blank reason, caps)

## Progress (2026-10-28)
Built; imports and schema validation checked. The new tests have NOT been run — they need the Postgres on :5433, which was not running (starting it needs approval).

Verified 2026-10-28: `uv run pytest app/tests/modules/test_attendance_unlock.py` -> 15 passed (against workspace-2 code; test Postgres container hrms-test-pg started for the run, then stopped).

Completed: 2026-10-28
