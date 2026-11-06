# Lead generation (public pricing-page enquiries)

Schema (approved 2026-11-05): [`lead-generation-schema.dbml`](lead-generation-schema.dbml). This plan links it and does not restate it.
Paths are relative to `workspace-1/hrms/`.

> **FINAL schema, 2026-11-06 (user-supplied):** `lead_masters` is just `name`, `email`, `mobile`, `subscription_plan_master_id`,
> `subscription_price_master_id`, `subscribed_at`, `status_master_id` plus soft-delete and audit columns, with **no CHECK constraints**.
> Everything below or in earlier banners about a billing address, resume code, conversion/completion columns or the CDP onboarding
> columns is **not in the schema**; it is only deferred design. This banner overrides them.

> **Scope revision, 2026-11-05 (user instruction):** for now this feature is **only the table**: the `LeadMaster` model and its Alembic migration
> (`alembic/versions/e6b2d8f4a173_lead_masters.py`, with the five `LEAD` rows it seeds into `status_masters`). Everything else in this plan, i.e. the public-endpoint storage, the `leads` module, the Leads screen, conversion and the form field, is **not being built**
> and is kept only as the design for a later decision. The stage is now `status_master_id` → `status_masters` (not a `status` varchar), so wherever
> this plan says `status = X` read "the `status_masters` row with `source_activity = 'LEAD'` and `status_code = X`", resolved by code; the
> status CHECK is gone, and "CONVERTED needs `converted_at`" is enforced by the service, not the database.
>
> **Column names follow the organisation side:** where this plan says `company_name`, `contact_name`, `organization_email` or `phone`, the columns are
> `name`, `frst_nm` + `lst_nm`, `email` and `mobile` (the same names `care_delivery_program_masters`, `users` and `contact_details` use), so a lead copies straight into
> Add Organization.
>
> **Revision 3 (6-Nov-26): the schema now also holds the billing address, resume code, subscription facts and completion** (see `lead-generation-schema.dbml` "Scenarios the schema covers"). Behaviour for those (address step,
> resume-by-code, subscribe, one-time form) is NOT designed here; it is only the table and migration for now.

## Why
The "Send request" form on the public Subscriptions page (`frontend/public/subscriptions.html` → `POST /api/v1/public/plan-enquiry`) only
emails the support inbox (`backend/app/modules/public/enquiry.py`, "Nothing is stored"). Nobody can see who asked, who followed up, or which
enquiry became a customer. Each enquiry becomes a row in `lead_masters`; Super Admin works the list; converting a lead creates the
organisation and links back to it.

## Scope
Built now: model + migration only (see the revision note above). The rest of this section is the deferred design.

In (deferred, except the first bullet):
- New table `lead_masters` (model, migration, shared-DB hand-apply).
- Public form: add the **Company name** field (page + endpoint), and store every accepted enquiry as a lead. The email to support stays.
- Duplicate rule: same email (case-insensitive) enquiring while an open lead exists updates that lead (decision 3).
- Super Admin **Leads** screen: list, filter, search, open a lead, assign, change status, notes, lost reason, archive.
- Conversion: the Add Organization flow can be started from a lead and stamps the lead `CONVERTED`.
- Tests, `docs/lead-generation.md`.

Out of scope:
- Any tenant-facing (org admin / HR) view of leads. The table is platform-level and Super Admin only.
- Creating a tenant, trial or `organisation_subscriptions` row automatically from a submit (rejected in the schema's Alternatives).
- Email/SMS/WhatsApp follow-up automation, reminders, a status history table, lead scoring, a retention/purge job, a `submitted_ip` column.
- Other sources (`WEBSITE_CONTACT`, `REFERRAL`) beyond the column existing. `MANUAL` "add lead" button: not built (see Open decisions).
- Changing the rate limits or the honeypot.

## Flow
1. Visitor picks a plan on `/subscriptions.html`, fills Company name, Organization email, Contact person, Phone, sends.
2. `POST /public/plan-enquiry` validates, applies the honeypot and the 3 rate limits (unchanged), then in one transaction:
   find an open lead for `lower(organization_email)` (`archive = false`, status not CONVERTED/LOST); update it (plan, cycle, company, contact,
   phone, `last_enquired_at = now()`) or insert a new one (`source = PRICING_PAGE`, `status = NEW`). A LOST lead whose person enquires again
   gets a new row, not a reopen.
3. The support email is sent as today (now also showing Company name). The lead is the record of truth, so an email failure does **not** fail the
   request: log a WARNING, still return 201. The rate-limit slot is kept (the visitor did nothing wrong, but the lead is stored, so a retry would
   only duplicate it).
4. Super Admin opens **Leads** in the portal, takes a lead (assign), moves it NEW → CONTACTED (sets `contacted_at` on first move) → QUALIFIED, or
   LOST (with `lost_reason`).
5. To convert: "Create organization" on the lead opens the existing Add Organization modal pre-filled (company → name, contact → contact, email,
   phone, plan). On a successful create, the same transaction sets the lead `CONVERTED`, `converted_at`, and the new CDP id.
6. Archive hides a lead from every list and from the duplicate check (soft delete).

State rules (service-enforced, backed by `ck_lead_masters_converted`):
- `CONVERTED` is reached only through organisation creation, never by a manual status change; a CONVERTED lead cannot move back.
- `LOST` requires a `lost_reason`; moving out of LOST clears it.
- Allowed manual moves: NEW → CONTACTED, QUALIFIED or LOST; CONTACTED → QUALIFIED or LOST; QUALIFIED → LOST; LOST → CONTACTED (re-engaged).
  Nothing moves back to NEW, and QUALIFIED does not move back to CONTACTED.

## Backend
- `app/models/lead_master.py` → `LeadMaster`, table `lead_masters`, exactly as the DBML (column types, DB defaults as `server_default`, the three CHECKs
  `ck_lead_masters_source/billing_cycle/converted`; `status_master_id` has no default, the indexes; the functional `lower(organization_email) WHERE archive = false` index is written
  with `Index(..., func.lower(...), postgresql_where=...)`). Register in `app/models/__init__.py`.
- Migration (**done, not applied anywhere**): hand-written and existence-guarded like `d5e9a1c7f302`, chained from `a9d4f2c6b318`; its `UPGRADE_SQL` is the exact SQL for the shared DB. Apply with `scripts/migrate.py upgrade heads` on a normal DB.
- New module `app/modules/leads/` (`router.py`, `schemas.py`, `service.py`); mount in the API router next to `/admin/subscriptions`.
  - Plain read/write rules in `service.py`; routes on an `EncryptedRoute` router with prefix `/admin/leads`, every route `RequireSuperAdmin`
    (there is no tenant caller, so there is no CDP filter by design; add a comment saying so and a test that a tenant admin gets 403).
  - `GET /admin/leads` (filters: `status`, `assigned_to_id`, `plan`, `q` over company/name/email/phone, `created_from/to`; server-side paging per the shift roster
    pattern; default excludes `archive = true`), `GET /admin/leads/{id}`, `PATCH /admin/leads/{id}` (status, assigned_to_id, notes, lost_reason, contact fields),
    `DELETE /admin/leads/{id}` → archive (sets `is_active=false`, `archive=true`, `archived_by_id`, `archived_at`),
    `GET /admin/leads/summary` (count per status, for the header tiles).
  - `leads.service.record_enquiry(db, payload) -> LeadMaster` is the single write path for the public form (and any future source). It maps the page
    label to `subscription_plan_masters` by `plan_code`: `OyeHR Light Basic → LIGHT_BASIC`, `Light Initial → LIGHT_INITIAL`, `Light Growth → LIGHT_GROWTH`,
    `OyeHR One → ONE`; an unmatched plan stores `subscription_plan_master_id = NULL` and keeps `plan_name`. `billing_cycle` stored upper-case.
- `modules/public/enquiry.py`: `PlanEnquiryIn.company_name` (required, 2–200, trimmed, whitespace-collapsed, no control characters, same line-break guard as the
  other fields); after the rate-limit reservation call `record_enquiry`, then email. The router gains `DbSession`. Update the module docstring (it says "Nothing is
  stored"). Public router stays a plain `APIRouter` (no `EncryptedRoute`).
- `modules/admin_organizations`: `CreateOrganizationRequest.lead_id: int | None`. In `create_organization`, when present: load the lead (404 if missing,
  409 if archived or already CONVERTED), and after the CDP is flushed set `status = CONVERTED`, `converted_at`, `converted_care_delivery_program_master_id`,
  `updated_by_id` in the same transaction, so a failed create leaves the lead untouched.
- `hrms-activity-logging`: archive and the CONVERTED stamp are a deletion and an ownership/assignment-type change, so write `log_activity` rows for
  `lead_archived`, `lead_assigned`, `lead_converted` (record = lead id; no PII in the detail).
- Logging: workspace-1 uses stdlib `logging` (`logging.getLogger(__name__)`, `%s` placeholders; its own CLAUDE.md says no third-party logger). Messages for lead created / updated-existing / status changed / archived / converted, ids only. **Never log email, phone or
  name.** The existing `logger.info("Plan enquiry sent for %s", payload.plan)` line stays (plan only).
- RBAC: Super Admin only (bypasses the grid); no `permissions.py` resource.
- Cloud: no local state. The in-process rate limits are unchanged (per task); noted in the doc.

### Shared hrms-dev DB
Hand-applied, same method as `shift_day_overrides` (memory: reference-shared-hrms-dev-db): the migration's existence-guarded DDL in one transaction, short
`lock_timeout`, stamp (`8012104013b3`) left alone, then `GRANT SELECT, INSERT, UPDATE, DELETE` on `lead_masters` and `USAGE, SELECT` on its sequence to
`backup_user` (the 29-table gap is not widened). Verify afterwards with Alembic `compare_metadata`. Only when the user explicitly asks to apply it.

## Frontend
- `frontend/public/subscriptions.html`: add "Company name" as the first field (`name="company_name"`, `maxlength=200`, placeholder "Your company", `autocomplete="organization"`),
  validation rule (≥ 2 characters), included in the POST body and in the 422 field-error mapping, included in the focus order of the focus trap. The "Thank you" copy is unchanged.
- `frontend/src/lib/api.ts`: `Lead`, `LeadSummary`, list/get/patch/archive helpers (all via `secureFetch`, the endpoints are encrypted).
- Super Admin portal: new nav item **Leads** in `frontend/src/dashboards/superAdmin/index.tsx` (between Organizations and Subscriptions), view component
  `superAdmin/LeadsPage.tsx`. Tailwind only, 10px page spacing (`hrms-spacing`), dates via `DateField`/dd-MMM-yy (`hrms-date-format`), archive confirm through `useConfirm()`
  (`hrms-confirm-dialog`).
  - Status tiles row (count per status, click filters), filter bar (search, status, assignee, plan), table (company, contact, email, phone, plan + cycle,
    status badge, assignee, created, last enquired), paging.
  - Row opens a side panel/drawer: all fields, status select, assignee select, notes, lost reason (when LOST), "Create organization", "Archive".
    The drawer is a modal-style overlay, so the `hrms-responsive-side-panel` rule does not apply.
  - Loading state: `LeadsSkeleton` exported next to the page, built only from the shared `Shimmer*` primitives (`ShimmerMetricTileRow`, `ShimmerFilterBar`, `ShimmerTable`
    with the same `gridTemplateColumns` as the real table); page shows it immediately while data loads.
- `AddOrganizationModal.tsx`: accept an optional `lead` prop to pre-fill name, contact first/last name, email, mobile and show the chosen plan as read-only text;
  send `lead_id` on submit. Plan assignment itself stays in the Subscriptions screen (not changed here).
- Leads list reload after the modal closes with success so the row shows CONVERTED.

## Tests (`app/tests/modules/test_leads.py`, plus updates to `test_plan_enquiry.py`)
- Public submit: 201, row stored with `source = PRICING_PAGE`, `status = NEW`, correct plan FK and upper-case cycle; unknown plan 422 and no row; missing/short company 422;
  honeypot stores nothing; rate-limited stores nothing; email failure still 201 and the lead exists; plan with no catalogue row stores NULL FK.
- Duplicate rule: same email, different case → one row, `last_enquired_at` bumped, fields refreshed; archived / LOST / CONVERTED lead → new row.
- Super Admin routes: list filters + paging + search; archived hidden; detail; patch status transitions (every allowed and one disallowed per rule, LOST needs reason, CONVERTED
  not settable manually); assign; archive writes `archive`/`archived_by_id`/`archived_at`.
- Authorisation: 401 unauthenticated; **403 for a tenant admin and for an HR role** on every `/admin/leads` route (the cross-tenant table must never leak).
- Conversion: `create_organization` with `lead_id` stamps the lead; bad/archived/already converted `lead_id` rejects with no CDP created; a failed create leaves the lead unchanged.
- Existing `test_plan_enquiry.py` payload gains `company_name`; email body asserts the Company line.
- Encrypted round trip for the admin router, like `test_encryption.py`.
- Migration: applies on a fresh DB, `alembic check` clean, CHECK `ck_lead_masters_converted` rejects `CONVERTED` without `converted_at`.

## Docs
`docs/lead-generation.md`: the flow above, state rules, the "platform-level, Super Admin only, no CDP column" warning, conversion, the shared-DB apply steps. Link it from the
CLAUDE.md "Authentication & sessions"/subscriptions neighbourhood only if a section for public endpoints is added later; otherwise link from `docs/subscriptions-schema.md`.

## Rollout order
1. Model + migration (+ shared-DB apply when asked).
2. Backend `leads` module + `record_enquiry` + public endpoint change (+ tests).
3. Public page Company name field. Deploy 2 and 3 together, otherwise the page sends no `company_name` and the endpoint rejects it. (Mitigation if they must go out separately:
   make `company_name` optional on the endpoint for one release; the column stays NOT NULL, so `record_enquiry` would then fall back to the contact name.)
4. Admin conversion hook (`lead_id`), then the Leads screen and the modal pre-fill.
5. Docs.

## Open decisions
1. **Email failure behaviour (proposed: still 201, lead kept).** The old behaviour returned 503 so the visitor could retry. With storage that would create duplicates and lose the
   lead's "stored" guarantee. Say if you would rather keep 503.
2. **`MANUAL` source:** should Super Admin get an "Add lead" button now (for phone/WhatsApp enquiries), or later? Proposed: later; the column already allows it.
3. **Who can convert/assign:** only Super Admin (proposed). If you want a "sales" role on the platform side, that is a new role and a new grid resource, not part of this plan.
4. **`company_name` rollout:** deploy page and endpoint together (proposed), or make the field optional for one release?
5. **Duplicate window:** an open lead is updated no matter how old it is. Proposed: yes; say if a lead untouched for N days should rather start a new row.
