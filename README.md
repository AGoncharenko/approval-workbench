# Approval workbench

An accounts-payable invoice approval workbench. Requesters submit invoices, approvers approve or reject them, and admins manage roles and read the audit history. Built with Rails 8.1, Ruby 4.0, PostgreSQL 18 and Hotwire. All data is synthetic.

## Demo

- **Preview URL:** TODO(user): the Render URL after the first Blueprint deploy (for example `https://workbench-xxxx.onrender.com`). The free database expires 30 days after it is created (see [Deploy runbook](#deploy-runbook)). If the preview is gone, use the compose command below.
- **Setup/run command if no preview:** `docker compose up --build`, then open <http://localhost:3000>. It needs Docker only: no account and no secret.
- **Demo password:** every seeded account uses `demo-password-2026`, unless `DEMO_PASSWORD` was set when the seeds ran. On the hosted preview it is the value entered on Render.

### Five-minute demo path

1. **Wake the preview.** Open `/up` about a minute before the demo. The free instance sleeps after 15 minutes idle, and the first request takes about a minute. A blank 200 page means the app and the database are up.
2. **Sign in as each role.** Use a private window per account (sessions are per browser).
   - `requester@acme.example.com` sees only their own invoices, drafts included, and can create and submit a draft.
   - `approver1@acme.example.com` sees Acme's submitted invoices, but no drafts and nothing from Globex.
   - `admin@acme.example.com` additionally sees **Users** and **Audit history** in the header. Admins can't decide invoices.
3. **Cause a two-approver conflict.** Sign in as `approver1@acme.example.com` in one window and as `approver2@acme.example.com` in another. Both open the pending *Northwind Office Supply* invoice (version 2). In the second window, type a reason in **Reason for rejection** but don't submit. Approve in the first window. The second window refreshes by itself: the status becomes *Approved (not paid)*, and the typed reason and the version it reviewed are kept. Now click **Reject** there. It gets *"Not applied: this invoice changed since you opened it…"* with the current status, version and approver. The audit history shows only the one approval.
4. **Try another company's invoice.** As `approver1@globex.example.com`, open any Globex invoice and copy its URL (it ends in a UUID). Paste it into an Acme window. Acme gets *"Invoice not available"* (404), the same page as for a UUID that doesn't exist.
5. **Check the audit history.** As `admin@acme.example.com`, open **Audit history** (`/admin/audit_events`). The approval from step 3 is listed with actor, role, statuses and time. Seeded submits, approvals and rejections are there too.
6. **Revoke a role while a page is open.** As `approver2@acme.example.com`, open the pending *Kumo Translation KK* invoice and leave it open. As the admin, open **Users** (`/admin/users`), set Blair Approver's role to *Requester*, and click **Save role**. Back in the approver's window, click **Approve**. The server re-reads the role and answers *"Invoice not available"*, and the invoice stays pending. **Audit history** now shows the role change.

## Chosen scope

- **Declared time box:** extended, 1-2 days.
- **Approximate time spent:** TODO(user): actual hours. The git history covers about 15 hours of wall-clock time, from the first spec commit on 2026-11-16 to this change.
- **Scope:** extended.
- **Completed:**
  - all four core outcomes;
  - requester, approver and admin experiences;
  - draft creation with exact amount parsing;
  - expected-version conflicts and idempotent retries;
  - an append-only audit trail;
  - admin role management;
  - content-free realtime refresh;
  - accessible list, detail, empty, conflict and failure states;
  - a Render Blueprint, a Docker Compose fallback, a health check, tagged and filtered logs, and CI.
- **Deliberately omitted:** multi-step policies and approval limits, delegation, SSO, payments, an outbox and notifications, feature flags, metrics and tracing, Postgres RLS, and a mobile client. See [DECISIONS.md](DECISIONS.md#deliberate-omissions-and-next-steps).

## Run locally

### Start

Option 1: **Docker Compose** (production mode, no local Ruby or PostgreSQL needed).

```sh
docker compose up --build        # app on http://localhost:3000
APP_PORT=3001 docker compose up --build   # if port 3000 is taken
docker compose down -v           # stop and delete the local database
```

The app container runs the same image as Render. Its entrypoint migrates and seeds before Puma starts. Compose uses a `SECRET_KEY_BASE` that is published in `docker-compose.yml` and labelled local-only. It turns off the HTTPS redirect for plain-HTTP localhost. Its Postgres publishes no host port.

Option 2: **Native.** Needs Ruby 4.0.9 (`.ruby-version`) and PostgreSQL 18. Dev and test expect PostgreSQL on `localhost:5433`; override it with `PGPORT`.

```sh
bundle install
bin/rails db:prepare db:seed
bin/dev                          # http://localhost:3000
```

### Test and verification

```sh
bundle exec rspec                # full suite, including system specs in headless Chrome
bin/rubocop
bin/brakeman -q
bin/bundler-audit
openspec validate --all --strict # specs in openspec/ (needs the openspec CLI)
```

CI (`.github/workflows/ci.yml`) runs on every push and pull request: RSpec against a `postgres:18` service with Chrome, RuboCop, Brakeman, bundler-audit and the importmap audit.

## Approach

- **Architecture and source of truth:** a Rails monolith with server-rendered Hotwire pages. PostgreSQL is the only source of truth.
  - Every state change goes through one service, `TransitionInvoice`, in one transaction: claim the idempotency key, lock the invoice through the actor's visibility scope, check the policy, check status and version, update, and write the audit event.
  - Realtime messages carry no data. They only tell open pages to re-read their own view under the viewer's session.
  - Behaviour is specified first, as OpenSpec requirements in `openspec/specs/`. Each requirement is proved by RSpec (see [Traceability](#brief-traceability)).
- **Most important domain/security invariant:** a user only ever reads or changes their own company's records, and only what their current role allows.
  - The company comes from the signed-in user, never from a URL, form field or client state.
  - Each query starts from the user's company and role scope, so another company's invoice is a 404, the same as a missing one.
  - The server re-reads the role on every command. The refusal order is 404 (not visible), then 403 (visible but not allowed), then 409 (status or version changed).
- **Most important tradeoff:** optimistic `expected_version` checks plus idempotency keys, rather than holding locks across the user's think time.
  - A stale decision is refused with the current state, and a retried request is replayed, never applied twice.
  - The cost is that a user who loses a race has to re-read and decide again.
- **Deployment approach and known limitation:** Render free tier, from a versioned `render.yaml` Blueprint (Docker web service plus a free Postgres 18 database), and a Docker Compose fallback with the same image.
  - The free tier has no shell, pre-deploy step or workers. So the entrypoint migrates and seeds at boot, Solid Queue runs inside Puma, and Solid Cache, Queue and Cable share the one database.
  - Limits: the instance sleeps after 15 minutes idle (about 1 minute to wake). The free database expires after 30 days (deleted after a further 14) and has no backups. There is one 512 MB instance.

### Trust boundary

- **Trusted:**
  - the server-side session, found by an opaque, signed, HttpOnly cookie;
  - the user, role and company the server reads from the database on every request.
- **Not trusted:**
  - URL ids;
  - request bodies, including hidden fields such as `expected_version` and `idempotency_key` (they are inputs to check, never authority);
  - which buttons were shown;
  - realtime signals, which only prompt a re-read.
- **Demo authentication:** email and password against seeded accounts. The demo password is public on purpose and protects only synthetic data. On Render, `DEMO_PASSWORD` can replace it.
- **Production path:** replace password sign-in with OIDC SSO against the customer's identity provider. The callback would map the verified subject to a `users` row (company plus role), then create the same server-side session. Everything after sign-in stays unchanged, because authorization already re-reads role and company from the database.

## Development tools

- **Editor, CLI, frameworks and test harnesses:**
  - RubyMine, and Claude Code in the terminal;
  - Rails 8.1 generators;
  - RSpec, FactoryBot, Capybara with headless Chrome;
  - RuboCop (rails-omakase), Brakeman, bundler-audit;
  - OpenSpec CLI for spec-first changes;
  - Docker Compose;
  - GitHub Actions.
- **AI, model and agents used:**
  - Claude Code with Claude Opus 5.5.
  - The work was spec-first with OpenSpec. Seven changes were written and validated before any code (see `docs/plan.md`).
  - A subagent implemented each change against its `tasks.md`. A separate reviewing session reran the gates (RSpec, RuboCop, Brakeman, `openspec validate`) and checked the behaviour in a browser before each change was committed and archived.
- **Important contributions, assumptions and corrections:**
  - **Contribution:** the AI proposed moving the audit tables' append-only guarantee into PostgreSQL triggers. That forced `db/structure.sql`, because `schema.rb` would have built test, CI and fresh production databases without the triggers. This is recorded in `DECISIONS.md`.
  - **Failure caught in review:** in change 6 (realtime refresh), the decision form kept the version it was first rendered with, even after a 409 conflict. So every retry from that page conflicted again. The reviewing session spotted it while reading the code, then reproduced it with a failing system spec before fixing it; a follow-up browser check found the shown version disagreeing with the hidden one, fixed the same way. That spec is in `spec/system/realtime_refresh_spec.rb`.
  - **Failure caught in this change:** the first version of the log-tagging `around_action` used `logger.tagged { … }`. With more than one log sink, Rails' `BroadcastLogger` runs that block once per sink, so the action ran twice (`DoubleRenderError`). `spec/requests/logging_spec.rb` caught it, and the code now uses `push_tags`/`pop_tags`.
  - **Verification:** every task in `openspec/changes/*/tasks.md` has a "Verify:" step, and is ticked only after it passes. The full suite, RuboCop and Brakeman ran before each commit.

## Deploy runbook

### First deploy (Render Blueprint)

1. Push the repository to GitHub.
2. In Render, choose **New → Blueprint** and pick the repository. Render reads `render.yaml` and proposes:
   - `workbench-db`: free PostgreSQL 18;
   - `workbench`: a free Docker web service, built from `Dockerfile`, started with `./bin/rails server`, health check `/up`.
3. Enter the two secrets Render asks for (they are `sync: false`, so they are never in git):
   - `RAILS_MASTER_KEY`: the contents of your local `config/master.key`;
   - `DEMO_PASSWORD`: the demo password you want to publish to reviewers.

   `DATABASE_URL` is filled from the database's connection string.
4. Apply. On start, the entrypoint runs `db:prepare` (loads `db/structure.sql` on the empty database) and `db:seed`, then starts Puma on `$PORT`. Render routes traffic only once `/up` returns 200.

- **Database created on:** TODO(user): date of the first Blueprint deploy. It expires 30 days later and is deleted after a further 14-day grace period.

### Later deploys and migrations

- A push to the default branch auto-deploys. The new version takes traffic only after its `/up` passes, so a version that fails its health check leaves the previous one serving.
- Migrations run at boot and must be **expand/contract only**: add columns and tables first, backfill, switch the code, and drop the old ones in a later deploy. That way the previous version still runs against the current schema, and a rollback never needs a schema rollback.
- Seeding on every boot is idempotent, so redeploys don't duplicate demo data and keep the audit history.

### Rollback

- In the Render dashboard, go to **workbench → Events/Deploys**, pick an earlier successful deploy, and click **Rollback**. Render's docs say free services can roll back to the two most recent previous deploys.
- A dashboard rollback turns auto-deploy off. Turn it back on once the fix is pushed.
- If rollback isn't offered, run `git revert <bad commit>` and push. That deploys the previous code forward.

### Free-tier limits

| Limit | Effect | What to do |
| --- | --- | --- |
| Sleeps after 15 minutes without traffic | The first request takes about 1 minute | Open `/up` a minute before a demo |
| Free Postgres expires 30 days after creation, then is deleted after 14 more days | The preview stops working | Recreate it from the Blueprint; boot re-seeds the demo data |
| No backups on free Postgres | Data loss on expiry or incident | Data is synthetic; take a manual dump (below) if you need one |
| 0.1 CPU, 512 MB, one instance | Slow cold starts; no high availability | Single-process Puma (`WEB_CONCURRENCY=0`, 3 threads) |
| No shell, pre-deploy step or workers | No one-off commands | Entrypoint migrates and seeds; Solid Queue runs in Puma (`SOLID_QUEUE_IN_PUMA=1`) |

### Logs

Logs go to STDOUT and appear in the service's **Logs** tab.

- Every request line is tagged with its request id (also returned as the `X-Request-Id` header).
- Lines logged inside an authenticated action also carry `user=<uuid>` and `company=<uuid>`.
- Passwords, tokens and idempotency keys show as `[FILTERED]`.
- To trace an approval, search for its request id.
- `/up` requests are not logged.

### Manual backup

Copy the **External Database URL** from the database's page in the dashboard, then run, with a `pg_dump` 18 client:

```sh
pg_dump "$EXTERNAL_DATABASE_URL" > backup.sql
```

## Brief traceability

Each non-negotiable behaviour and edge case from the brief, with the spec requirement that states it and the RSpec file that proves it. Requirements live in `openspec/specs/<capability>/spec.md`.

| Brief item | Spec requirement | Proved by |
| --- | --- | --- |
| No cross-company read or change by URL, body or client state | tenancy: *Cross-tenant records are indistinguishable from missing records*; *Unguessable public identifiers* | [spec/requests/tenancy_spec.rb](spec/requests/tenancy_spec.rb), [spec/requests/invoices_spec.rb](spec/requests/invoices_spec.rb), [spec/requests/transitions_spec.rb](spec/requests/transitions_spec.rb) |
| Server validates actor and transition; hidden buttons are not enough | approvals: *Eligible decision makers*; *Refusal precedence*; authentication: *Actor re-validated per request* | [spec/services/transition_invoice_spec.rb](spec/services/transition_invoice_spec.rb), [spec/policies/invoice_policy_spec.rb](spec/policies/invoice_policy_spec.rb) |
| Exact minor units with currency | invoices: *Exact money with currency*; invoice-submission: *Exact amount parsing* | [spec/models/money_spec.rb](spec/models/money_spec.rb), [spec/models/invoice_spec.rb](spec/models/invoice_spec.rb) |
| Audit trail says who did what and when | approvals: *Atomic audit of every transition*; audit: *Append-only audit events*, *Actor identity preserved*, *Company audit history for admins* | [spec/services/transition_invoice_spec.rb](spec/services/transition_invoice_spec.rb), [spec/db/audit_append_only_spec.rb](spec/db/audit_append_only_spec.rb), [spec/requests/admin/audit_events_spec.rb](spec/requests/admin/audit_events_spec.rb) |
| Stale or duplicate approval never applies twice | approvals: *Stale commands never apply*; *Idempotent retries* | [spec/services/transition_invoice_concurrency_spec.rb](spec/services/transition_invoice_concurrency_spec.rb), [spec/requests/transitions_spec.rb](spec/requests/transitions_spec.rb) |
| Synthetic demo and test data only | demo-data: *Synthetic-only demo data*; *Idempotent demo data load* | [spec/seeds_spec.rb](spec/seeds_spec.rb), [spec/factories_spec.rb](spec/factories_spec.rb) |
| Edge: two approvers open version 7; one approves, the other rejects | approvals: *Stale commands never apply*; *Honest outcome reporting* | [spec/system/approval_conflict_spec.rb](spec/system/approval_conflict_spec.rb), [spec/services/transition_invoice_concurrency_spec.rb](spec/services/transition_invoice_concurrency_spec.rb) |
| Edge: browser times out after the server commits | approvals: *Honest handling of ambiguous network failures*; *Idempotent retries* | [spec/system/approval_network_failure_spec.rb](spec/system/approval_network_failure_spec.rb) |
| Edge: user loses approver permission with the page open | authentication: *Actor re-validated per request*; user-roles: *Role changes*, *Audited role changes* | [spec/system/admin_role_revocation_spec.rb](spec/system/admin_role_revocation_spec.rb), [spec/requests/admin/role_change_effect_spec.rb](spec/requests/admin/role_change_effect_spec.rb) |
| Edge: company A guesses company B's numeric id | tenancy: *Unguessable public identifiers*; *Cross-tenant records are indistinguishable from missing records* | [spec/requests/invoices_spec.rb](spec/requests/invoices_spec.rb) |
| Edge: realtime event arrives before the command response | realtime: *Change signals carry no data*; *Views refresh from authoritative state* | [spec/system/realtime_refresh_spec.rb](spec/system/realtime_refresh_spec.rb), [spec/models/invoice_broadcast_spec.rb](spec/models/invoice_broadcast_spec.rb) |
| Deployed or reproducibly deployable | operations: *Self-provisioning hosted preview*; *Reproducible local deployment*; *Health check reflects dependencies* | [spec/requests/health_spec.rb](spec/requests/health_spec.rb), [spec/seeds_spec.rb](spec/seeds_spec.rb) |
| Logs that trace a request without leaking secrets | operations: *Traceable, privacy-safe logs* | [spec/requests/logging_spec.rb](spec/requests/logging_spec.rb) |

The `operations` capability is added by the `add-deployment-and-ops` change and joins `openspec/specs/` when that change is archived.

## Demo accounts

Every seeded account uses the demo password `demo-password-2026`, unless `DEMO_PASSWORD` was set when the seeds were loaded.

| Email | Role | Company |
| --- | --- | --- |
| requester@acme.example.com | requester | Acme Industries |
| approver1@acme.example.com | approver | Acme Industries |
| approver2@acme.example.com | approver | Acme Industries |
| admin@acme.example.com | admin | Acme Industries |
| requester@globex.example.com | requester | Globex Trading |
| approver1@globex.example.com | approver | Globex Trading |
| approver2@globex.example.com | approver | Globex Trading |
| admin@globex.example.com | admin | Globex Trading |

## Known limitations and next step

See [DECISIONS.md](DECISIONS.md): the assumption ledger, key decisions, time-box choices, and deliberate omissions with next steps.
