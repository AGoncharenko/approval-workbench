# Assumptions and decisions

## Assumption ledger

| Assumption | Why it was necessary | Risk if wrong | How to validate in a real product |
| --- | --- | --- | --- |
| Drafts are private to their author. Admins and approvers see only submitted invoices, plus the full audit trail. | The brief says users see invoices "available to their company and role" and that admins "inspect the audit history", but it never defines who sees drafts. Drafts are unsubmitted work in progress with no audit events, and nobody but the author can act on them. | Admins can't spot forgotten drafts nearing their due date, which is an oversight gap for AP. | Ask AP admins whether unsubmitted drafts matter to their oversight. If they do, add a read-only admin "Drafts" view rather than widening the general visibility rule. |
| An invoice total is between 0 and 99,999,999,999,999 minor units (USD 999,999,999,999.99; the cap is in minor units, so it is ¥99.9 trillion for JPY and BHD 99.9 billion). Negative totals (credit notes) are out of scope. | The brief asks for exact money but sets no range. Without a cap, a typo or a forged value could store an absurd amount, and integers past 2^53 lose precision in any JavaScript or JSON consumer. This cap is far above any real AP invoice, fits easily in `bigint`, and stays below 2^53. One limit is enforced in three places: `Money::MAX_MINOR_UNITS`, the form parser and a DB CHECK. | A legitimate invoice is refused (very unlikely at this size), or credit notes, which are common in AP, cannot be entered. | Check the largest real invoice and the credit-note volume with AP. If credit notes are needed, model them as their own document type rather than allowing negative totals. A per-currency cap would only matter if a single cap proved too loose or too tight in practice. |
| An invoice needs one approval: a single approver's approve or reject is final. | The brief suggests `PENDING → APPROVED` or `REJECTED` and doesn't define approval chains. One step keeps the state machine small, and the concurrency and audit rules are the same either way. | Real AP often needs two approvers or amount-based limits, so a single click could approve a large invoice. | Ask AP for their approval matrix. Multi-step policies are listed under omissions; the version check and audit already cover each step. |
| Each user belongs to exactly one company, and the company comes from the user record. | A company is the tenant boundary. Taking it from the signed-in user, never from the request, removes a whole class of tenant-switching bugs. | Shared-service accountants who work for several companies would need separate accounts. | Ask whether any users span companies. If so, add memberships with an explicit, audited company switch that re-scopes the session. |
| Demo sign-in is email plus one shared, published password for synthetic accounts. | The brief allows simplified login. Reviewers need to sign in as each role without accounts or secrets. | Anyone who knows the password can act as any demo user, so this protects nothing beyond synthetic data. | Replace it with OIDC SSO (see the README trust boundary). `DEMO_PASSWORD` can change the hosted preview's password meanwhile. |
| Approvers and admins see every submitted invoice in their company; there are no per-approver queues. | The brief asks for company- and role-based visibility only. | Large teams can't split the work, and an approver can see invoices outside their area. | Ask AP how work is assigned. Add assignment or cost-centre scopes inside the company scope, not instead of it. |

## Key decisions

### Decision: Plain deterministic seeds, not FactoryBot

- Context: Demo data must back a five-minute demo path with exact names. It must load on the production image deployed to Render, at boot with no shell and must never contradict the audit invariant.
- Options considered: (a) FactoryBot factories called from `db/seeds.rb`; (b) plain `db/seeds.rb` with fixed literals, where non-draft invoices are driven through the real commands.
- Chosen approach: (b). Users and draft invoices use `find_or_create_by!` on natural keys. Submitted, approved and rejected invoices are produced by calling the submit/approve/reject commands with deterministic idempotency keys, so a re-seed replays and doesn't transition again. FactoryBot is used only for spec setup.
- Tradeoffs: Seeds are a bit more verbose than factory calls. Seeding depends on the commands, so it runs after those changes land, and drafts are the only invoices before then.
- Evidence or verification: `spec/seeds_spec.rb` loads the seeds twice with stable counts, versions and audit events. A production-env seed run uses `BUNDLE_WITHOUT=development:test`.

### Decision: Public UUIDv7 identifiers on PostgreSQL 18

- Context: Sequential invoice ids in URLs let any user enumerate ids and infer system-wide volume, though scoping already blocks access across companies.
- Options considered: (a) bigint ids in URLs; (b) UUID primary keys everywhere; (c) bigint PKs plus a public `uuid` column on companies and invoices.
- Chosen approach: (c). The column is `uuid uuid NOT NULL DEFAULT uuidv7()` with a unique index, using the native `uuidv7()` added in PostgreSQL 18. `to_param` returns it, and lookups use `find_by!(uuid:)` inside the tenant/visibility scope. The company is never read from a URL.
- Tradeoffs: Two identifiers per record. UUIDv7 reveals the creation time to the millisecond (acceptable). Requires PG 18 locally, in CI, in compose (where the PG 18 image volume path changes to `/var/lib/postgresql`) and on Render (18 is the default).
- Evidence or verification: Request specs check that a sequential id in the URL returns 404, a company B UUID returns 404, and the rendered pages contain no sequential ids.

### Decision: Admin role management page with audited changes

- Context: The brief's "user loses approver permission while the page is open" case needs a way to revoke a role during the demo, and revoking approval authority is itself security-relevant.
- Options considered: (a) a `bin/rails runner` one-liner; (b) a `users:set_role` rake task; (c) an admin-only `/admin/users` page (index plus inline role update, no show or edit pages).
- Chosen approach: (c). Role changes are made by `ChangeUserRole`, which locks the company row, refuses self-changes and refuses to remove the last admin, and writes an append-only `role_change_events` row in the same transaction. The rake task was dropped, so there is one audited path for role changes.
- Tradeoffs: More code than a rake task (a controller, a service, a table, a view and specs). Concurrent edits to the same user are last-write-wins, which is safe because setting a role gives the same result however often it's repeated, and every change is audited.
- Evidence or verification: Service, concurrency, request and system specs: self-change 403, last-admin 422, mutual demotion leaving 1 admin, another company's user 404, and a revoked approver refused without signing out.

### Decision: Render free tier instead of Kamal

- Context: Reviewers should be able to click a hosted preview, and the brief also asks for a reproducible deployment. Kamal needs a VPS, a registry and SSH that reviewers don't have.
- Options considered: (a) Kamal on a VPS; (b) Render free tier with the Docker runtime; (c) both.
- Chosen approach: (b), plus a Docker Compose fallback. A `render.yaml` Blueprint defines a free web service and a free Postgres 18 database. The free tier has no shell, pre-deploy or workers, so migrations and idempotent seeds run in the entrypoint at boot, Solid Queue runs inside Puma, and Solid Cache, Queue and Cable share the single database. Kamal was removed (`--skip-kamal`) so there is one deploy path.
- Tradeoffs: The instance sleeps after 15 minutes idle (about 1 minute to wake). The free database expires after 30 days plus a 14-day grace and has no backups, so it holds synthetic data only and the Blueprint recreates it. A single 512 MB instance.
- Evidence or verification: `/up` returns 200 on the preview after a fresh Blueprint deploy. Redeploys keep data without duplicating seeds. Compose boots the same image locally.

### Decision: Append-only audit enforced in the database, with `db/structure.sql`

- Context: Audit events must never change or disappear. Model guards such as `readonly?` are bypassed by `update_all`, `delete_all`, raw SQL and the console. Admins also need one history across invoice decisions and role changes.
- Options considered: (a) model guards only; (b) PostgreSQL triggers that refuse UPDATE and DELETE on both event tables, plus an `audit_entries` view (UNION ALL) for the history page; with (b), either keep `schema.rb` and add the `scenic` and `fx` gems, or switch the schema dump to `structure.sql`.
- Chosen approach: (b) with `structure.sql`. `schema.rb` can't represent functions, triggers or views. Rails builds test, CI and fresh production databases (`db:prepare` on Render's empty database) by loading the schema file, not by replaying migrations, so with `schema.rb` those databases would silently lack the protection. The production cache, queue and cable databases keep `schema_format: ruby` for Rails' own Solid schema files.
- Tradeoffs: `structure.sql` diffs are noisier. Dumping needs `pg_dump` and loading needs `psql` (the Docker image installs `postgresql-client`). The PG 18 dump uses settings that older servers reject, so every environment must run PG 18. TRUNCATE and the table owner can still bypass the triggers; real tamper-proofing needs a separate DB role without those rights.
- Update (change 7, `add-deployment-and-ops`): the separate production cache, queue and cable databases, and their `schema_format: ruby`, are gone. Their tables are now regular migrations on the primary database, so they are in `structure.sql` too (see the single-database decision below).
- Evidence or verification: `spec/db/audit_append_only_spec.rb` shows `update_all`, `delete_all` and raw SQL refused on both tables with rows unchanged. Rolling back and re-running the migrations regenerates a byte-identical `structure.sql`.

### Decision: Optimistic expected version, plus a short row lock inside the command

- Context: Two approvers can open the same invoice version and decide seconds apart. The brief requires that a stale approval never silently applies.
- Options considered: (a) pessimistic locks held while the user reads the page; (b) a row lock inside the command only, with no version from the client; (c) the client sends the `expected_version` it reviewed, and the command locks the row (`FOR UPDATE`), compares and bumps the version in one transaction.
- Chosen approach: (c). Locks last milliseconds, never across a user's think time. The version check means a decision applies only to the state the user actually saw.
- Tradeoffs: The user who loses a race must re-read and decide again. The 409 page shows the current status, version and last actor to make that quick.
- Evidence or verification: `spec/services/transition_invoice_concurrency_spec.rb` (two threads, one applies, one conflicts) and `spec/system/approval_conflict_spec.rb`.

### Decision: Idempotency keys for retries, separate from the version check

- Context: Browsers, proxies and users retry. A retried approval must not be reported as a conflict with itself, or applied twice.
- Options considered: (a) rely on the version check alone; (b) a per-form idempotency key, claimed with `INSERT … ON CONFLICT DO NOTHING` in the same transaction as the transition.
- Chosen approach: (b). The key answers "is this the same request again?" and the version answers "did the user see the current state?". A replay returns the original outcome and time. A key reused with a different payload (by fingerprint) is refused with 422. A failed command rolls the key back with everything else.
- Tradeoffs: One more table and a unique index. Keys never expire yet (see omissions).
- Evidence or verification: `spec/requests/transitions_spec.rb` (replay with the original time; reused key) and `spec/system/approval_network_failure_spec.rb` (response lost after commit, then Retry).

### Decision: Audit event written in the same transaction as the transition

- Context: The audit trail must say who did what and when, and must never disagree with the invoice's status.
- Options considered: (a) an after-commit callback or job that writes the event; (b) insert the event inside the transition's transaction.
- Chosen approach: (b). The status update, the version bump and the `approval_events` row commit or roll back together. The event stores the actor's role at that moment.
- Tradeoffs: Notifications built on events need an outbox later; they can't be sent from inside the transaction.
- Evidence or verification: `spec/services/transition_invoice_spec.rb` (a forced event-insert failure leaves the status and version unchanged) and `spec/db/audit_append_only_spec.rb`.

### Decision: Refusal precedence 404, then 403, then 409

- Context: A refused command can reveal information. Saying "conflict" or "forbidden" for another company's invoice would confirm that it exists.
- Options considered: (a) check state first; (b) check visibility, then permission, then state and version.
- Chosen approach: (b). Not visible to this actor gives 404 (the same page as a missing record). Visible but not allowed gives 403. Allowed but the status or version changed gives 409.
- Tradeoffs: A demoted approver gets "not available" rather than a role-specific message, because requesters can't see others' invoices.
- Evidence or verification: the precedence cases in `spec/services/transition_invoice_spec.rb` and `spec/requests/transitions_spec.rb` (404, not 403 or 409, for another requester's stale invoice).

### Decision: Realtime refresh signals carry no data

- Context: Open pages should show other users' decisions, but a realtime channel is another way to leak data across tenants or roles.
- Options considered: (a) broadcast rendered rows or JSON; (b) broadcast a bare Turbo "refresh" to the company stream, after commit, so each page re-reads itself under its own session.
- Chosen approach: (b). The message has no content. Pages morph, so typed reasons and the version the user reviewed survive. A signal that arrives before the command's own response is harmless, because it only prompts a re-read.
- Tradeoffs: Every viewer re-requests the page on each change, which is fine at this scale.
- Evidence or verification: `spec/models/invoice_broadcast_spec.rb`, `spec/channels/application_cable/connection_spec.rb` and `spec/system/realtime_refresh_spec.rb`.

### Decision: One production database for the app and Solid Cache, Queue and Cable

- Context: Render's free tier gives one Postgres database. Rails 8 generates separate cache, queue and cable databases.
- Options considered: (a) extra databases inside the one Render instance; (b) convert the Solid schema files into regular migrations on the primary database.
- Chosen approach: (b). `config/database.yml` production reads `DATABASE_URL` only. The `connects_to` settings are removed. Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA=1`) and polls every second. The production pool is threads plus 2, because Solid Queue's worker needs that many.
- Tradeoffs: Cache and queue load shares the app's database and connection limit (100 on free). This is fine for one small instance.
- Evidence or verification: `RAILS_ENV=production bin/rails db:prepare` on an empty PG 18 creates all 15 `solid_*` tables in one database. The compose boot starts Puma with the Solid Queue supervisor, worker, dispatcher and scheduler. `grep -ri redis config` is empty.

## Time-box decisions

- **What I intentionally simplified:**
  - password sign-in with published demo credentials;
  - one approval step;
  - one company per user;
  - offset pagination with a "next page" link (25 invoices, 50 audit rows per page) and no total count;
  - a single free Render instance that migrates and seeds at boot;
  - seeds as plain Ruby.
- **What I refused to simplify, because it protects a core invariant:**
  - tenant scoping from the session on every query;
  - the 404/403/409 order;
  - integer minor units with currency;
  - the expected version plus idempotency key on every transition;
  - the audit event in the same transaction;
  - append-only audit tables enforced by the database;
  - PostgreSQL 18 everywhere, so the schema file loads the same in dev, CI, compose and Render.
- **What I would build next with more time:** an outbox with duplicate-tolerant notifications, then multi-step approval policies.
- **What I would reconsider before production:**
  - SSO instead of passwords;
  - session expiry;
  - a separate DB role so the app can't TRUNCATE the audit tables;
  - paid hosting with backups and a pre-deploy migration step instead of migrating at boot.

## Deliberate omissions and next steps

| Omitted | Next step |
| --- | --- |
| Outbox and notifications | Write an `outbox` row in the transition's transaction. A Solid Queue job delivers it with a dedupe key, so retries don't notify twice. |
| Multi-step policies and approval limits | Model a policy per company (amount bands, number of approvers). Each approval is a version-checked, audited step, and the invoice is approved when the policy is satisfied. |
| Delegation | Time-boxed, audited delegations. The audit event records both the delegate and the delegator. |
| Feature flags, metrics and tracing | Add flags for risky rollouts, and OpenTelemetry traces plus metrics for decision latency and conflict, replay and refusal rates, keyed by the existing request id. |
| Postgres row-level security | Add RLS policies on `company_id`, set per transaction from the session, as defence in depth behind the application scopes. |
| Keyset pagination | Paginate the list and the audit history by `(due_date, id)` and `(created_at, id)` keys instead of offsets, so deep pages stay fast and rows don't shift while paging. |
| Idempotency-key expiry | A recurring job deletes keys older than a retry window (for example 24 hours). |
| SSO | OIDC sign-in mapped to existing users, with the same server-side session afterwards (see the README trust boundary). |
| Paid-plan backups | A paid Render Postgres with point-in-time recovery, a pre-deploy command for migrations, and a restore drill. Until then, a manual `pg_dump` (README). |
| Session expiry and cleanup | The generator's cookie is permanent, so sessions last until sign-out. Add an idle and an absolute timeout, plus a recurring Solid Queue job that deletes expired `sessions` rows. |

Every non-negotiable behaviour in the brief maps to a spec requirement and an RSpec file in the README's [brief traceability table](README.md#brief-traceability).
