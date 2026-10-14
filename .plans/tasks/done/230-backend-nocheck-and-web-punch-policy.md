---
task: 230
title: Backend — NoCheck verification, web clock-in from its own switch and mode, admin guards
status: done
depends_on: [229]
---

# 230 — Backend: NoCheck verification, web clock-in from its own switch and mode, admin guards

Clone: **top-level `hrms/`**, branch `feature/gowtham_ClockInNoCheck`. Plan: `.plans/clockin-other-mode-web-key-plan.md`.
Logging in this clone is stdlib `logging` with `%s` placeholders (not structlog).

## Scope
Columns from 229 on `work_location_masters`:
- `mobile_punch_check_mode` ∈ {Wifi, Geofence, WifiAndGeofence, **NoCheck**};
- `web_punch_enabled` bool, default false;
- `web_punch_check_mode` ∈ {**Geofence** (default), NoCheck}.

229 also added `CHECK_NONE`, `WEB_CHECK_MODES` and `web_check_mode(loc)` to
`punch_verification_service`.

Both keys stay on `GET /api/v1/attendance/me/punch-policy`. The mobile app is unchanged.

```
web_punch_allowed = loc is not None AND loc.mobile_punch_enabled AND loc.web_punch_enabled
```

### `services/punch_verification_service.py`
1. Add `web_punch_allowed(loc: WorkLocationMaster | None) -> bool` implementing the rule above.
   It is the only place the formula lives.
2. `verify_punch`, **web** (`punch_source != "Mobile"`):
   - **Not allowed:** return `Refused`, `reasons=["web_punch_not_allowed"]`, and set
     `ev["web_block"] = "no_work_location" | "site_not_enabled" | "web_not_enabled"`. This
     replaces today's accept-as-`Unverified` at app-OFF sites and today's unconditional
     refusal at enabled sites.
   - **`web_check_mode(loc) == "NoCheck"`:** return `Unverified`. Still compute
     `is_within_geofence` / `distance_mtrs` when coordinates exist, and set
     `ev["check_mode"] = "NoCheck"`.
   - **`"Geofence"`:** run the existing geofence + accuracy block (location_unavailable /
     location_mismatch / accuracy_too_coarse) with no Wi-Fi block, and set
     `ev["check_mode"] = "Geofence"`. Factor the geofence/accuracy block into a helper the app
     and web paths share, rather than duplicating it.
3. `verify_punch`, **app**, with `check_mode(loc) == "NoCheck"`: skip the Wi-Fi, approved-network,
   geofence and accuracy checks. Return `Unverified`, with geofence still computed for the
   record and `ev["check_mode"] = "NoCheck"`.
4. Update the module and function docstrings and the decision table. `Unverified` now means
   "accepted under a No Check mode (app or web): deliberately not checked".

### `modules/attendance/service.py`
5. `get_punch_policy`:
   - set `web_punch_allowed=web_punch_allowed(work_location)` on **every** return (no_shift and
     no_work_location → False);
   - set `web_check_mode=web_check_mode(loc)` when the web is allowed, else None;
   - app `NoCheck` → `can_punch_from_app=True`, `requires_wifi=False`, `requires_location=False`,
     `check_mode="NoCheck"`, and no approved-network check (that check only runs for Wi-Fi modes;
     verify this).
6. `_refusal_message`, `web_punch_not_allowed` → **"Clocking in from the browser isn't switched on
   for your location. Please use the mobile app, or contact HR."** Task 232 copies it word for word.
7. `_assert_site_ready_for_app_punch`: app NoCheck needs nothing. The existing per-mode branches
   already allow that; add a comment.
8. New `_assert_site_ready_for_web_punch(loc)`: if `loc.web_punch_enabled and web_check_mode(loc) == "Geofence"`,
   require `lttd`/`lgtd` and `geo_fence_radius_mtrs`. Otherwise 422: "This location needs
   coordinates, an allowed distance before web clock-in can be switched on." (List only what's
   missing, the same way the app guard builds its message.) In `update_work_location`, call it
   after assignment when the PATCH touches any of `web_punch_enabled`, `web_punch_check_mode`,
   `lttd`, `lgtd` or `geo_fence_radius_mtrs`.
   - Clearing coordinates on a web-Geofence site that is enabled is refused the same way.
   - No coupling to the app's mode: a WifiAndGeofence app site may have web Geofence.
9. INFO log in `update_work_location` when `web_punch_enabled` or `web_punch_check_mode` changes
   (`"Web clock-in setting changed: tenant=%s work_location=%s enabled=%s mode=%s"`). WARNING
   at the 422 guard, with what's missing.
10. `_work_location_detail_out` and the list out include `web_punch_enabled` and `web_punch_check_mode`.
    `create_work_location` saves `web_punch_check_mode` when given.

### `modules/attendance/schemas.py`
11. The app-mode Literal on `WorkLocationIn` / `WorkLocationPatch` gains `"NoCheck"`.
12. `WorkLocationIn` gets `web_punch_check_mode: Literal["Geofence","NoCheck"] | None = None`
    (a setting, saved on create). `WorkLocationPatch` gets that plus `web_punch_enabled: bool | None = None`.
    Create does **not** take `web_punch_enabled`.
13. `WorkLocationOut` gets `web_punch_enabled: bool = False` and `web_punch_check_mode: str = "Geofence"`.
14. `PunchPolicyOut`:
    - `web_punch_allowed` default → `False`, with its comment updated to the rule;
    - add `web_check_mode: str | None = None`.

## Files
- `backend/app/services/punch_verification_service.py`
- `backend/app/modules/attendance/service.py`, `backend/app/modules/attendance/schemas.py`
- `backend/app/tests/modules/test_attendance.py`

## Acceptance criteria
- [x] **Policy:**
  - [x] no_shift, no_work_location, app OFF, and app ON with the box off all return `web_punch_allowed=false`;
  - [x] app ON with the box on returns true whatever the app mode (incl. WifiAndGeofence), with `web_check_mode` set;
  - [x] app NoCheck returns `can_punch_from_app=true` with both `requires_*` false.
- [x] **App punch:** NoCheck returns 200, `Unverified`, `raw.check_mode="NoCheck"`. Other modes are unchanged (existing tests pass).
- [x] **Web punch:**
  - [x] web NoCheck returns 200 `Unverified`;
  - [x] web Geofence is accepted (`Verified`) inside the fence, and refused `location_mismatch` outside it, `location_unavailable` with no fix, and `accuracy_too_coarse` above the threshold;
  - [x] a web punch with the box off or app OFF returns 403 with the new sentence, and the `ClockInRefused` audit row carries `web_block`;
  - [x] clock-out mirrors clock-in.
- [x] **Admin:**
  - [x] enabling app NoCheck with no coordinates or networks succeeds;
  - [x] web on + Geofence without coordinates returns 422, and web on + NoCheck without coordinates succeeds;
  - [x] clearing coordinates on an enabled web-Geofence site returns 422;
  - [x] `web_punch_check_mode="Wifi"` returns 422;
  - [x] create saves `web_punch_check_mode`;
  - [x] PATCHing another tenant's location returns 404.
- [x] Existing attendance tests pass, with any test that asserted the old web accept-as-Unverified updated.
- [x] `uv run pytest app/tests/modules/test_attendance.py` is green (throwaway pg:18; seed status masters per the usual recipe).

Implemented 13-Oct-26, uncommitted on `feature/gowtham_ClockInNoCheck` (top-level `hrms/`).
- On a throwaway postgres:18 (migrated with `upgrade heads`, status masters seeded), `test_attendance.py` + `test_attendance_dashboard.py` give 342 passed and 4 failed. The same 4 fail on `main` (2 holiday-calendar tests needing state/city seed rows, 2 dashboard tests). 23 new tests were added.
- `test_attendance_recompute.py` and `test_leave.py` give the same results as on `main`. Ruff is clean on the changed source; the 6 E741 hits in the test files were already on `main`.
- Test fixtures: new `app/tests/punch_sites.web_clock_location` (web on, NoCheck). `_assign_shift` and `_self_employee_on_shift_now` now attach such a site, because a web clock-in with no site is refused since this task. `_assign_shift(with_site=False)` gives no site. `_assign_shift_with_location` stays plain unless `web_clock=True`.
- Two tests that asserted the old rule were rewritten: web accepted as Unverified at a site that never opted in, and the policy's `web_punch_allowed=True` there.

Completed: 2026-10-13
