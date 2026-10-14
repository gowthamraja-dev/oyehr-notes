---
task: 160
title: Maternity Leave shown to male employee NT42 (Next Life) — gender filter gaps
status: ongoing
depends_on: []
---

# 160 — Maternity Leave shown to a male employee (NT42, Next Life)

**Where:** backend + web frontend in the top-level `hrms/` clone (`feature/gowtham_LeaveMasters`,
where the leave-policy code lives). The mobile fix goes in `employeeapp/`.

## Report (30-Sep-26)
Employee **NT42** in the **Next Life** tenant is male but has (sees) **Maternity Leave**.

## What was found (read-only look at the shared hrms-dev DB, 30-Sep-26)
- NT42 = `employee_masters.id 81187` (gowtham raja), corp *Next Life Line*, CDP **19571** (Next Life).
  **`gndr = 'M'`**. Every other employee in that CDP uses the full word: `Male` ×12, `Female` ×6,
  `M` ×1 (only him).
- Maternity Leave = `leave_type_masters.id 24634`, code `ML`, `gender_applicable = 'Female'`,
  active, not archived.
- He has **no ML ledger rows and no ML leave requests.** Nothing was ever credited or applied,
  so this is a *visibility* bug, not a data bug.
- Every backend gender check compares values case-insensitively for **exact equality**
  (`"female"` vs `"m"`), so they exclude him correctly:
  `leave_accrual_service.py` L270 / `_is_gender_applicable` L461 (accrual + first credit),
  `assignment_service.py` ~L486–493 (`/leave/me/policy` drops other-gender types) and
  `service.py` ~L854 (apply rejects).
- The web **My Leave** apply picker (`MyLeave.tsx` `ApplyLeaveForm`, ~L382) narrows types to
  `/leave/me/policy`'s covered rules. **But** it is loaded with `getMyLeavePolicy().catch(() => null)`
  (~L625), and when that is null the picker falls back to **every** active leave type.
- The **mobile app** apply screen (`employeeapp/.../LeaveScreen.js` L39 →
  `ApplyLeaveViewModel.getLeaveTypes()` → `GET /leave/types`, `EndPoints.js` L38) lists **all**
  of the tenant's leave types, with no policy or gender filtering. That is the most likely place
  he saw ML.

## Scope
1. **Confirm where it shows.** Ask the user, or reproduce as NT42, which screen shows ML:
   mobile apply picker, web My Leave apply picker, web balances / "Leave rules" card, the Home
   apply modal, or HR's view of his profile (`/leave/employees/{id}/balances`,
   `EmployeeLeaveTab`). Fix that path first, then close the others below.
2. **Mobile app:** the apply picker must offer only the types the employee's policy covers.
   Source them from `GET /leave/me/policy` (`rules[].covered`), like web does, not from
   `/leave/types`. Follow the `hrms-mobile-api-integration` skill contract.
3. **Web fallback:** when `/leave/me/policy` fails, don't widen the picker to every type. Show an
   error or empty state instead (or retry). Apply would be rejected by the server anyway.
4. **Gender value normalisation.** `employee_masters.gndr` holds both `M` and `Male` (the
   nhforms Registration/Edit Profile forms and imports can write either). `leave_type_masters.gender_applicable`
   is `Male|Female|Other`. With exact matching, a **Male-only** type (e.g. Paternity) would be
   wrongly *hidden* from NT42 today. Add one shared helper, e.g.
   `normalise_gender("M"|"m"|"Male"|"male") -> "Male"` (`F`→`Female`, `O`→`Other`), and use it in
   all four backend checks above instead of the ad-hoc `.lower()`/`.casefold()` comparisons.
   Decide with the user whether to also backfill `gndr = 'M'` → `'Male'` on the shared DB. That
   is a data write, so get their go-ahead first, and find where `'M'` is written so it stops.
5. Check the other gender-restricted type: `ERL` (id 14691) is marked `Female` but is archived,
   so it is probably misconfigured test data. Mention it to the user, don't change it.

**Out of scope:** the leave-type admin UI (task 159) and `corp_master_id` (task 158).

## Files
- `hrms/backend/app/services/leave_accrual_service.py` (L270, `_is_gender_applicable`)
- `hrms/backend/app/modules/leave/assignment_service.py` (~L486–493)
- `hrms/backend/app/modules/leave/service.py` (~L854 apply gate)
- New shared helper (e.g. `hrms/backend/app/services/gender.py`, or next to the leave vocabularies)
- `hrms/frontend/src/dashboards/Employee/MyLeave.tsx` (~L382, ~L625)
- `employeeapp/src/screens/LeaveScreen/LeaveScreen.js`, `.../ApplyLeave/ApplyLeaveViewModel.js`,
  `.../ApplyLeave/ApplyLeaveService.js`, `employeeapp/src/api/EndPoints.js`
- Tests: `hrms/backend/app/tests/modules/test_leave_my_policy.py`, `test_leave_accrual_scenarios.py`, `test_leave.py`

## Acceptance criteria
- [x] The screen where NT42 saw ML is identified: the HR policy-resolution explainer (see Root cause).
- [x] As NT42 (`gndr='M'`), ML is not shown as covered in HR's policy-resolution panel
      (EmployeeLeaveTab, Policy Assignments), nor in his own pickers, balances or leave-rules card. Applying for ML directly via the API returns the gender rejection.
- [x] A `Male`-only type is shown to, accrues for and can be applied for by an employee whose
      `gndr` is `M`, `m` or `Male`, and never by a `Female`/`F` employee. Tests cover
      `M`/`Male`/`F`/`Female`/NULL in accrual, `/me/policy` and apply.
- [x] If `/leave/me/policy` fails on web, the picker does not list every type (it is empty, with an error line; Submit stays disabled because no type can be picked).
- [ ] Any `gndr` backfill on the shared DB was run only after the user approved it.
- [x] `uv run pytest app/tests/modules/test_leave*.py` passes (with test_employees + test_gender: 413 passed; `test_update_employee_full_details` updated to expect `Female`; `test_audit_action_updated_on_patch` flaked once while a concurrent full run shared the DB, passes on rerun). `npx tsc --noEmit` and lint are clean.

## Root cause (confirmed 30-Sep-26, read-only)
- NT42 (`employee_masters.id 81187`, `user_id 91644`) is **not** an admin: `users.is_admin = false`,
  and his only role in CDP 19571 is **Employee** (role 2). So `GET /leave/types` limits him to the
  types he has ledger rows for (`service.list_leave_types` L271-291), and it can't return ML. The
  mobile picker and the web fallback **can't** be where he saw it.
- **The leak is the HR-side policy explainer.**
  `GET /leave/employees/{id}/policy-resolution` → `assignment_service.explain_employee_policy`
  (L424-470) lists **every live leave type** and marks it `covered` when the winning policy has a
  rule for it. There is **no gender check**, and `resolution.explain()` doesn't filter by gender
  either. The endpoint feeds `PolicyResolutionPanel`, shown on the employee's Leave tab
  (`shared/EmployeeLeaveTab.tsx`) and in Policy Assignments' "check an employee" panel. So HR
  opening NT42 sees **Maternity Leave · covered** with its rule.
- Where it **is** filtered: `/leave/me/policy` (`get_my_policy` L484-495), accrual
  (`leave_accrual_service` L270, `_is_gender_applicable`) and the apply gate (`service.validate_gender`
  L853-861). His ledger and requests have no ML, so nothing was credited or applied.
- The `gndr = 'M'` vs `'Male'` mismatch is a **separate, latent bug**. With exact matching,
  Male-only types (e.g. Paternity) are wrongly hidden from him, and he would never accrue them.

## Implementation plan
Order: 1 → 2 → 3 (backend + tests in one commit), then 4, then the optional 5–6.

### 1. Shared gender helper: new `hrms/backend/app/services/gender.py`
It imports nothing from `app.modules`, so there is no import cycle with `leave_accrual_service`.
```python
GENDERS: tuple[str, ...] = ("Male", "Female", "Other")
_ALIASES = {"m": "Male", "male": "Male", "f": "Female", "female": "Female", "o": "Other", "other": "Other"}
def normalise_gender(value: str | None) -> str | None:  # strip + casefold lookup; unknown/blank -> None
def gender_applies(required: str | None, gndr: str | None) -> bool:
    return required is None or (normalise_gender(gndr) is not None and normalise_gender(gndr) == normalise_gender(required))
```
Unknown values map to `None`, which excludes them from gender-restricted types, as NULL does
today. `leave/schemas.py` L8: `GENDERS_APPLICABLE = set(GENDERS)`.

### 2. Use it everywhere a gender restriction is checked
- **The fix for the report:** `assignment_service.explain_employee_policy`. Leave types whose
  `gender_applicable` doesn't apply to the employee are not shown as covered. **Recommended:**
  keep them in the list, marked not applicable, by adding
  `not_applicable_reason: str | None` (e.g. "Female only") to `ResolutionRuleOut`. This tells HR
  why the type is missing. The alternative is to drop them, as `/me/policy` does. Confirm with
  the user. Also filter `resolution.explain()`'s `details` the same way, so any other caller
  inherits it.
- `leave_accrual_service.py` L270-273 and `_is_gender_applicable` L461-464 → `gender_applies(...)`.
- `assignment_service.get_my_policy` L486-493 → `gender_applies(lt.gender_applicable, employee.gndr)`.
- `service.validate_gender` L853-861 → `if gender_applies(...): return`. Keep the WARNING log and the 422.
- `grep -rn gndr app` finds no other gender comparisons.

### 3. Frontend for the explainer
- `lib/api.ts`: add `not_applicable_reason` to the resolution rule type.
- `shared/PolicyResolutionPanel.tsx`: render a not-applicable type as a muted row, e.g.
  "Maternity Leave · Not applicable (Female only)", instead of covered / not covered.

### 4. Tests
- `app/tests/services/test_gender.py` (new): `test_normalise_gender`, parametrized
  (M/m/" Male "/male → Male; F/Female → Female; O/other → Other; None/""/"X" → None), and
  `test_gender_applies`.
- `test_leave_policy_assignments.py` (explainer): `test_explainer_marks_other_gender_type_not_applicable`.
  A male employee with `gndr='M'` whose policy has an ML (Female-only) rule gets ML marked not
  applicable and not covered. A female employee still sees it covered.
- `test_leave.py`, next to `test_validate_gender` (~L1191):
  `test_validate_gender_normalises_short_codes`, parametrized. A Male-only type passes for
  M/m/Male and rejects F/Female/None; a Female-only type does the reverse.
- `test_leave_my_policy.py`: `test_my_policy_gender_filter_normalises_short_codes` (gndr
  M/Male/F/Female/None; Male-only PL, Female-only ML, unrestricted CL).
- `test_leave_accrual_scenarios.py`: `test_gender_restricted_type_accrues_only_for_matching_gender`
  (Male-only type credits M/Male, not F/None), and `test_first_credit_respects_normalised_gender`
  (OnJoining).

### 5. Stop writing short codes (recommended, small)
- `app/modules/employee_import/service.py` L325 stores the spreadsheet cell as it is. This is the
  only in-app writer that can produce `'M'`. nhforms Registration doesn't map gender, and the web
  profile select offers only Male/Female/Other. Normalise the value there, and add a row error
  for unmappable values ("Unrecognised gender 'X' (use Male/Female/Other)"). Add
  `test_direct_import_normalises_gender`.
- `employees/schemas.py` L129 `EmployeeSelfPatch.gndr`: add a `field_validator` that normalises
  the value and rejects anything outside `GENDERS`. Add `test_self_patch_normalises_gender`.
- NT42 has `created_by_id = NULL` (created 29-Sep-26 19:14), so it was probably a direct or
  scripted write, not the UI.

### 6. Optional hardening (not the cause, separate commits)
- Web `MyLeave.tsx` L382: when `policy === null`, show an error and disable submit instead of
  falling back to every type.
- Mobile `employeeapp`: source the apply picker from `GET /leave/me/policy` (`rules[].covered`)
  instead of `/leave/types`. Add `LEAVE.POLICY` in `EndPoints.js`, `getMyPolicy` in
  `ApplyLeaveService.js`, and map to `{id: leave_type_master_id, name}` in
  `ApplyLeaveViewModel.getLeaveTypes()`. Return `[]` on error.

### 7. Data (only with the user's approval)
```sql
-- Q1 (read-only) gndr variants per tenant
SELECT c.care_delivery_program_master_id AS cdp, e.gndr, count(*)
FROM employee_masters e JOIN corp_masters c ON c.id = e.corp_master_id
WHERE e.archive IS NOT TRUE GROUP BY 1, 2 ORDER BY 1, 2;
-- Optional backfill: run in a transaction, check the count against Q1, then COMMIT
BEGIN;
UPDATE employee_masters SET gndr = CASE lower(trim(gndr)) WHEN 'm' THEN 'Male' WHEN 'male' THEN 'Male'
  WHEN 'f' THEN 'Female' WHEN 'female' THEN 'Female' WHEN 'o' THEN 'Other' WHEN 'other' THEN 'Other' END, updated_at = now()
WHERE lower(trim(gndr)) IN ('m','male','f','female','o','other') AND gndr NOT IN ('Male','Female','Other');
```

### Risks
- **Male-only types start to apply.** Once values are normalised, `M` employees start seeing,
  accruing and being allowed to apply for Male-only types. The next accrual and first-credit
  sweeps catch up on missed credits. Tell HR.
- **Explainer response shape.** It gains one optional field, so existing clients are unaffected.

## Progress (30-Sep-26)
**Done (uncommitted, in `hrms/` on `feature/gowtham_LeaveMasters`):**
- `app/services/gender.py`: `GENDERS`, `normalise_gender`, `gender_applies`. `leave/schemas.py`
  `GENDERS_APPLICABLE = set(GENDERS)`.
- `gender_applies` is used in accrual (`process` loop + `_is_gender_applicable`), `validate_gender`,
  `get_my_policy`, and `resolution.explain()`. Its `details` now drop other-gender rules, which
  fixes the HR explainer at the source.
- The explainer returns `not_applicable_reason` ("Female only"). `PolicyResolutionPanel` renders
  such a row muted as "Not applicable (Female only)" and leaves it out of the "not covered" count.
- **A second writer of short codes was found:** the HR **Edit Employee modal**
  (`shared/EditEmployeeModal.tsx`, which came in with `main`'s `c618a56`) sent `M`/`F`/`O`, while
  My Profile sends full words. The modal now sends full words and maps legacy codes on load.
  Before this, a stored `Male` showed as "Not set", and saving then wiped it to NULL.
- `EmployeePatch` / `EmployeeSelfPatch` normalise `gndr` and return 422 for an unmappable value.
  The bulk import normalises too and reports a row error for unrecognised values.
- NT42 itself: `updated_at == created_at`, so its `M` was written at creation, not by the modal.
- Docs updated: `gaps.md` #34 (now resolved), `ledger.md` rule 3 / accrual skip,
  `vocabularies.md`.
- Tests added: `tests/services/test_gender.py`,
  `test_explainer_marks_other_gender_types_not_applicable`,
  `test_validate_gender_normalises_short_codes`, `test_my_policy_gender_filter_normalises_short_codes`,
  `test_gender_restricted_type_accrues_only_for_matching_gender`,
  `test_first_credit_respects_normalised_gender`, `test_commit_normalises_gender_and_rejects_unrecognised`,
  `test_update_employee_normalises_gender`, `test_update_employee_rejects_unknown_gender`.

**Pre-existing failures, not caused by this task:** `test_employee_import.py::test_commit_creates_employees_when_all_rows_valid`
and `::test_commit_provisions_a_real_login_for_each_imported_employee`. The import now requires
Employee ID and Email (from `main`), and those tests don't send them.

**Shared-DB data (Q1, read-only):** 22 non-archived employees store short codes (`M` ×15 in 4
tenants, `F` ×7 in 3). Matching now handles them. The backfill in §7 stays optional and needs
the user's go-ahead.

**Web fallback done** (`MyLeave.tsx` `ApplyLeaveForm`). **Not done (optional §6):** the mobile picker switch to `/leave/me/policy`. It didn't cause this bug.
