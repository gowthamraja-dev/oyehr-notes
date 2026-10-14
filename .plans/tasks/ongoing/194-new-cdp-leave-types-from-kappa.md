---
task: 194
title: Make Kappa's (ka) leave types and shifts the CDP 0 template that new CDPs inherit
status: ongoing
depends_on: []
---

# 194 — Make Kappa's (ka) leave types and shifts the CDP 0 template that new CDPs inherit

## Scope

When Super Admin creates a new organisation (CDP), it should start with **all of Kappa's leave
types and Kappa's shift configuration** (subdomain `ka`), including each shift's week-offs.
To get there, copy Kappa's set into **CDP 0**, the template that org creation already clones
from.

Built in `workspace-2/hrms` on branch `feature/gowtham_Cdp0LeaveShiftTemplate` (cut from
`origin/main` 2af9feb, upstream unset so a push can't go to main).

### How org creation clones (`backend/app/modules/admin_organizations/service.py`)

`create_organization` → `_clone_shift_and_leave_defaults` copies CDP 0's live shifts, live
leave types, live leave policies and their rules, and their `CareDeliveryProgramMaster`
assignments. Policy rules are remapped by matching the template's leave-type ids. Once CDP 0
holds Kappa's set, every new org picks it up. Precedent: `scripts/seed_cdp0_payroll_groups.py`,
which copied Acme's (CDP 1) Payroll Groups into CDP 0 the same way. After this, the standard
set is curated by editing CDP 0, with no deploy needed.

### Data on shared hrms-dev (verified 07-Oct-26)

Kappa = CDP **121862**, host `ka`. It's a real tenant (`is_own = false`), so the script
resolves it by host and never by id.

**Leave types** (matched by `code`, unique per CDP):

| code | CDP 0 today | Kappa | Action |
|---|---|---|---|
| CL | identical | — | none |
| SICK | order 0, no colour | order 2, `#e06500` | update in place (id 1972) |
| COF | order 0, no colour | order 4, `#7c06a7` | update in place (id 1971) |
| EL / ML / PL / LOP | missing | EL paid, max 3 consecutive, 2 days notice · ML Female, document required, 30 days notice · PL Male, 30 days notice · LOP unpaid, no approval | insert |

Rows are updated in place, never deleted and re-inserted, because CDP 0's DEFAULT policy CL
rule points at id 1970. Leave policies are already the same in both CDPs (DEFAULT, one CL rule:
Yearly 12, Pre, max 12, prorated). **No policy changes.**

**Shifts**: remove the old ones and add Kappa's.

| CDP 0 today | Kappa (live) |
|---|---|
| MOR Morning 09–18, flexible, no week-offs (id 1553) → **archive** | NIT Night 18:00–03:00, night, flexible, 90-min break, `#9d00a8`, week-offs Sat+Sun → **insert** |
| GEN General 09–18, no policy settings, no week-offs (id 1554) → **archive** | GEN General 09–18, 60-min break, grace 0/0, overtime tracking off, week-offs Sat+Sun → **insert** |
| Verify-Night (id 1552), already archived → untouched | Verify-Night, archived → not copied |

No `employee_shift_details` or `employee_attendance_details` rows reference CDP 0's shifts or
leave types.

### Change

1. **`backend/scripts/seed_cdp0_leave_shift_defaults.py`** (new; dry run by default,
   `--apply` to write).
   - **Leave types**: insert missing codes and update differing ones in place. Codes that
     only exist in CDP 0 are reported and left alone.
   - **Shifts**: a live CDP 0 shift identical to a Kappa shift is kept. "Identical" means
     every cloned column (name, code, color, start/end time, policy_config, is_active,
     effctv_dt, trmntn_dt) and its week-off set all match. Every other live CDP 0 shift is
     **soft-deleted** (`archive = true`, `is_active = false`, `archived_by_id`,
     `archived_at`). Every Kappa shift without an identical match is inserted together with
     its week-offs.
   - Idempotent: a second run writes nothing.
2. **`_clone_shift_and_leave_defaults`**:
   - skips archived template shifts and leave types (it used to copy them, archived ones included);
   - **now also clones each shift's week-offs** (`shift_week_off_details`). Before this, new
     orgs got shifts with no week-offs at all.
   - Shifts are now inserted one at a time with `RETURNING id`, to get the old→new id map.
3. Tests:
   - `test_admin_organizations.py::test_new_organization_clones_live_template_shifts_with_week_offs`
   - `test_seed_cdp0_leave_shift_defaults.py`: insert vs. update in place, archive vs. keep,
     week-offs copied, source CDP untouched, second run is a no-op.

### Not in scope

- Existing CDPs (Kappa and every org created before this) are not touched. A backfill would be
  its own task.
- Leave policies. CDP 0's DEFAULT still accrues CL only, the same as Kappa's.
- Task 186's shelved `date_rule` column.

## Files

- `backend/scripts/seed_cdp0_leave_shift_defaults.py` — new
- `backend/app/modules/admin_organizations/service.py` — `_clone_shift_and_leave_defaults`
- `backend/app/tests/modules/test_admin_organizations.py` — new test
- `backend/app/tests/modules/test_seed_cdp0_leave_shift_defaults.py` — new

## Acceptance criteria

- [x] Dry run on hrms-dev prints: CL unchanged; SICK/COF update `display_order` and `color_code`;
      EL/ML/PL/LOP insert; MOR + GEN (1553/1554) archive; NIT + GEN insert with Sat+Sun
      week-offs. 10 changes in total, nothing written.
- [x] `--apply` on hrms-dev, run 08-Oct-26 with the user's OK: 10 changes. CDP 0 now has 7
      live leave types: CL 1970, SICK 1972, EL 31652, COF 1971, ML 31653, PL 31654, LOP 31655.
      It has 2 live shifts, NIT 28565 and GEN 28566, both with Sat+Sun week-offs; MOR 1553 and
      GEN 1554 are archived. The DEFAULT CL rule (551) is intact, and a re-run reports nothing
      to do.
- [x] New tests pass. Archived template shifts and leave types aren't cloned, and a cloned
      shift carries its week-offs.
- [x] Full `test_admin_organizations.py` + the new script tests: 49 passed, 3 failed. The 3
      failures (`test_create_organization_end_to_end`, `test_list_admins_requires_super_admin`,
      `test_add_admin_requires_super_admin`) are a login-response `KeyError` on
      `access_token`/`tenant_id`, and they fail identically on clean `origin/main`, so they
      predate this task.
- [ ] Manual check (leave to the user): create an org in Super Admin. HR Admin → Leave shows
      CL, SICK, EL, COF, ML, PL, LOP in that order; Shifts shows Night and General with Sat+Sun
      week-offs.
