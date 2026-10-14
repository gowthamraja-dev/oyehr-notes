---
task: 136
title: Open-session detection and punch debounce must not depend on direction
status: done
depends_on: [134]
---

# 136 — Open-session detection and punch debounce must not depend on direction

## Problem
Task 134 made worked-minutes settlement direction-agnostic (first punch → last punch). But
"is this employee currently clocked in?" is still answered by **"latest punch has
`direction == 'IN'`"**, in two places:

- `hrms/backend/app/modules/attendance/service.py:_open_in_punch` — clock-in duplicate guard,
  clock-out session lookup, `/me/today` + `/employees/{id}/today` state and live timer.
- `hrms/backend/app/modules/attendance/dashboard_service.py:_open_punch_map` — manager
  register / analytics / exceptions live credit and the `stale_open_session` exception.

The ZKTeco terminals report status 0 (= IN) unless a function key is pressed first — 105 of
the first 106 live punches were IN (`devices/service.py` `DeviceConfig.trust_device_direction`
note). So a device user's evening departure is stored as IN, and the system then treats them as
clocked in until their next punch:

1. `stale_open_session` exception raised for every device user overnight / weekends / leave.
2. The employee's Today card stays "clocked in" with a running timer.
3. A next-morning app clock-in is refused: `409 Already clocked in at 18:05`.

## Rule (the fix)
For the employee's latest active, non-archived punch:

- **Trusted-direction sources** (`Web`, `Mobile`, `Manual`) — unchanged: open iff
  `direction == 'IN'`, with no date bound (a forgotten app clock-out stays open so
  `clock_out` can close it and `stale_open_session` can flag it).
- **Direction-untrusted sources** (`Biometric` — both the iclock device path and the punch
  webhook write this) — direction is ignored. The session is open only when ALL hold:
  1. the punch belongs to **today's business date** (`resolve_business_date_for_instant(now)`;
     the punch's own date is its linked day row's `attendance_date`, else resolved from
     `punch_at`),
  2. **today's day hasn't closed** — `now < shift_end_at` (`_day_closed`; no shift → the
     calendar-day boundary, same as recompute), and
  3. **an odd number of kept punches** for today (after the existing 60s debounce) — 1st punch
     = arrival, 2nd = departure, 3rd/4th = lunch out/in. This is what lets a device user's
     departure show as "out" immediately instead of staying "in" until shift end.

   (1)+(2) are the bound the user asked for; (3) is an added necessary condition within that
   bound — it can only make a session read as *closed*, never open one the bound would close.

Consequences: a biometric session can never be stale, so `stale_open_session` only ever flags
app/web sessions; a device arrival still blocks a duplicate app clock-in and can be closed by
an app clock-out.

## Scope
- New shared helper in `hrms/backend/app/services/attendance_recompute_service.py`:
  `is_open_session(db, tenant_id, employee_id, punch, now, shift_cache=None) -> bool` +
  `DIRECTION_UNTRUSTED_SOURCES = frozenset({"Biometric"})`.
- `_open_in_punch` → fetch latest punch (now also tenant-scoped), apply the helper.
- `_open_punch_map` → batch-fetch latest punch per employee (unchanged `DISTINCT ON`), apply
  the helper per employee.
- **Debounce ignores direction** (added to scope 29-Sep-26 at the user's request):
  `_debounce_and_direction` drops any punch within 60s of the previous *kept* punch, whatever its
  direction. Previously only a same-direction repeat was dropped, so a device IN + OUT re-badge
  survived as two punches — moving `last_out_at` by the gap and flipping the parity check above.
  Applies to every source (settlement is source-blind). Accepted trade-off: an app clock-in +
  clock-out less than 60s apart keeps only the clock-in (a sub-minute session is a mis-tap).
- Tests (below).
- Docs: `hrms/docs/leave-and-attendance/attendance/assembler.md` (§5.2 + "Who counts as currently
  clocked in"), `api-and-pages.md` (`stale_open_session` note).

**Not in scope** (separate follow-ups if wanted): auto-running `pending_attendance_rebuild`; logging punches that land
on a locked day; `Manual` (regularization) IN punches being treated as open sessions; the HR
register page not auto-refreshing.

## Files
- `hrms/backend/app/services/attendance_recompute_service.py`
- `hrms/backend/app/modules/attendance/service.py`
- `hrms/backend/app/modules/attendance/dashboard_service.py`
- `hrms/backend/app/modules/devices/service.py` (comment only)
- `hrms/docs/leave-and-attendance/attendance/assembler.md`, `api-and-pages.md`
- `hrms/backend/app/tests/modules/test_attendance_recompute.py` (helper unit tests, fixed `now`)
- `hrms/backend/app/tests/modules/test_attendance.py` (clock-in / Today endpoint)
- `hrms/backend/app/tests/modules/test_attendance_dashboard.py` (exceptions / register)

## Acceptance criteria
- [x] Helper: biometric IN from a previous business date → closed.
- [x] Helper: biometric single punch today, before shift end → open (direction IN *or* OUT).
- [x] Helper: biometric two punches today (both IN) → closed.
- [x] Helper: biometric single punch today, after shift end → closed.
- [x] Helper: Web IN from days ago → still open (unchanged app behaviour).
- [x] `stale_open_session` count is 0 for a device user whose last punch (IN) was yesterday;
      still 1 for a Web IN from days ago (existing test stays green).
- [x] App clock-in succeeds after yesterday's biometric IN departure; refused (409) after a
      single biometric arrival punch today.
- [x] `/me/today` shows `clocked_out` after an arrival+departure pair of biometric INs.
- [x] Debounce: an opposite-direction re-tap within 60s is dropped; a punch >= 60s after the last
      kept one is kept; the window is measured from the last *kept* punch; settled first/last/
      worked are identical whatever direction a re-tap carries.
- [x] Existing attendance / dashboard / recompute / devices / webhooks tests all pass.

## Verification
`uv run pytest` over test_attendance, test_attendance_dashboard, test_attendance_recompute,
test_devices, test_webhooks, test_attendance_assembler_job: 281 passed, 2 failed. The two failures
(`test_devices.py::test_unmapping_returns_punches_and_empties_the_day_row`,
`::test_reported_name_reaches_the_unresolved_reason_on_a_punch`) are pre-existing and
data-dependent: both look a punch up by `enrollment_no` alone, and the shared dev DB holds real
device punches for PINs 1 and 172, so the query returns a real punch instead of the test's. Not
caused by this change (neither test reaches the open-session or debounce code paths).
Separately, `test_attendance_dashboard.py::test_analytics_yesterday_never_punched_counts_absent`
fails when run on a Sunday or Monday ("yesterday" defaults to a week-off); it passed on this run.

Completed: 2026-09-29
