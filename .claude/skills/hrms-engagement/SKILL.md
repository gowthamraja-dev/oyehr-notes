---
name: hrms-engagement
description: >
  Build or modify HRMS engagement features — WhatsApp messaging (send/templates/status
  ticks/inbound), the reusable engagement drawer, the Meta webhook, and real-time
  updates. Use whenever the task touches WhatsApp/engagement, chat_rooms/chat_messages,
  message_transaction_details, partner_parameter_masters, the engagement module, the
  webhooks module, or the EngagementDrawer/useEngagement frontend. Also encodes HRMS
  cross-cutting patterns (CDP scoping, real-time via Postgres NOTIFY, shell/breadcrumb,
  and the CodeArtifact build gotcha) learned porting nh_server_app's engagement to HRMS.
---

# HRMS Engagement (WhatsApp) — patterns & gotchas

Reference app is `nh_server_app` (Rails). HRMS re-implements the *behaviour* natively
(FastAPI + Next.js), it does not share code. Port shape/UX, not implementation.

## 1. WhatsApp configuration — `partner_parameter_masters`, param 208
- Integration creds live in `partner_parameter_masters` under **`parameter_master_id = 208`**
  (`parameter_masters` id 208 = `WhatsappAuth`). `parameter_value` is a **JSON string** with keys:
  `phone_number_id, waba_id, business_id, auth_token, webhook_verify_token, app_secret, phone_display`.
- **Lookup is by the caller's CDP only** (`care_delivery_program_master_id == principal.tenant_id`) —
  do NOT add a global `0` fallback (product decision). Helper: `_wa_config(db, cdp_id)`.
- "Configured" = the JSON has all of `phone_number_id`, `auth_token`, `waba_id`
  (`_config_complete`). The frontend WhatsApp action is enabled only when configured.
- Never hardcode creds. Seed for dev via env `WHATSAPP_CONFIG_JSON` (passed to `seed_dev`), never commit.
- **`partner_parameter_masters.parameter_value` copied from legacy Rails data may be a Ruby
  `Hash#inspect` string** (`{:phone_number_id=>"...", ...}`), not JSON — `json.loads` throws and
  is silently swallowed to "not configured" even though real creds are present. `_wa_config`/
  `find_config_by_phone_number_id` go through `_parse_config_value`, which falls back to a regex
  parse of that Ruby-hash-pair syntax when `json.loads` fails. Don't "fix" this by rewriting the
  DB row to JSON — the parser handles both formats on purpose, since more legacy-copied rows may
  turn up the same way.
- **`template_masters.activity_name` convention (confirmed against nh_server_app's actual
  DB-level usage, not its frontend labels)**: WhatsApp templates use **`'WTSAPP'`** (all caps,
  abbreviated — NOT `'WhatsApp'`, NOT `'WTSP'`; nh_server_app's own React frontend inconsistently
  says `"WhatsApp"` in a couple of dropdowns, but every backend query/dispatch/controller check
  reads/writes `'WTSAPP'` — that's the value that matters). Email templates use the full word
  `'Email'`. Both `seed_employee_form_template_vars.py` (WhatsApp) and
  `seed_employee_email_template.py` (Email) set this column — don't leave it `NULL` on a new
  template row even if nothing currently filters WhatsApp sends by it (only the Email path does
  today, in `list_email_templates`/`send_email`); a future feature may add the same filter to
  WhatsApp, and a `NULL` row reads as "never configured," same trap as the Ruby-hash bug above.

## 2. Sending (outbound) — Meta Graph, independent of the webhook
- Backend module `hrms/backend/app/modules/engagement/` on an **`EncryptedRoute`** router (PII). Endpoints:
  `GET /whatsapp/status`, `GET /whatsapp/messages`, `GET /whatsapp/templates`,
  `POST /whatsapp/send-text`, `POST /whatsapp/send-template`.
- Send = HTTP `POST https://graph.facebook.com/v19.0/{phone_number_id}/messages` with
  `Authorization: Bearer {auth_token}`, via **httpx** (mock it in tests). Meta accepting returns
  `messages[0].id` (**wamid**, ~60 chars) with `message_status: accepted`.
- **Number normalisation** (`_to_number`): Meta needs the country code, no `+`. 10-digit → prefix
  `91`; `0`+10-digit → strip 0, prefix `91`; already-`91` kept. (`917844887791` is correct.)
- **Templates**: list **APPROVED only** from `GET /{waba_id}/message_templates` (skip
  PENDING/REJECTED/PAUSED) and send with the template's **own `language`** — sending the wrong
  language causes Meta error **#132001 "Template name does not exist in the translation"**.
- **Template body preview**: request `fields=name,status,language,components` (NOT just
  name/status/language) and extract the `{"type":"BODY","text":…}` component's text into
  `TemplateOut.body`, substituting Meta's `example.body_text` sample values into `{{1}}`,`{{2}}`,…
  (`_template_preview`). The chat bubble renders the stored message body, so if you don't carry the
  real text the frontend sends `undefined` → `send_template` falls back to storing the **template
  name** and the bubble shows `hello_from_nanohealth` instead of the actual message. HEADER/FOOTER/
  BUTTONS are ignored for the bubble.
- **24h session rule**: free-text only delivers within 24h of the user's last inbound message;
  otherwise you must send an approved **template** first. The drawer defaults to the template picker
  when no active session.
- Sending does NOT need the webhook. It works as soon as the config is valid.

## 3. Rooms & messages
- **Email does NOT get a chat room.** Confirmed against nh_server_app: `patient_engagement_details`
  (HRMS's analog: `employee_engagement_details`, currently unused/empty — a later task will start
  writing to it) is the shared, channel-agnostic engagement log every channel writes to. WhatsApp is
  the outlier that *additionally* creates a `chat_rooms`/`chat_messages` pair + `message_transaction_details`
  row, because it's two-way/conversational. Email is fire-and-forget (send the form link, no reply
  thread) and in nh_server_app never touches chat-room tables at all — it only logs to the engagement
  table (+ a message-content record). **Don't call `_find_or_create_room`/write `ChatMessage` for
  email** — it'll try to insert `chat_room_type_master_id = 7` ("Employee mail"), which doesn't
  exist in `chat_room_type_masters` (only ids 1-6 are seeded), causing an FK violation on every send.
  `send_email` should log only via `MessageTransactionDetail` (`activity_type="EMA"`) for now; a
  later task adds proper `employee_engagement_details` rows for real history.
- `chat_rooms` **find-or-create by `(cdp, employee_master_id)`** — one room per employee, never
  duplicate. WhatsApp room: `chat_room_type_master_id = 6`, `communication_channel_type_master_id = 3`
  (NanoHealth System — WhatsApp is a system chat).
- `chat_messages` has **no** status/wamid column and `pubnub_timetoken` is **varchar(30)** — too short
  for a wamid. Pattern: write the `message_transaction_details` (MTD) row FIRST (`transaction_id =
  wamid` in varchar255), flush, then store the **short `str(mtd.id)`** in `pubnub_timetoken`.
  `list_messages` LEFT-joins `cast(MessageTransactionDetail.id, String) == ChatMessage.pubnub_timetoken`
  to surface `status` + `wamid`. Outbound `sender_role="provider"`, inbound `="employee"`.
- `message_transaction_details` is the send/status log: `activity_type` `WTS` (outbound) / `WTA`
  (inbound), `status` (sent/delivered/read/failed/received), `updates_json` = status history.

## 4. Real-time updates — Postgres LISTEN/NOTIFY (NOT Redis)
- nh uses ActionCable (WebSocket+Redis). In HRMS the browser learns of webhook events via **SSE**.
- **Use Postgres `LISTEN/NOTIFY`, not the Redis client** — adding `redis` to pyproject is blocked by
  the CodeArtifact 401 (see gotchas). psycopg is already installed, so NOTIFY needs no new dependency.
- Publish (in `hrms/backend/app/core/notify.py`): `notify_employee(db, cdp, emp_id, payload)` runs
  `SELECT pg_notify(:chan, :payload)` **inside the caller's transaction** (delivered on commit).
  Channel = `wa_emp_{cdp}_{employee_id}` (digits/underscore = valid identifier). Call it in the webhook
  (per affected employee) and after send, before `db.commit()`.
- SSE endpoint: **plain** (non-Encrypted) router `GET /api/v1/engagement/whatsapp/stream?employee_id=&token=`,
  async `StreamingResponse` `text/event-stream`. Auth via `token` **query** (EventSource can't set
  headers) — decode the JWT, scope the employee to the CDP. Open an **own** `psycopg.AsyncConnection`
  (autocommit), `LISTEN {channel}`, and `async for note in aconn.notifies(timeout=15)` → yield
  `data: {payload}\n\n`, else a `: keepalive`. Events carry **no PII** (just a ping) — the client
  refetches the encrypted messages endpoint.
- Verify locally without Meta: open the SSE URL with a minted token and fire
  `SELECT pg_notify('wa_emp_1_7', '{"type":"update"}')` from psql — the stream should print it.

## 5. Meta webhook — `hrms/backend/app/modules/webhooks/` (plain, unauthenticated)
- `GET /api/v1/webhooks/whatsapp` → echo `hub.challenge` when `hub.mode==subscribe` and
  `hub.verify_token` matches a config's `webhook_verify_token`, else 403.
- `POST /api/v1/webhooks/whatsapp` → read the **raw body**; find the config by
  `value.metadata.phone_number_id`; verify `X-Hub-Signature-256` = HMAC-SHA256(app_secret, raw_body)
  (skip if no app_secret). Process `value.statuses[]` (update MTD by wamid) and `value.messages[]`
  (inbound → match employee by last-10-digits of `from`, find-or-create room, insert inbound message).
  Always return 200. NOTIFY each affected employee before commit.
- **Meta allows ONE callback URL per WABA.** It currently points at nh's domain
  (`customer.nanohealthplan.com/webhooks/whatsapp`). For HRMS to receive: point Meta at HRMS's public
  URL, or have nh fan-out a copy. **Meta can never reach `localhost`** → delivered/read/inbound only
  work on a public HTTPS deployment (or ngrok). Outbound send + its SSE echo work locally.

## 6. Frontend — reusable engagement drawer
- Global provider `EngagementProvider` + `useEngagement()` (`src/contexts/engagement-context.tsx`),
  mounted once in `hrms/frontend/src/app/dashboard/layout.tsx`. Any view calls
  `useEngagement().open({ entityType, entityId, name, mobile, subtitle?, details? })`. Generic — works
  for employees now, patients later. The drawer/API live in `src/dashboards/shared/`.
- `EngagementDrawer` = right-side; **details-first** (quick actions + details + last interaction), and
  the **WhatsApp** quick action opens the chat (details collapse to a side column). Channels:
  WhatsApp active; SMS/Call/Email/Notify inactive.
- WhatsApp chat UI: official green logo `#25D366`; bubbles outbound `#d9fdd3` (radius `8px 0 8px 8px`),
  inbound white (`0 8px 8px 8px`); chat bg `#efeae2`; time `h:mm AM/PM` `#667781`; ticks via `ChatTick`
  (sent=1 gray, delivered=2 gray, read=2 blue `#53bdeb`, failed=red `!`). Footer: 😊 emoji picker →
  text → template-icon popup → send. Recipient shown `+91 xxxxx xxxxx` (`fmtPhone`).
- Real engagement icon: nh PNGs copied to `hrms/frontend/public/icons/engagement{,_active}.png`.
- **24h session countdown chip** (nh parity): compute from the last **inbound** message's
  `created_at` — `remaining = lastInboundTs + 24h - now`. Show a chip in the chat header (dot +
  small label) that **ticks every 1s** (a `sessionTick` state + `setInterval` running only while
  the chat is open): active → dot `#22c55e`/text `#166534` label `Xh Ym Zs left`; **warning
  (`< 4h` left)** → dot `#f97316`/text `#b45309`; **expired** → dot `#ef4444`/text `#b45309` label
  `Session closed`. Only render when the employee has replied at least once (`sessionKnown`).
  `freeTextLocked = !(sessionKnown && !expired)`; keep the amber "no active session" banner for the
  locked/expired case (complements the chip).

## 7. Shell / layout conventions
- Breadcrumb = **Home (icon) › {nav section} › {page}** in its own row; the top band is **search only**
  (+ help/notification icons). A view sets `fullBleed: true` (in its `DashboardView`) to render its own
  full-height layout (the shell drops the default heading/padding). Content spacing ~**10px** (uniform:
  `p-[10px]` + `gap-[10px]`, no leftover per-child margins that double the gap).
- **List/directory pages**: the page's own sub-breadcrumb's LAST segment reflects the **selected
  filter**, so it shows which item is active — e.g. Employee Directory shows
  `Employee Directory › {selected department}` and `… › People` when "All" is selected.
- Tailwind only (v4). Brand tokens: `--brand-primary`, `--input-focus`, teal/ink palettes.

> **Keep this skill current:** when the user gives a specific UI/behaviour directive during HRMS work
> (spacing, breadcrumb rules, colours, layout, naming, a gotcha), record it here so it isn't
> re-litigated next time.

## 8. Assets & icons — where & how (best practice)
- **UI glyphs → inline SVG** (default). Nav/button/status icons are inline `<svg>` with
  `stroke="currentColor"` (or `fill="currentColor"`) so Tailwind text colour controls them, they scale
  crisply, and cost no HTTP request. This is the norm across the shell, drawer, directory, etc.
- **Raster/brand icons → PNG in `hrms/frontend/public/icons/`**, referenced as `/icons/<name>.png`
  (Next serves `public/` at `/`). Use a PNG only when it's a brand/complex mark that can't be a clean
  SVG — e.g. nh's engagement icon copied from
  `nh_server_app/public/assets/new/base/engagement-<hash>.png` → `hrms/frontend/public/icons/engagement.png`
  (+ `engagement_active.png`). Keep all such icons under `public/icons/`, not scattered.
- **Rendering a PNG icon**: plain `<img src="/icons/…" width height />` with
  `{/* eslint-disable-next-line @next/next/no-img-element */}` (project convention). PNGs are
  fixed-colour: for an inactive→active swap use the two files (`x.png` / `x_active.png`); to force a
  PNG glyph white on a dark/tinted tile use `style={{ filter: "brightness(0) invert(1)" }}`.
- **Brand logos** (e.g. WhatsApp) → inline SVG with the **official brand colour** (`#25D366`); never
  recolour a brand mark. Put reusable ones as a small component (e.g. `WaLogo`).
- **Org logo / favicon are DB-driven**, NOT static assets — they come from `image_details` via the API
  (`logo_url` / `favicon_url`); render those URLs, don't hardcode files.
- **No new `.module.css`** — Tailwind utilities + inline `style` only (per CLAUDE.md). Icon tiles use
  brand tints, e.g. `color-mix(in srgb, var(--brand-primary) 10%, white)`.

## 9. Gotchas (bit us; save the time)
- **CodeArtifact/nhforms 401 blocks new backend deps.** `uv lock`/image build re-resolves the private
  `nhforms` index and 401s. → Prefer **no-new-dependency** solutions (that's why real-time is Postgres
  NOTIFY, not Redis). Only add a backend dep once an admin fixes CodeArtifact auth.
- **`hrms/backend/scripts/` is NOT volume-mounted** (only `hrms/backend/app/` + `alembic/`). To run an edited seed:
  `docker cp hrms/backend/scripts/seed_dev.py hrms-api-1:/code/scripts/` then `uv run python -m scripts.seed_dev`.
- **`.env` / compose `env_file` changes need `docker compose up --force-recreate`** (a plain restart
  doesn't reload env).
- **New SQLAlchemy models must be registered** in `hrms/backend/app/models/__init__.py` or Alembic/app won't see them.
- **Watch column lengths** on admin-owned tables (e.g. `pubnub_timetoken` varchar(30) — don't store wamids there).
- Run Postgres/psql via the container: `docker exec hrms-db-1 psql -U postgres -d hrms_dev -c "…"`
  (compose `db` service). Backend tests: `docker compose exec api uv run pytest`.
