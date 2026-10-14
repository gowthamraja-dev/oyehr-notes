---
task: 55
title: Employee documents — list and upload API (Documents profile tab)
status: done
depends_on: []
---

# 55 — Employee documents — list and upload API (Documents profile tab)

## Discussion

The design prompt's profile Documents tab (§9) may only be built "when the existing schema and
permissions support them." `image_details` is a generic polymorphic store
(`app/models/image_detail.py`, keyed by `(imageable_type, imageable_id)`) and
`app/services/image_service.py` already anticipates `imageable_type="EmployeeMaster"` — it's in
the `_FOLDER` map and even in the module's own usage docstring — but **nothing in the codebase
actually calls it for an employee today**. No employee-facing upload flow, and no `img_type`
row for `EmployeeMaster` exists in CLAUDE.md's tracked `img_type` table. So the schema supports
this; it's simply never been wired up. This task wires it, end to end, rather than building a
read-only tab against data that can never exist.

### `img_type` values introduced by this task

Following CLAUDE.md's "File uploads" convention, add rows to that table's `img_type` list:

| Entity | img_type | Description |
| --- | --- | --- |
| EmployeeMaster | `profile` | Employee photo shown in the directory/profile header |
| EmployeeMaster | `document` | General HR document attached to the employee (ID proof, offer letter, etc.) |

### Endpoints — `backend/app/modules/employees/router.py`

`GET /employees/{employee_id}/documents` → `list[EmployeeDocumentOut]`, on the existing
`EncryptedRoute` router. `EmployeeDocumentOut { id, img_type, img_url, created_at }`. CDP-scope
`employee_id` through the same `EmployeeMaster` → `CorpMaster` join `get_employee` already uses
(404, not empty list, for a cross-CDP id). Query `ImageDetail` where `imageable_type =
"EmployeeMaster"`, `imageable_id = employee_id`, `is_active = true`, ordered by `created_at
desc`.

`POST /employees/{employee_id}/documents` — **multipart**, so per CLAUDE.md's "file uploads"
section this must live on a **plain `APIRouter`**, not the encrypted one — mirror the
`_upload_router` pattern already used in `organizations/router.py` and `leave/router.py`'s
attachment endpoint. Body: `file: UploadFile`, `img_type: Literal["profile", "document"]`.
Calls `image_service.upload_image(db, user_id=principal.user.id, imageable_type="EmployeeMaster",
imageable_id=employee_id, file_bytes=..., content_type=file.content_type, img_type=img_type)` —
this already handles size/MIME validation and deactivating the previous active row for the same
`(imageable_type, imageable_id, img_type)` (relevant for `profile`, where there should only ever
be one active photo; `document` rows are additive — multiple documents coexist, so re-uploading a
`document` shouldn't be understood as "replacing" a specific prior one; note this in a code
comment since `upload_image`'s deactivate-previous behavior means uploading a second `document`
silently deactivates the first one. If that's not the desired semantics for the many-documents
case, use a distinct `img_type` per logical document — e.g. the frontend passes a more specific
type than the generic `"document"` string per upload (`"doc_id_proof"`, `"doc_offer_letter"`,
etc.) so each slot manages its own history, same pattern CDP's `cert_incorporation`/`cert_gst`/
etc. already establish. Prefer this over a bare `"document"` catch-all — decide the exact set of
document slots with whoever reviews this task, or default to a small starter set: `doc_id_proof`,
`doc_offer_letter`, `doc_other` (repeatable) — document the final choice in CLAUDE.md's table
instead of the two-row sketch above.**

Authorization: any authenticated caller in the CDP may `GET` (matches the rest of the directory's
view permission, no stricter than viewing the employee's profile at all); `POST` requires
`principal.is_admin` **or** `_require_manager_or_admin_for_employee`-equivalent for the target
(reuse [[54]]'s helper if it lands first, or write the same shape here and let whichever task
lands second de-duplicate it into a shared place — both modules already tolerate this kind of
small duplication per `attendance/service.py`'s own docstring note about not cross-importing
between attendance and shifts).

## Files

- `backend/app/modules/employees/router.py` — new `GET` route (encrypted router) + new `POST`
  route (new plain multipart sub-router, mounted alongside, same pattern as other modules'
  `_upload_router`)
- `backend/app/modules/employees/schemas.py` — `EmployeeDocumentOut`
- `backend/app/services/image_service.py` — no code change needed (`EmployeeMaster` folder
  mapping already exists); confirm the `_FOLDER` entry is still `"employee"` and reuse it
- `CLAUDE.md` — add the final `img_type` rows decided above to the existing table under "File
  uploads"

## Tests (extend `backend/app/tests/modules/test_employees.py`)

- Upload a document, then list — it appears with the correct `img_type`/`img_url`.
- Uploading a second `profile` photo deactivates the first (only one active `profile` row at a
  time) — matches `upload_image`'s existing documented behavior.
- Uploading a second document under a distinct document-slot `img_type` does **not** deactivate
  an existing document under a different slot.
- Cross-CDP `employee_id` → `404` on both `GET` and `POST`.
- `GET` works for any authenticated CDP member; `POST` is rejected for a non-admin caller who
  isn't the target's manager.
- Oversized file / disallowed content-type rejected (already covered generically by
  `upload_image`'s own validation — one smoke test here confirming this route surfaces that
  error, not a full re-test of `image_service`).

## Acceptance criteria

- [x] Documents tab has a real, working upload + list path — not a permanently-empty read view.
- [x] `POST` is on a plain (unencrypted) multipart router; `GET` stays on the encrypted router.
- [x] CLAUDE.md's `img_type` table is updated with the final set of `EmployeeMaster` values this
      task actually shipped.
- [x] No employee outside the caller's CDP is ever reachable through either route.

## Completion notes

- Went with the task's own default starter set: `profile`, `doc_id_proof`, `doc_offer_letter`,
  `doc_other` — no reviewer was available to pick a different set.
- **`doc_other` is single-slot, not repeatable**, despite the task text's parenthetical
  "(repeatable)" next to it in the default-set suggestion. `upload_image` (left unchanged, per
  the task's own "no code change needed" instruction) deactivates every previous active row for
  the exact same `(imageable_type, imageable_id, img_type)` triple — there is no mechanism in
  the shared service for one `img_type` string to hold multiple simultaneously-active rows.
  Making `doc_other` genuinely repeatable would need either an `image_service.py` change (out of
  scope here) or minting a unique per-upload `img_type` suffix (which would break the "small
  fixed set of slots" pattern every other `img_type` in CLAUDE.md's table follows, including
  `LeaveRequestDetail`'s own `attachment`, which is single-slot the same way). Documented
  accurately in both CLAUDE.md and the `EMPLOYEE_DOCUMENT_IMG_TYPES` docstring; if genuine
  multi-document-per-slot support is wanted later, that's a separate task against
  `image_service.py` itself, not a per-caller workaround.
- Authorization for `POST` mirrors [[54]]'s `_require_manager_or_admin_for_employee` shape
  exactly (admin, self, or direct manager) — written locally in `employees/service.py` rather
  than imported from `attendance.service`, matching this codebase's established per-module
  duplication tolerance for this predicate (attendance/service.py's own docstring already makes
  this call for `_require_caller_employee`).
- `employees/router.py` gained an `_upload_router` + `include_in(api_router)`, following the
  organizations/leave/attendance pattern exactly; `app/api/router.py` was updated to mount it via
  `include_employees_router(api_router)` instead of importing the bare `router`.

Completed: 2026-08-19
