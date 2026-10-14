---
task: 34
title: Employee clock card — wire MyAttendance.tsx to the real clock-in/out API
status: done
depends_on: [31]
---

# 34 — Employee clock card frontend

## Discussion

`frontend/src/dashboards/Employee/MyAttendance.tsx` already has the clock card markup — it is
explicitly marked mock in the file's own comment: *"TODO: replace with a real live/running timer
+ actual clock state once the attendance service exists — this is static mock content for now"*
(lines 66-69, predating this task). Task 31 is that service. This task wires the existing card to
it; it does **not** redesign the card — same layout, same Tailwind classes, same "CLOCKED OUT" /
"Clock in" visual language already in the file, per CLAUDE.md's frontend-styling rules (no new
`.module.css`, existing design tokens only).

Reference for behavior, not visuals: `docs/leave-and-attendance/attendance/employee-self-service.md
§2.1` — the three states (Not started / On the clock / Clocked out), and "the elapsed timer ticks
client-side from `worked_seconds_so_far`... the client does not poll."

## Files

### Edited

- `frontend/src/lib/api.ts` — add, grouped under a new `// ── Attendance: clock ──` banner near
  the existing `// ── Shifts: employee self-service ──` block:

  ```ts
  export type ShiftBrief = { name: string; start_time: string | null; end_time: string | null; time_zone?: string };

  export type ClockAction = {
    punch_id: number; punch_at: string; direction: "IN" | "OUT";
    is_within_geofence: boolean | null; attendance_date: string;
    shift: ShiftBrief | null; late_by_minutes: number;
    state: "clocked_in" | "clocked_out";
  };

  export type TodayAttendance = {
    attendance_date: string; day_type: string; attendance_status: string | null;
    state: "not_started" | "clocked_in" | "clocked_out";
    first_in_at: string | null; last_out_at: string | null;
    worked_seconds_so_far: number; shift: ShiftBrief | null;
    is_late: boolean; late_by_minutes: number;
  };

  export async function clockIn(): Promise<ClockAction> {
    const token = sessionStorage.getItem("token");
    const { ok, status, data } = await secureFetch<ClockAction>(
      "/api/v1/attendance/me/clock-in", { method: "POST", token, jsonBody: { punch_source: "Web" } },
    );
    if (!ok) throw new Error(status === 409 ? (data as { detail?: string })?.detail ?? "Already clocked in" : "Failed to clock in");
    return data;
  }

  export async function clockOut(): Promise<ClockAction> {
    // same shape, POST /api/v1/attendance/me/clock-out
  }

  export async function getTodayAttendance(): Promise<TodayAttendance> {
    // GET /api/v1/attendance/me/today
  }
  ```

  Follow `listMyShifts`/`getMyShiftForDate` immediately above this block as the exact style
  precedent (token retrieval, `secureFetch`, throw-on-`!ok`) — this file's established convention,
  not a new one.

- `frontend/src/dashboards/Employee/MyAttendance.tsx`:
  - Replace the hardcoded clock-card `<section>` (currently lines ~76-93: the static "CLOCKED OUT"
    badge, `00:00:00`, and the "Clock in" button with no `onClick`) with a new `ClockCard`
    component, colocated in this file next to the existing `TodayShiftLabel`:
    - On mount, `getTodayAttendance()`. Loading state: reuse this file's existing skeleton idiom
      (`animate-pulse` over the same card shape — see `TodayShiftLabel`'s loading span for the
      pattern this codebase already uses for inline loading text; here it's a whole card, so
      shimmer the badge/time/button placeholders, per the repo-wide shimmer-skeleton convention in
      CLAUDE.md — no spinner, no "Loading…" text).
    - Render badge text from `state`: `not_started` -> "CLOCKED OUT" (dot `bg-ink-300`, unchanged
      from today's static style), `clocked_in` -> "ON THE CLOCK" (consider a teal dot to
      distinguish from the clocked-out state — small, consistent tweak, not a redesign),
      `clocked_out` -> "CLOCKED OUT".
    - Elapsed time: client-side interval ticking from `worked_seconds_so_far` (captured at fetch
      time) + elapsed wall-clock since that fetch, formatted `HH:MM:SS` — matches the "ticks
      client-side... does not poll" rule. Stop ticking (freeze the last value) once `state !==
      "clocked_in"`.
    - Button: `state === "not_started" | "clocked_out"` -> "Clock in" calling `clockIn()`;
      `state === "clocked_in"` -> "Clock out" calling `clockOut()`. On either call: disable the
      button while in flight, then re-fetch `getTodayAttendance()` (simplest correct approach —
      the response of `clockIn`/`clockOut` itself already has everything needed, so an immediate
      re-fetch is optional; using the action response directly to update state avoids the extra
      round trip and is preferred if it doesn't complicate the component).
    - Errors (e.g. 409 "Already clocked in at 09:02"): show inline near the button using this
      file's existing toast/error convention (check `shell.tsx` or a sibling dashboard for the
      established inline-error pattern before inventing a new one — CLAUDE.md's "existing toast
      treatment" rule).
    - `In {time}` subtitle (currently hardcoded `"In 1:46 PM"`) becomes the real `first_in_at`
      formatted in the browser's locale, shown only when clocked in or clocked out today; hidden
      when `not_started`.

## Implementation notes (decided during execution)

- Removed a synchronous `setLoadError(false)` call from the top of the `load()` callback — it
  tripped the `react-hooks/set-state-in-effect` ESLint rule when `load()` was invoked directly
  from the mount effect. It was dead logic anyway: nothing in this component ever retries after
  a load error, so there was never a case needing the reset.
- Success toasts ("Clocked in — welcome back" / "Clocked out") use `react-toastify`, matching
  `ShiftScheduling.tsx`'s existing convention; the 409 "Already clocked in..." error renders in
  an inline banner, reusing `EmployeeHome.tsx`'s existing inline-error style exactly (same
  border/background/text colors) rather than inventing a new one.

## Acceptance criteria

- [x] Loading the My Attendance page shows a shimmer skeleton, then the real clock state — never
      a spinner or "Loading…" text.
- [x] Clocking in calls the real API, disables the button mid-flight, and updates to "On the
      clock" with a running timer that persists across a page refresh — manually verified in
      Chrome: clocked in (toast + badge + timer all updated), reloaded the page, state and
      `first_in_at` ("In 10:25 AM") were unchanged and the timer continued from the
      server-reported baseline.
- [x] Clocking out calls the real API and returns to "Clocked out" — manually verified (toast
      "Clocked out", badge and button reverted, timer reset to the final `worked_seconds_so_far`
      — floored to 0 whole minutes since the manual test session was under a minute, matching
      the backend's whole-minute granularity, not a bug).
- [x] `tsc --noEmit` and `eslint` both clean on the changed files (aside from one pre-existing,
      unrelated `no-unused-vars` warning on the `me` prop that predates this task).
- [x] The timer never polls the server — ticks from a client-side `setInterval` seeded by
      `worked_seconds_so_far`, confirmed by the refresh test above.
- [x] No new `.module.css` file; only Tailwind utility classes, matching the existing card.
- [x] Manually verified end-to-end in a real browser session (Chrome, logged in as the seeded
      `employee1@test.com` / subdomain `beta` employee): clock in, watch the timer run, refresh,
      confirm state survives, clock out, confirm it stops. The 409 duplicate-clock-in path is
      covered by task 31's backend tests; not re-driven manually since the UI itself prevents
      reaching that state via normal clicks (button flips to "Clock out" immediately on success).

Completed: 2026-08-18
