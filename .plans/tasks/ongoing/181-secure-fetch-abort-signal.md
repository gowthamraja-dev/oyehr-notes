---
task: 181
title: Request cancellation foundation — AbortSignal in secureFetch + useLatestRequest hook
status: ongoing
depends_on: []
---

# 181 — Request cancellation foundation — AbortSignal in secureFetch + useLatestRequest hook

## Why
List/search screens fire a new request on every filter/search/page change, but the old one
keeps running. If an older response lands after a newer one, it overwrites the screen with
stale data (e.g. `EmployeeDirectory.tsx:fetchList` has no guard at all). ~35 components work
around this with a hand-rolled `let cancelled = true` flag, which hides the stale result but
does not stop the request — the server still does the work and the browser still decrypts it.

There is no axios in the frontend, and none is needed: native `fetch` supports
`AbortController` (axios itself now cancels through the same `AbortSignal`; its `CancelToken`
is deprecated). Our "axios-like" choke point is `secureFetch` in
`hrms/frontend/src/lib/crypto.ts` — ~290 calls in `src/lib/api.ts` go through
it — so cancellation goes there once, not per call. Swapping in axios would not help: the
RSA/AES envelope is WebCrypto work done before and after the HTTP call either way.

## Scope
1. **`secureFetch` accepts `signal?: AbortSignal`** (new field on `SecureOptions`).
   - Pass it to `fetch(...)`.
   - Call `signal?.throwIfAborted()` before each expensive step: before `attempt()`, before
     the stale-key retry, after `res.text()`, before the AES decrypt. Aborting mid-flight
     then costs nothing more than the work already done.
   - The stale-key retry (`res.status === 400 && cachedKey`) must reuse the same signal.
   - An abort must throw `DOMException` `AbortError` — never return `{ ok: false }`, and
     never reach `endSession()`.
2. **`isAbortError(e: unknown): boolean`** exported from `src/lib/crypto.ts` (or `src/lib/api.ts`
   next to `ApiError`) — callers use it in `.catch` to skip the error toast / `setFetchFailed`.
3. **`useLatestRequest()` hook** — `src/hooks/useLatestRequest.ts`:
   ```ts
   const run = useLatestRequest();
   useEffect(() => {
     run((signal) => getEmployees({ ...filters }, { signal }))
       .then(setData)
       .catch((e) => { if (!isAbortError(e)) setFailed(true); });
   }, [filters]);
   ```
   - Each `run()` aborts the previous controller held in a `useRef`, then starts a new one.
   - Aborts the in-flight request on unmount.
   - "Latest wins" is **per hook instance**, never global by URL: `hrAdmin/index.tsx` and
     `EmployeeDirectory.tsx` both call `getEmployees` for different purposes at the same
     time, and a path-keyed global cancel would make them kill each other.
4. Plumb `signal` through `getEmployees` only, as the reference pattern:
   `getEmployees(params?: EmployeeListParams, opts?: { signal?: AbortSignal })`.
   The rest of `api.ts` is task 182.

**Not in scope:** migrating call sites (182, 183); mutations (POST/PATCH/DELETE) — never
auto-cancel a write, the server may already have committed it; multipart helpers that use
plain `fetch` (`commitEmployeeImport` already takes a `signal`).

## Files
- `hrms/frontend/src/lib/crypto.ts` — `SecureOptions.signal`, abort checks, `isAbortError`
- `hrms/frontend/src/hooks/useLatestRequest.ts` — new
- `hrms/frontend/src/lib/api.ts` — `getEmployees` opts param
- `hrms/docs/payload-encryption.md` — short "Cancelling a request" note under the frontend section

## Acceptance criteria
**Changed 05-Oct-26:** the user wants cancellation configured in `api.ts`, not in components.
The `useLatestRequest` hook was dropped in favour of `latestOnly(fn, { lane })` in
`src/lib/latestRequest.ts` (see task 184). `getEmployees` is unchanged: it has many concurrent
callers (directory list and typeaheads in modals over it), so it needs lane design in task 182.

Work happens in the top-level `hrms/` clone (user's call, 05-Oct-26), not `workspace-2/`.
Node check against the dev API (05-Oct-26): pre-aborted → `AbortError`, 0 fetches; mid-flight
abort → `AbortError`; no-signal call unchanged. Browser Network-tab + hook checks still open.

- [x] `secureFetch(path, { signal })` with an already-aborted signal rejects with `AbortError` and sends no request (Network tab).
- [ ] Aborting during a slow request (DevTools throttling) cancels it in the Network tab and rejects with `AbortError`; no 401 redirect, no `endSession`.
- [x] Existing calls without `signal` behave exactly as before (login, an encrypted list, a POST).
- [ ] `useLatestRequest`: three rapid `run()` calls leave only the last one un-cancelled; unmounting cancels the in-flight one.
- [x] `npx tsc --noEmit` clean; eslint clean on the touched files (repo-wide `npm run lint` has pre-existing errors).
