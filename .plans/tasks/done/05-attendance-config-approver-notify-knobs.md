---
task: 05
title: Wire regularization_approver + notify_on_late_mark knobs
status: done
depends_on: []
---

# 05 — Wire regularization_approver + notify_on_late_mark knobs

Follows the completed attendance-admin backend slice (`01`-`04` in `.plans/tasks/done/`).
`docs/leave-and-attendance/14-config-knob-reference.md` §4.1 documents 15 attendance-policy
knobs at ids 300-309, but Task 02 only wired 15 of the full ~34-knob catalogue into
`tenant_params.PARAM_IDS`, and **skipped two of the 300-309 block**:
`regularization_approver` (302) and `notify_on_late_mark` (306). This task closes that gap so
the existing `/attendance/config` endpoint round-trips them like every other knob — additive to
the same file/dict per Task 02's own note, not a rewrite.

## Scope

Backend only. No new tables, no migration — `parameter_masters` and
`care_delivery_program_parameter_details` already exist and already hold every other knob.

**Not in scope**: the frontend settings page that will actually expose these two fields to an
admin (see sibling task `06-attendance-settings-frontend-page.md`, `depends_on: [5]`).

## Files

**`backend/app/services/tenant_params.py`** — add two entries to `PARAM_IDS`:
```python
"regularization_approver": 302,
"notify_on_late_mark": 306,
```
No other code change — `get_str`/`get_bool`/`upsert` already dispatch generically by Python
type (`isinstance(value, bool)` checked before `int`), so a `str` knob and a `bool` knob need no
new branches.

**`backend/app/modules/attendance/schemas.py`** — add to `AttendanceConfigOut` (required field)
and `UpdateAttendanceConfigRequest` (`Optional[...] = None`, the class already has
`model_config = ConfigDict(extra="forbid")`):
```python
regularization_approver: str          # str | None = None on the Update schema
notify_on_late_mark: bool             # bool | None = None on the Update schema
```
No `field_validator`/enum constraint — matches this file's existing convention
(`late_mark_reset_cycle` is also a bare unconstrained `str`). Enum enforcement for
`regularization_approver`'s two valid values (`ReportingManager` / `HRAdmin` — see Task 06)
stays UI-only, consistent with how `late_mark_reset_cycle` (`Monthly`/`Quarterly`) is handled
today.

**`backend/app/modules/attendance/service.py`** — in `get_config`, add two reads using the
defaults from the knob-reference doc:
```python
regularization_approver=tenant_params.get_str(db, cdp_id, "regularization_approver", "ReportingManager"),
notify_on_late_mark=tenant_params.get_bool(db, cdp_id, "notify_on_late_mark", True),
```
`update_config` needs **no change** — it already does
`payload.model_dump(exclude_unset=True).items()` and calls `tenant_params.upsert(db, cdp_id,
name, value)` generically for every key except the special-cased `default_week_off_days`; the
two new keys fall through that same generic branch once they exist on the schema.

**`backend/scripts/seed_attendance_leave_masters.py`** — iterates `tenant_params.PARAM_IDS`
directly, so it will auto-create `parameter_masters` rows at ids 302/306 once the dict entries
above exist. Add two entries to its per-knob description mapping so the seeded rows get a real
`parameter_desc` instead of falling back to the bare param name:
```python
"regularization_approver": "Role that approves attendance regularization requests (ReportingManager or HRAdmin).",
"notify_on_late_mark": "Whether the employee is notified when a late-mark is recorded against them.",
```

**`backend/app/tests/modules/test_attendance.py`** — extend the existing config test block:
- `test_config_defaults`: add assertions `body["regularization_approver"] == "ReportingManager"`
  and `body["notify_on_late_mark"] is True`.
- New test (mirror `test_config_partial_update_only_changes_supplied_keys`'s shape): `PUT
  {"regularization_approver": "HRAdmin", "notify_on_late_mark": False}` → `200`, both fields
  round-trip in the response, and an untouched field (e.g. `regularization_window_days`) stays
  at its default — proves the partial-update contract still holds with the enlarged schema.
- No change needed to `test_config_unknown_key_rejected` or the encrypted round-trip test —
  both are field-agnostic already.

## Deploy / rollout note (not a code change, but blocks Task 06's manual testing)

`care_delivery_program_parameter_details.parameter_master_id` has a real DB-level
`ForeignKey("parameter_masters.id")` (`backend/app/models/care_delivery_program_parameter_detail.py:24`).
`GET /attendance/config` works before reseeding (missing-row defaults are Python-level
fallbacks in `tenant_params.get_*`, independent of whether the catalogue row exists), but `PUT`
on either new knob **will fail with an FK violation** until
`uv run python -m scripts.seed_attendance_leave_masters` (via `docker compose exec api`, per the
known host-side CodeArtifact/nhforms 401) has been re-run against the target DB. Re-run it as
part of this task's own acceptance check, not left for Task 06.

## Acceptance criteria

- [x] `PARAM_IDS` includes `regularization_approver: 302` and `notify_on_late_mark: 306`.
- [x] `AttendanceConfigOut`/`UpdateAttendanceConfigRequest` include both fields with correct
      required/optional shape; unknown keys still `422` (`extra="forbid"` unaffected).
- [x] `GET /api/v1/attendance/config` returns `regularization_approver: "ReportingManager"` and
      `notify_on_late_mark: true` by default on a CDP with no rows yet — verified via
      `test_config_defaults`.
- [x] Seed script re-run creates exactly 2 new `parameter_masters` rows (ids 302, 306) — total
      went from 15 to 17; running it again left the count at 21 (this dev DB's cumulative total
      across all seeded params) unchanged (idempotency preserved) — verified live.
- [x] `PUT` with either new key updates it and leaves every other knob untouched
      (`test_config_can_update_approver_and_notify_toggle`); a `PUT` prior to reseeding
      reproduced the FK-violation failure mode live (confirms the prerequisite is real, not
      theoretical).
- [x] `docker compose exec api python -m pytest app/tests/modules/test_attendance.py -v` — all
      36 tests pass, including the 2 new/extended config assertions. Full suite
      (`python -m pytest -q`) afterward: 117 passed (up from 116), same 9 pre-existing
      unrelated failures in `test_engagement.py`/`test_engagement_email.py`/`test_webhooks.py`
      as noted in task 04's completion log (missing `chat_room_type_masters` seed row) — no
      regressions introduced.

Note: mid-task, `docker-compose.yml`'s `DATABASE_URL` was found pointing at a remote host with
plaintext credentials (an uncommitted local change, same class of issue task 03 hit) — reverted
to the local `db` service per user confirmation before reseeding or re-running tests.

Completed: 2026-08-11
