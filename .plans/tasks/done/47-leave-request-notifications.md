---
task: 47
title: Leave lifecycle notifications via the existing engagement module
status: done
depends_on: [44, 45]
---

# 47 — Leave lifecycle notifications via the existing engagement module

## Discussion

No generic in-app/notification framework exists in this codebase. What exists is
`backend/app/modules/engagement/service.py` — `send_text`, `send_template`, `send_email`, keyed
by `employee_id`, resolving message content from `TemplateMaster` rows (`template_masters`,
resolved by `(CDP, template_code)` at send time). This is the "existing HRMS notification
framework" the generic leave plan means when it says not to build a leave-specific mechanism —
reuse `send_template`, do not add a second notification pathway.

Read `backend/app/modules/engagement/service.py`'s `send_template` signature and
`backend/app/models/template_master.py` fully before writing this task's code — confirm exactly
how `var_questn_ids`/template variable interpolation works so the four leave events below
populate the right placeholders, and confirm whether `send_template` already handles the
"template not configured for this tenant" case gracefully (log-and-skip) or raises — this
task's calls must not fail the leave request transaction if a template is simply missing for a
given CDP. Wrap each notification call so a `send_template` failure is caught and logged, never
propagated as a 500 back to the employee/manager who just successfully applied/approved/
rejected/cancelled.

### Four events, four template codes

Following the pattern implied by existing `template_code` usage elsewhere in the codebase
(check how other modules name their codes — likely a short uppercase-with-underscores
convention):

| Event | Trigger point | Recipient | Suggested `template_code` |
| --- | --- | --- | --- |
| Submitted | end of [[44]]'s `POST /requests` (Pending case only — the auto-approved case fires the Approved template instead, not both) | The resolved approver (`approver_user_id`) | `LEAVE_REQUEST_SUBMITTED` |
| Approved | end of [[45]]'s approve endpoint | The applicant | `LEAVE_REQUEST_APPROVED` |
| Rejected | end of [[45]]'s reject endpoint | The applicant | `LEAVE_REQUEST_REJECTED` (include the rejection reason as a variable) |
| Cancelled | end of [[44]]'s (or a manager acting via [[45]]) cancel endpoint | The approver if the request had been `Approved`; otherwise no notification needed (nothing was ever actioned) | `LEAVE_REQUEST_CANCELLED` |

Seed these four `template_masters` rows (per-CDP, or a tenant-agnostic default row if the seed
convention elsewhere allows one — check `backend/scripts/seed_dev.py` for how existing
templates are seeded) with placeholder message bodies matching the generic plan's §29 copy:

```
Submitted (to approver): "New leave request from {{employee_name}}"
Approved (to employee):  "Your {{leave_type}} request from {{from_date}} to {{to_date}} has been approved."
Rejected (to employee):  "Your leave request has been rejected. Reason: {{reason}}"
Cancelled (to approver): "{{employee_name}} has cancelled their {{leave_type}} request for {{from_date}} to {{to_date}}."
```

## Files

- `backend/app/modules/leave/service.py` — one small `_notify_*` helper per event, called at the
  end of the relevant [[44]]/[[45]] function, each wrapped to swallow and log send failures
- `backend/scripts/seed_dev.py` (or wherever template seeding actually lives — confirm first) —
  the four new `template_masters` rows
- `backend/app/tests/modules/test_leave.py` — extended

## Tests

- Submitting a `requires_approval=true` request calls `send_template` once, addressed to the
  resolved approver, with the right template code — mock/spy on `engagement.service.send_template`
  rather than asserting a real message was sent (matches how this codebase likely already tests
  any engagement call sites elsewhere — check for a precedent before inventing a mocking style).
- Approve/reject/cancel each fire exactly one notification, to the right recipient.
- A `requires_approval=false` auto-approved request fires only the Approved notification, never
  a Submitted one.
- A missing/unconfigured template for a tenant does not raise — the request still succeeds and
  is queryable afterward.

## Acceptance criteria

- [x] All four lifecycle events notify through `engagement.service`, not a new mechanism.
- [x] A notification failure never rolls back or 500s the leave action that triggered it.
- [x] No notification fires twice for the same event (auto-approve fires Approved only once, not
      Submitted-then-Approved).

Completed: 2026-08-18
