---
task: 38
title: Update the leave-and-attendance doc corpus to reflect what tasks 29-37 actually built
status: done
depends_on: [30, 33, 36, 37]
---

# 38 — Docs update

## Discussion

`docs/leave-and-attendance/attendance/*.md` and `docs/leave-and-attendance/shared/*.md` currently
describe clock-in/out and regularization as entirely **not built**. Tasks 29-37 build a
deliberately reduced slice of that design (see task 29 and 30's Discussion sections for the exact
list of cuts: no device ingestion, no batch job/`app/jobs/`, no leave-status integration, no
OnDuty/WFH/ShortLeave, no auto-absent, no overtime, no status_masters seeding, no register/
analytics KPI dashboards). Per CLAUDE.md's documentation rule and this corpus's own established
style (compare how task 13's and task 18's work was reconciled into `../shifts/gaps.md` and
`employee-self-service.md`'s "stale-fact fix" notes), update the docs to state plainly what's real
now versus what's still a documented gap — do not leave the corpus claiming this is unbuilt once
it isn't, and do not silently mark cut scope as "done."

## Files

### Edited

- `docs/leave-and-attendance/README.md` — update the persona/status table (§1.1) and the
  `Excluded from v1` table (§1.2) if any of tasks 29-37's scope cuts belong there (e.g. "auto-
  absent marking" and "the batch assembler / job runner" are now concretely deferred for this
  slice, not just abstractly unbuilt).

- `docs/leave-and-attendance/attendance/api-and-pages.md` — flip **Status** from "Not built" to
  "**Built**" for exactly the endpoints tasks 31-33 shipped (`/me/clock-in`, `/me/clock-out`,
  `/me/today`, `/me/daily`, `/me/requests`, `/requests` POST/cancel/attachment,
  `/requests` GET/`{id}`/approve/reject — both self- and manager/admin-scoped). Leave
  devices/register/analytics/lock/rebuild rows exactly as "Not built" — they remain untouched by
  this task set. Update §2's page tables (`myAttendance`, `regularizations` nav item) similarly.

- `docs/leave-and-attendance/attendance/assembler.md` — add a note (near the top, matching the
  existing "status" callout style already used in `api-and-pages.md`/`config-knobs.md`) pointing
  at task 30's `calendar_resolver_service.py` / `attendance_recompute_service.py` as **the reduced,
  event-driven implementation actually shipped** for clock-in/out and regularization, versus this
  document's own batch-job design — cross-reference both ways so a future reader lands on the
  right one for what they're trying to do (extend the real event-driven path vs. eventually build
  the full batch job).

- `docs/leave-and-attendance/attendance/employee-self-service.md` — remove/update the "What's
  still actually missing: the real clock-in/out backend... `MyAttendance.tsx`'s... remain 100%
  hardcoded mock UI" note (§ near the top) — it's no longer true after tasks 34-35. Follow the
  exact "stale-fact fix" correction style already used earlier in this same file for the shift-
  display reconciliation, rather than deleting the paragraph outright (this corpus's convention is
  to correct forward with a dated note, not silently rewrite history).

- `docs/leave-and-attendance/attendance/manager-approvals.md` — update §3 (Regularization inbox)
  from "No mockup designs this screen... blocks the manager surface" to note it's built per this
  task set, referencing `RegularizationInbox.tsx` (task 36) and the endpoint set (task 33).

- `docs/leave-and-attendance/attendance/gaps.md` — update gap #6 (no manager-facing inbox) to
  ✅-resolved style (matching how gap #18 is already marked resolved in this same file), scoped
  explicitly to `Regularization` — note `OnDuty`/`WFH`/`ShortLeave` requests still have no
  approval surface. Add a new gap entry (next available number, or clearly marked as an addendum
  if the 42-item numbering is considered closed) for: no scheduled job runner exists, so
  auto-absent marking and the full batch assembler remain unbuilt; the per-row recompute (task 30)
  is a deliberate, documented substitute, not a fix for that gap.

- `docs/leave-and-attendance/shared/implementation-structure.md` — update the Phase 3/4 endpoint
  table (§3) and the frontend file tables (§7.2, §7.3) to mark the shipped files/endpoints, per the
  same reconciliation style already used for the `AttendanceShifts.tsx`/`ShiftScheduling.tsx`
  corrections in that file.

- `docs/leave-and-attendance/attendance/config-knobs.md` — no change expected (the per-shift
  knobs this task set reads — `regularization_window_days`, `max_regularization_requests_per_month`
  — were already documented as shipped in §0); confirm during review that nothing here needs
  updating rather than skipping the file.

## Acceptance criteria

- [ ] Every doc file above accurately reflects tasks 29-37's actual shipped scope — verified by
      re-reading each edited section against the real `router.py`/`service.py`/frontend files, not
      copied from this task's own Discussion section (which was written before implementation).
- [ ] No doc claims something is built that isn't, and no doc still claims something is unbuilt
      that now is.
- [ ] The reduced-recompute-vs-batch-assembler architectural decision is cross-referenced from
      both `assembler.md` and wherever task 30's new service files live, so a future reader finds
      it from either direction.
- [ ] `docs/leave-and-attendance/attendance/gaps.md`'s gap #6 is marked resolved for
      `Regularization` specifically, with the remaining request types called out as still open.
- [ ] No change to `CLAUDE.md` — this corpus's own established pattern (tasks 17, 20) updates the
      `docs/leave-and-attendance/` tree directly rather than adding a top-level CLAUDE.md section.

Completed: 2026-08-18
