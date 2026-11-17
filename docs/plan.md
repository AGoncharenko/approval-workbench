# H1 Approval Workbench — Rails 8.1 + Postgres 18 + OpenSpec + Render

> **Planning-stage snapshot** (2026-11-16), taken before any application code was written. The OpenSpec changes in `openspec/` are the source of truth and are kept current; this file is not updated during implementation. The assignment brief mentioned below (`docs/brief/`) is kept local and is not published in this repository.

## Context
This is a take-home for an accounts-payable invoice approval workbench. The brief and the candidate guide are in `docs/brief/`. Goal: requesters submit invoices, approvers approve or reject them, and admins manage roles and inspect the audit trail. Throughout, the app must keep these rules:
- tenant isolation;
- server-side authorization;
- exact money;
- an atomic audit trail;
- no silent stale or duplicate actions.

**The OpenSpec changes in `openspec/changes/` are the source of truth.** This plan only summarises them.

Choices:
- Time box: extended, about 1-2 days.
- UI: Hotwire, server-rendered.
- Process: OpenSpec SDD. Context and invariants live in `openspec/config.yaml`.
- Deploy: Render free tier (Docker runtime, `render.yaml` Blueprint), with a Docker Compose fallback. No Kamal.

Toolchain:
- Ruby 4.0.9 (rbenv, `.ruby-version`), Rails 8.1.4.1.
- PostgreSQL 18.7 for native `uuidv7()`. Postgres.app (all-versions build) runs it on **port 5433**, and 17.12 stays on 5432 for other projects. Dev and test use `PGPORT` with a default of 5433. CI uses 5432 and production uses `DATABASE_URL`.
- Node 24, openspec 1.16.0, Docker 28.3.

Current repo state: only `docs/brief/`, `openspec/`, `DECISIONS.md`, `.claude/`, `.idea/` and `.ruby-version`. The first skeleton was deleted, because it was generated with `--skip-bundle`, so it had no lockfile, no Solid install and Redis cable. Change 1 task 0.0 regenerates it with `--skip-kamal`, with bundling enabled. No git repo exists until then. All 7 changes are written and pass `openspec validate --all --strict`.

## Workflow
For each change, in order: implement its tasks.md, check each item's verification step, run `bundle exec rspec`, then `openspec archive <change>`.

| # | Change | Capabilities |
|---|---|---|
| 1 | `add-tenancy-and-demo-auth` | `tenancy`, `authentication`, `demo-data` (plus app generation and the RSpec/FactoryBot harness) |
| 2 | `add-invoice-review` | `invoices` (list, detail, money, visibility, terminal statuses, accessible states) |
| 3 | `add-approval-commands` | `approvals` (approve/reject, refusal precedence, version check, idempotency, atomic audit, unknown-outcome UX) |
| 4 | `add-invoice-submission` | `invoice-submission`, `demo-data` delta (drafts, exact amount parsing, submit, seeds through real commands) |
| 5 | `add-admin-area` | `audit` (append-only, `/admin/audit_events`), `user-roles` (`/admin/users`) |
| 6 | `add-realtime-refresh` | `realtime` (data-free refresh signal, re-read under the viewer's session) |
| 7 | `add-deployment-and-ops` | `operations` (Render Blueprint, single-DB Solid, compose, `/up`, logs, CI) plus README/DECISIONS submission docs |

## Data model
- `companies(id bigint, uuid uuidv7 UNIQUE, name)`
- `users(id, uuid, company_id, name, email_address, password_digest, role CHECK requester|approver|admin)`: unique `(company_id, id)`.
- `sessions(id, user_id FK ON DELETE CASCADE, ip_address, user_agent)`
- `invoices(id, uuid, company_id, vendor_name, total_minor_units bigint CHECK 0..99999999999999, currency char(3), due_date, status CHECK, version int, submitted_by)`: unique `(company_id, id)`.
- `approval_events(company_id, invoice_id, actor_id RESTRICT, actor_role, action, from_status, to_status, reason, created_at)`: composite FK to `invoices(company_id, id)`, append-only trigger.
- `role_change_events(company_id, actor_id, target_user_id, from_role, to_role, created_at)`: composite FKs to `users(company_id, id)`, append-only trigger.
- `idempotency_keys(company_id, user_id, key, fingerprint, approval_event_id)`: unique `(company_id, user_id, key)`.
- View `audit_entries` = `UNION ALL` of both event tables (read-only).

## Core design (details in each change's design.md)
- **Identity and tenancy:**
  - Rails 8 auth generator, password reset removed. Server-side sessions with an opaque cookie.
  - `Current.user` is re-read every request, and every query starts from `Current.company`.
  - Public UUIDv7 in URLs. Bigint PKs and FKs stay internal.
- **Refusal precedence:** not visible → 404; visible but not allowed → 403; state or version changed → 409.
- **Visibility:**
  - requesters see their own invoices, including drafts;
  - approvers and admins see non-draft invoices;
  - drafts are author-only.
- **`app/services/transition_invoice.rb`:** one transaction:
  1. claim the idempotency key (`INSERT … ON CONFLICT`, then replay or 422);
  2. load the invoice through the scope `FOR UPDATE`;
  3. run the policy check;
  4. check status and version;
  5. update and bump the version;
  6. insert the event and commit.

  It covers submit, approve and reject. Segregation of duties: an author can never decide on their own invoice, and admins can't decide at all.
- **`app/services/change_user_role.rb`:** a company-row lock, no self-change, at least one admin kept, and an audited change.
- **Money:** integer minor units plus ISO currency. `Money.parse` and `format` with an exponent table. No Float, no rounding.
- **Realtime:** `broadcast_refresh_to company, :invoices` (synchronous, with no job dependency) carries no data. Turbo morphs, and the decision form is `data-turbo-permanent`.
- **Unknown outcome:** a Stimulus notice, then Retry with the same idempotency key.
- **Seeds:** plain `db/seeds.rb`.
  - 2 companies, each with a requester, 2 approvers and an admin.
  - About 15 drafts with relative due dates.
  - Non-drafts are produced through the real commands with `seed:` keys.
  - `DEMO_PASSWORD` can be overridden.
- **Rejected:** ActiveAdmin, Devise, CanCanCan, audit gems (paper_trail, audited, logidze), FactoryBot in seeds, UUID primary keys, a rake task for roles.

## Testing
RSpec plus FactoryBot (synthetic factories, `FactoryBot.lint`), with Capybara and headless Chrome system specs. The highest-risk specs:
- cross-tenant 404s on every route;
- the refusal precedence matrix;
- multi-threaded concurrency for transitions and for mutual admin demotion;
- idempotent replay and fingerprint mismatch;
- audit atomicity under a forced failure;
- the append-only triggers;
- seeds idempotent and history-consistent;
- a network failure after commit;
- the two-approver conflict and role revocation, as system specs.

## Deployment
- **Render (free):** a `render.yaml` with a Docker web service (`dockerCommand: ./bin/rails server`, `healthCheckPath: /up`, `WEB_CONCURRENCY=0`, `SOLID_QUEUE_IN_PUMA=1`) and free Postgres 18 (`DATABASE_URL` from `connectionString`).
- **Free-tier constraints:** there's no shell or pre-deploy, so the entrypoint runs `db:prepare` and `db:seed` at boot. Solid Cache, Queue and Cable share the one database, with queue polling at 1 s. The app sleeps after 15 minutes. The database expires after 30 days plus 14 and has no backups.
- **Secrets:** `RAILS_MASTER_KEY` and `DEMO_PASSWORD` are `sync: false`, entered on Render. There are no secrets in git.
- **Migrations:** expand/contract. Rollback uses Render's dashboard rollback, or `git revert` if that isn't available on free.
- **Compose fallback:** production mode with a local-only `SECRET_KEY_BASE`, seeded automatically.
- **Health and logs:** `/up` returns 503 when the DB is down. Logs carry request id, user and company ids, with secrets filtered.
- **CI:** GitHub Actions with RSpec on PG 18, Chrome, RuboCop, Brakeman and bundler-audit.

## Docs
- README from the template: demo path, scope and time box, trust boundary, AI tools, and a brief-to-spec traceability table.
- DECISIONS.md: ledger, decisions, omissions and next steps.

## Deliberate omissions
- multi-step policies and approval limits;
- delegation;
- SSO;
- payments;
- outbox and notifications;
- feature flags, metrics and tracing;
- RLS;
- user lifecycle;
- mobile client.

## Verification
1. `bundle exec rspec` is green, and so are CI and `openspec validate --all --strict`. After archiving, `openspec list --specs` shows 10 capabilities.
2. The README five-minute demo, run against the Render preview and `docker compose up --build`:
   - sign in per role;
   - cause the two-approver conflict;
   - try a company B UUID from company A and get 404;
   - as admin, demote an approver on `/admin/users`; the open approval gets "no longer available";
   - check `/admin/audit_events`.
3. `curl -fsS localhost:3000/up` returns 200.
4. Render: the Blueprint is accepted, and on the preview URL `/up` returns 200 and the demo path works. The first deploy needs a pushed GitHub repo and your Render account, with your go-ahead.
