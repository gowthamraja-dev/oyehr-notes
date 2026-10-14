---
task: 216
title: Web — show punch verification status in the HR attendance popover
status: done
depends_on: [211]
---

# 216 — Web: show punch verification status in the HR attendance popover

## Scope
Today HR can't tell a Verified app punch from an Unverified web punch anywhere, and refused
attempts are visible only as unrecognised-SSID counts in NetworkPanel. This task is **web
only** (`workspace-2/hrms/frontend/`).

- In the HR Manager attendance "i" punches popover (`frontend/src/dashboards/hrManager/Attendance.tsx:1027-1029,1143-1146`),
  render `verification_status` as a badge: Verified (teal) or Unverified (muted). The data is
  already returned by `GET /employees/{id}/today/punches` and typed in `lib/api.ts:1864-1871`.
- Not included: verification in the register, daily-log and export. Those backend schemas don't
  carry the field.

**Out of scope (needs backend):** a refused-attempt history view. There is no read endpoint
over `attendance_audit_log` today, and backend work isn't planned. Unrecognised SSIDs with
punch counts are already visible in NetworkPanel.

## Files
- `frontend/src/dashboards/hrManager/Attendance.tsx`, `frontend/src/lib/api.ts`

## Acceptance criteria
- [ ] The popover shows Verified or Unverified per punch.
- [ ] Punches with a null `verification_status` (older rows, device or regularized punches) show no badge.
- [ ] `npm run build` and lint pass, and the popover is smoke-tested in a browser.

Implemented in workspace-2/hrms commit `d0e0225` on `feature/gowtham_WebPunchPolicy` (pushed; PR to `main`). `tsc` clean, lint adds nothing new. The unticked checks above were **not** browser-verified. Moved to done at the user's request.

Completed: 2026-10-12
