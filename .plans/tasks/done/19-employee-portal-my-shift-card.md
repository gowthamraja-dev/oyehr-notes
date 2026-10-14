---
task: 19
title: "Employee Portal: Today's Shift card + Upcoming shifts, wired to the real API"
status: done
depends_on: [18]
---

# 19 — Employee Portal: Today's Shift card + Upcoming shifts

## Scope

Implements `.design/prompts/Shift Assignment — Manager & Employee UI Implementation Prompt.md`
§11-13 ("Employee Shift Screen", "Today's Shift Card", "Employee Shift Information") using
task 18's `GET /api/v1/shifts/me` / `GET /api/v1/shifts/me/{date}`.

**Current state (confirmed by reading the files):** `frontend/src/dashboards/Employee/` is a real,
registered `RoleDashboard` (`registry.ts` line 10: `employee_portal: () =>
import("./Employee").then(m => m.hrEmployeeDashboard)`) — it is live, not a stub. But every
screen inside it is 100% hardcoded mock data, including the one shift-shaped string that exists
today: `frontend/src/dashboards/Employee/index.tsx` line 52,
`subtitle: "July 2026 · Morning shift (09:00 – 17:30)"`, with a `TODO` comment right above it
saying to replace it "once schedule data exists" — it now does (task 18).

## Explicitly out of scope

- The clock-in/out control (`MyAttendance.tsx`'s "CLOCKED OUT" / "Clock in" button, `00:00:00`
  timer) is **also** 100% mock — there is no `attendance_punch_details` model or endpoint in this
  codebase yet (confirmed: no punch-related files under `backend/app/models/` or
  `backend/app/modules/attendance/`). Do not wire the clock button to anything real and do not
  invent a punch API as a side effect of this task — that belongs to whichever task eventually
  builds `docs/leave-and-attendance/attendance/employee-self-service.md`'s §2.1 clock card. Leave
  `MyAttendance.tsx`'s clock section exactly as-is.
- Leave balance, payslip, and other `EmployeeHome.tsx` mock tiles — untouched.
- `docs/leave-and-attendance/attendance/employee-self-service.md` describes a `hr_employee`
  dashboard that "doesn't exist yet" and calls the resolved shift text a property of the
  **attendance** self-service surface (§2, "My Attendance" header). That doc predates this
  dashboard's build and is now stale on that point — task 20 corrects it. Do not let the doc's
  "doesn't exist" claim block this task; the dashboard is real (see above).

## Part 1 — `frontend/src/lib/api.ts`

Add, near the existing `// ── Shifts: per-date assignments (Manager Portal roster) ──` section:

```ts
export type MyShift = {
  assignment_date: string; // "YYYY-MM-DD"
  shift_master_id: number;
  name: string;
  code: string | null;
  color: string | null;
  start_time: string; // "HH:MM:SS"
  end_time: string;
  is_day_off: boolean;
  is_night_shift: boolean;
  source: "assignment" | "standing";
};

export async function listMyShifts(from?: string, to?: string): Promise<MyShift[]> {
  const token = sessionStorage.getItem("token");
  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  const qs = params.toString();
  const { ok, data } = await secureFetch<{ shifts: MyShift[] }>(
    `/api/v1/shifts/me${qs ? `?${qs}` : ""}`, { token },
  );
  if (!ok) throw new Error("Failed to load your shifts");
  return data.shifts;
}

export async function getMyShiftForDate(date: string): Promise<MyShift | null> {
  const token = sessionStorage.getItem("token");
  const { ok, data } = await secureFetch<MyShift | null>(`/api/v1/shifts/me/${date}`, { token });
  if (!ok) throw new Error("Failed to load your shift for this date");
  return data;
}
```

Confirm the exact response envelope (`{ shifts: [...] }` vs a bare array) against task 18's
`MyShiftsOut` schema once that task lands — adjust the type/unwrap here if it differs from the
guess above.

## Part 2 — Today's Shift card in `EmployeeHome.tsx`

Add a new card, same visual pattern as the existing `STATS`/quick-actions sections (white card,
`border border-border rounded-[14px]`), placed between the `STATS` grid and "Quick actions" (or
folded into the stats row as a 5th tile if that reads better — use judgement, but don't disturb
the existing 4 `STATS` tiles' data).

Fetch via `listMyShifts()` on mount (client component — this file currently has no `useState`/
`useEffect`; add them, following the `useEffect`+`useState` pattern already used in
`hrManager/ShiftScheduling.tsx` for the load-on-mount shape). Render:

- **Today's shift**: from the entry where `assignment_date === todayIso`. If `is_day_off`: show
  "Off today" / "Rest day" instead of a time range (mirror `ShiftScheduling.tsx`'s
  `s.is_day_off ? "Rest day" : ...` pattern). Otherwise show `{name}` + `{start_time}–{end_time}`
  (slice to `HH:MM`, same `.slice(0, 5)` trick used in `ShiftScheduling.tsx`). Use
  `accentFor(shift.color, shift.code)` from `frontend/src/dashboards/shared/shiftAccent.ts` for
  the card's accent color, matching the Manager Portal's shift chip treatment (reuse, don't
  reinvent a second color system — `hrms-spacing`/design-system convention).
  - No entry for today → "No shift scheduled today".
- **Upcoming shifts**: next 4-5 entries after today, each as a compact row —
  date (short format, e.g. "Mon, 17 Aug"), shift name, time range or "Rest day" — matching the
  design prompt §13 table (`Date | Shift | Time`).
- Loading state: a shimmer skeleton per this repo's CLAUDE.md convention ("Loading states —
  shimmer skeletons") — `animate-pulse` placeholders matching the card's real dimensions, not a
  spinner or "Loading…" text.
- Error state: inline message in the card, same tone as `ShiftScheduling.tsx`'s `loadError` box
  (`border-[#F3C9C1] bg-[#FCEDEB] text-[#8F2B20]`).

## Part 3 — Fix the hardcoded subtitle in `index.tsx`

`frontend/src/dashboards/Employee/index.tsx` line ~48-53, the `attendance` view entry:

```ts
attendance: {
  title: "My Attendance",
  subtitle: "July 2026 · Morning shift (09:00 – 17:30)",   // <- hardcoded, delete the TODO above it
  render: (me) => <MyAttendance me={me} />,
},
```

`views[key].subtitle` is a static string set at module-load time — it has no access to fetched
data. Two options, pick whichever fits the shell's rendering contract with the least disruption
(check `frontend/src/dashboards/shell.tsx` / wherever `RoleDashboard.views[key].subtitle` is
consumed before deciding):

1. If the shell already supports a subtitle **render function** for other views, change this to
   one and compute the real month + resolved-today shift text there via `listMyShifts`/
   `getMyShiftForDate`.
2. If not, drop the static subtitle to a generic non-shift string (e.g. just the current month,
   computed with `Intl.DateTimeFormat`) and let `MyAttendance.tsx` itself render the resolved
   shift inline near its header instead — do not leave the literal "Morning shift (09:00 – 17:30)"
   string in the codebase either way.

Whichever path is taken, this task's exit bar is: **no hardcoded shift name/time string remains
in `Employee/index.tsx` or `Employee/EmployeeHome.tsx`.**

## Acceptance criteria

- [x] `EmployeeHome.tsx` shows a real "Today's Shift" card sourced from
      `GET /api/v1/shifts/me`, including the day-off case.
- [x] An "Upcoming shifts" list of the next several days is shown, each row using its own
      resolved shift (name, time or "Rest day").
- [x] Overnight shifts (`start_time > end_time`, e.g. Night 22:00–06:00) render their time range
      correctly (`22:00–06:00`, not a negative/garbled duration) — no special-case date-math
      needed since this is a read-only display of the two time-of-day fields, not a duration
      calculation. Confirmed against a real overnight shift (see below).
- [x] The literal string `"Morning shift (09:00 – 17:30)"` (or any other hardcoded shift name/time)
      no longer appears anywhere under `frontend/src/dashboards/Employee/` (`index.tsx`'s subtitle
      is now a computed `CURRENT_MONTH_LABEL`; the resolved shift itself now renders in
      `MyAttendance.tsx`'s new `TodayShiftLabel`, and in `EmployeeHome.tsx`'s new
      `TodayShiftCard`/`TodayShiftSkeleton`).
- [x] Loading state is a shimmer skeleton, not a spinner or "Loading…" text.
- [x] The employee cannot edit/assign/cancel a shift from this screen — read-only, no mutation
      call exists anywhere in this task's new code (design prompt §14).
- [x] `npx tsc --noEmit` and `npx eslint .` clean for every touched/new file (the 4 `eslint`
      warnings in this directory — unused `me` prop in `MyAttendance.tsx`/`MyLeave.tsx`/
      `MyPayslips.tsx`/`MyReimbursements.tsx` — are pre-existing, confirmed via `git diff`
      untouched by this task).
- [x] **Not visually verified in a browser** (browser automation tool use was declined twice this
      session — accepted as out of reach here per explicit instruction). Verified instead:
      1. A throwaway script (`httpx` + the same RSA-OAEP/AES-GCM dance as
         `test_encrypted_team_employee_shifts_roundtrip`) logged in as the seeded
         `employee1@test.com` / `Test@123` (subdomain `beta`, `EmployeeMaster.id=994`) against the
         **live running dev API** (not the test DB), created a real overnight "Night" shift plus a
         per-date `employee_shift_assignments` override via the admin account
         (`multirole@test.com`), and confirmed `GET /shifts/me`/`GET /shifts/me/{date}` returned it
         correctly (`start_time: "22:00:00"`, `end_time: "06:00:00"`, `source: "assignment"`) —
         end-to-end proof the backend resolution and response shape are correct against real data.
         Both the verification shift and assignment were cleaned up afterward
         (`DELETE /shifts/assignments/78`, `DELETE /shifts/403`, both `204`).
      2. The dashboard-mapping bug that would have blocked a click-through is now **fixed**:
         `backend/scripts/seed_employee_user.py` previously grabbed *any* `DashboardMaster` row
         for the CDP instead of one filtered by `dashboard_path`, so `employee1@test.com` landed
         on the `hr_manager` dashboard instead of `employee_portal`. Fixed to `get_or_create` a
         `DashboardMaster(dashboard_path="employee_portal")` row specifically (same pattern
         `seed_dev.py` already uses), and re-ran it against the live dev DB — confirmed output:
         `Role : Employee -> dashboard 'employee_portal'`.
      This confirms the data path end-to-end; it does not confirm pixel-level rendering of the new
      card/skeleton/label components.

Completed: 2026-08-17
