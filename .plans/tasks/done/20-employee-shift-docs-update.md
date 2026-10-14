---
task: 20
title: "Docs: record the employee self-service shift endpoints and the remaining deferred items"
status: done
depends_on: [18, 19]
---

# 20 — Docs update for employee-facing shift self-service

## Scope

Docs-only, no code — same shape as `.plans/tasks/done/17-shift-assignment-docs-update.md`, which
this follows up on. Brings `docs/leave-and-attendance/shifts/` and the attendance self-service doc
back in sync with tasks 18-19, and formally records the two items from `.design/prompts/Shift
Assignment — Manager & Employee UI Implementation Prompt.md` that remain deliberately unbuilt.

## Files

### `docs/leave-and-attendance/shifts/api-and-pages.md`

- §3 "Endpoint index" — add a new `S` (self) row group for `GET /shifts/me` and
  `GET /shifts/me/{date}` (task 18), noting the per-date-assignment-wins-over-standing-detail
  resolution rule and pointing at `gaps.md` #43 for why that resolution rule exists (two unsynced
  tables) rather than repeating the explanation.
- §2 "Pages" — add the Employee Portal row: view key/screen name from whatever task 19 actually
  wires up (check `frontend/src/dashboards/Employee/index.tsx`'s view keys once task 19 lands —
  likely `home` for the Today's Shift card, possibly `attendance` too if task 19 also touched
  `MyAttendance.tsx`'s header), status "live, built", primary endpoint `GET /shifts/me`.
- §6 "Deferred" table — add a row: "Leave-conflict warning on shift assignment" (design prompt
  §10) — why: no `leave_request`-type model exists in this codebase; detail: see
  `docs/leave-and-attendance/leave/gaps.md`.

### `docs/leave-and-attendance/shifts/gaps.md`

Add a new numbered item (continue the global sequence past #43 — check `../README.md` for the
current max number across the whole corpus before picking the next number, per this file's own
header rule: "Gap numbers are global across the whole leave-and-attendance corpus and are never
renumbered").

New gap content: task 18's employee self-service endpoints resolve "the employee's shift for
date X" with a **local, endpoint-scoped** precedence rule (per-date assignment wins over standing
detail) that is *not* the same thing as resolving gap #43 — the attendance assembler still only
reads `employee_shift_details` and is untouched by task 18. State plainly: an employee's
self-service "Today's Shift" card and the attendance assembler's expected-start/late-calculation
can now show *different* shifts for the same day, if a manager assigned a per-date override that
the assembler doesn't know about. This is the same underlying gap as #43, viewed from a third
consumer — do not describe it as newly discovered, cross-reference #43 directly.

### `docs/leave-and-attendance/attendance/employee-self-service.md`

- Fix the stale prerequisite note in the doc's header: it currently states no `hr_employee`
  dashboard exists and the loader is commented out in `registry.ts`. As of task 19 (and in fact
  already true before it — verify via `git log frontend/src/dashboards/registry.ts` for when the
  `employee_portal` line was added), this is no longer accurate: `frontend/src/dashboards/
  Employee/` is a real, registered `RoleDashboard` at `registry.ts`'s `employee_portal` entry.
  Correct the prerequisite note rather than deleting it outright — state what's actually still
  missing (the real clock-in/out backend, per §2.1, remains unbuilt) so a future reader doesn't
  have to re-derive that from the code.
- §2 "My Attendance" header subtitle example (*"July 2026 · General shift (09:00 – 18:00)"*) —
  confirm it still says "read from the active `employee_shift_details` row, not hardcoded" and
  update that sentence if task 18/19 changed which table/endpoint actually backs it (it now goes
  through `GET /shifts/me`'s resolution rule, which *may* prefer a per-date
  `employee_shift_assignments` row over `employee_shift_details` — see gaps.md's new entry above).

## Explicitly out of scope

No code changes. If reading the actual task 18/19 diffs turns up a mismatch between what those
tasks' own files say they'll do and what they actually did, describe what was actually built —
this doc-update task is not a re-review of tasks 18/19's correctness, just keeping the docs
honest about final reality (same principle task 17 followed for tasks 13-16).

## Acceptance criteria

- [x] `docs/leave-and-attendance/shifts/api-and-pages.md` lists the two new self-service
      endpoints with their resolution rule (new §2.4 page row, §3.3 endpoint table).
- [x] `docs/leave-and-attendance/shifts/gaps.md` has a new numbered entry (#44) describing the
      self-service-vs-assembler shift-resolution split, cross-referencing #43. (#44 was the
      correct next number — #43 was the highest across the whole corpus, confirmed by scanning
      every `gaps.md` file's numbered headings.)
- [x] `docs/leave-and-attendance/attendance/employee-self-service.md`'s stale "no hr_employee
      dashboard exists" note is corrected — replaced with what's actually still missing (the
      clock-in/out backend) — and its §2 header-subtitle claim is corrected to match what task 19
      actually built (a static month label + a separate resolved-shift line in `MyAttendance.tsx`,
      not a computed subtitle string).
- [x] The leave-conflict-on-assign deferral (design prompt §10) is recorded in
      `shifts/api-and-pages.md`'s Deferred table — confirmed it wasn't already covered in
      `leave/gaps.md` (grepped for "shift"/"conflict" there — no hit) before adding it here.

Completed: 2026-08-17
