---
task: 04
title: Attendance admin module tests
status: done
depends_on: [3]
---

# 04 — Attendance admin module tests

Part of the Attendance admin-config backend slice. Per `CLAUDE.md`, every module ships with
tests in the same change as the feature — this task exists separately only because the
parent plan was split by file boundary, not because tests should lag behind.

## Scope

`backend/app/tests/modules/test_attendance.py`, mirroring `test_organizations.py`'s
structure (path constants, `_token`/`_auth` helpers, comment-banner sections per resource)
and `test_employees.py`'s cross-CDP fixture pattern
(`other = CareDeliveryProgramMaster(...)` + a second `CorpMaster`).

## Coverage required

For every endpoint group (work-locations, shifts + week-offs, holiday-calendars + holidays +
import, employee-shifts, config):
- Happy path.
- `401` unauthenticated.
- `403` non-admin.
- Cross-CDP isolation — a second tenant's rows never appear in list/detail responses, and
  attaching a location to another tenant's corp is rejected.
- Validation errors (see module-specific must-haves below).
- An encrypted round-trip test for `router` (per `app/tests/modules/test_encryption.py`'s
  pattern) — at least once for this module, doesn't need repeating per endpoint.

Module-specific must-haves:
- [x] Shift create/update: night-shift/times mismatch rejected (`422`);
      `min_half_day_minutes >= min_full_day_minutes` rejected.
- [x] Week-off replace: old rows gone after `PUT`, new set persisted; out-of-range
      `day_of_week`/`week_of_month` rejected.
- [x] Holiday calendar: duplicate date within one calendar rejected
      (`uq_holiday_details_calendar_date`); CSV import with one bad row inserts **nothing**.
- [x] Employee-shift assignment: assigning a second shift terminates the first
      (`trmntn_dt = new.effctv_dt - 1 day`) in the same transaction.
- [x] `/config`: `PUT` with an unknown key → `422`; partial `PUT` only changes supplied
      keys; `default_week_off_days` round-trips as a `list[int]`.

## Acceptance criteria

- [x] `docker compose exec api python -m pytest app/tests/modules/test_attendance.py -v`
      (host-side `uv run` is blocked by the known CodeArtifact/nhforms 401) — all 35 tests
      pass.
- [x] Every acceptance-criteria checkbox above is backed by an actual test.
- [x] Full suite (`python -m pytest -q`) run afterward: 116 passed, plus 9 pre-existing
      failures in `test_engagement.py`/`test_engagement_email.py`/`test_webhooks.py`
      unrelated to this work (missing `chat_room_type_masters` seed row, id 6, in this
      local dev DB — confirmed via `git status` showing zero changes to any of those
      files or their tables this session).

Note: `admin_token` fixture (module-local, in `test_attendance.py`) flips
`tenant.user.is_admin = True` — no existing fixture covers an admin caller since this is
the first admin-gated module in the test suite. Left `conftest.py` untouched.

Completed: 2026-08-11
