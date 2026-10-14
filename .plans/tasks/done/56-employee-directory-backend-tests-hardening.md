---
task: 56
title: Employee Directory backend — cross-cutting tests hardening
status: done
depends_on: [52, 53, 54, 55]
---

# 56 — Employee Directory backend — cross-cutting tests hardening

## Discussion

[[52]]–[[55]] each specify their own unit-level tests inline. This task is the sweep pass that
runs after all four land together, mirroring how the leave-request arc closed with a dedicated
[[48-leave-request-tests-hardening]] and the attendance/regularization arc with
[[37-attendance-clock-regularization-tests-hardening]]: catch interaction bugs between the pieces
that per-task unit tests wouldn't, and confirm nothing upstream regressed.

Specifically verify:

- **Full permission sweep across the new surface**: every new route from [[52]]/[[53]]/[[54]]/
  [[55]], parametrized over {unauthenticated, wrong-CDP token, authenticated-but-not-a-manager-
  of-the-target, admin, manager-of-the-target}, matching the `test_shifts.py`-style parametrized
  sweep other arcs in this codebase already use — don't hand-roll a bespoke shape here.
- **Filter + pagination interaction**: applying [[52]]'s `status="On Leave"` filter together with
  [[53]]'s `headcount.on_leave` count on the same seeded data returns consistent numbers — the
  list filter and the aggregate must agree because they're meant to share the same predicate.
  Add one test that seeds a mixed set (active/inactive/on-leave/mid-leave/past-leave employees)
  and asserts the list endpoint's `On Leave` count equals `headcount.on_leave`.
- **[[54]]'s attendance route + [[52]]'s directory list stay independently CDP-scoped** — a
  manager who can see an employee in the directory list must also be able to view their
  attendance (if a direct report) or correctly get `403` (if not) — i.e. the directory's
  CDP-wide visibility and the attendance route's direct-reports-only visibility are two different,
  intentionally different scopes; add a test that asserts both are true simultaneously for the
  same employee (visible in directory, `403` on attendance) so a future change doesn't
  accidentally conflate the two.
- **[[55]]'s upload_image reuse**: confirm the existing `test_encryption.py`-documented exclusion
  of multipart routes from the encrypted round-trip test correctly covers the new
  `POST /employees/{id}/documents` route (add it to whatever list/pattern that test file uses to
  identify multipart exclusions, if it's an explicit list rather than automatic detection).
- **Full existing suite still green**: run `uv run pytest` for the whole backend after all four
  land and confirm zero regressions outside this arc — note any pre-existing unrelated failures
  (there is recent precedent for a handful of pre-existing failures in `test_admin_organizations.py`
  and `test_engagement_email.py` unrelated to any single feature arc; if the same ones reappear
  unchanged, note them as pre-existing rather than treating them as this task's regressions —
  if new ones appear, they are this task's problem).

## Files

- `backend/app/tests/modules/test_employees.py`
- `backend/app/tests/modules/test_attendance.py`
- `backend/app/tests/modules/test_encryption.py` (only if it needs the new multipart route added
  to an explicit exclusion list)

## Acceptance criteria

- [x] Every route added across [[52]]–[[55]] has an explicit 401/403/404-cross-tenant test, not
      just a happy-path test.
- [x] The "on leave" predicate is proven consistent between the list filter and the headcount
      aggregate on the same data, not just independently plausible.
- [x] `uv run pytest` run in full after this task, with a note in the completion record of any
      pre-existing (not newly introduced) failures observed.

## Completion notes

- **Gap found and closed**: [[53]]'s six new metadata/aggregate GET routes (`/departments`,
  `/employment-statuses`, `/reporting-managers`, `/headcount`, `/roles`, `/organization`) had
  zero 401 coverage — each of that task's tests started from an authenticated call. Added a
  `test_shifts.py`-style parametrized sweep (`_METADATA_ENDPOINTS`) asserting 401 unauthenticated
  and 200 for any authenticated CDP member (these routes are intentionally *not*
  manager-gated — same permission as viewing the directory at all, per [[52]]'s own "no separate
  manager endpoint" decision). [[52]]'s list, [[54]]'s attendance routes, and [[55]]'s documents
  routes already had explicit 401/403/404 coverage from their own unit tasks — verified, not
  re-added.
- **On-leave consistency**: added
  `test_on_leave_predicate_consistent_between_list_filter_and_headcount`, seeding a mixed set
  (active / inactive / currently-on-leave / pending-leave / past-leave) and asserting
  `list_employees(status="On Leave").pagination.total == get_headcount().on_leave == 1` on the
  same data — proves `_on_leave_today_subquery()` is genuinely shared, not just independently
  correct in each endpoint's own isolated test.
- **Independent-scope test**: added
  `test_directory_list_and_attendance_view_are_independently_scoped` — a manager sees a
  non-report in the CDP-wide directory list but gets `403` viewing that same employee's
  attendance (direct-reports-only), proving the two intentionally different scopes don't get
  conflated.
- **Encryption exclusion**: confirmed `test_encryption.py` has no explicit multipart-route
  exclusion list to update — `EncryptedRoute` exclusion is automatic by construction (a route is
  only encrypted if registered on a router built with `route_class=EncryptedRoute`; [[55]]'s
  `POST /employees/{id}/documents` lives on the plain `_upload_router`, so it was never in scope
  for encryption in the first place). No change needed to `test_encryption.py`.
- Full `uv run pytest`: **510 passed, 3 pre-existing failures** (`test_engagement_email.py::
  test_send_email_ok`, `test_engagement_email.py::test_send_email_resolves_template_variables`,
  `test_leave.py::test_audit_written_on_success_and_not_on_rejection`) — same three seen before
  any of [[52]]–[[56]] started (confirmed via `git stash` during [[52]]), unrelated to this arc.
  Zero new failures.

Completed: 2026-08-19
