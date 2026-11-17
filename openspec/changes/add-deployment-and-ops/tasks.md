# Tasks

## 1. Health and logging

- [ ] 1.1 `HealthController#show` at `/up`: 200 when the DB responds, 503 when it doesn't, no authentication required. Verify: `spec/requests/health_spec.rb` covers both cases, with the connection error stubbed.
- [ ] 1.2 Request id log tag, user and company UUID tags, and `filter_parameters` with `:idempotency_key`. Verify: `spec/requests/logging_spec.rb` captures the log and checks the tags are present and the password and key are filtered.

## 2. Production configuration

- [ ] 2.1 Single-database production: `database.yml` uses `DATABASE_URL` only. Solid Cache, Queue and Cable schemas become regular migrations on the primary database, with `connects_to` removed. Verify: `RAILS_ENV=production bin/rails db:prepare` against an empty local PG 18 creates all `solid_*` tables in one database.
- [ ] 2.2 `config/queue.yml` polling at 1 s, `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` kept, and `config/cable.yml` production on `solid_cable`. Verify: the production-mode boot from 2.1 starts Puma with Solid Queue and no Redis reference (`grep -ri redis config` is empty).
- [ ] 2.3 `assume_ssl` and `force_ssl` from ENV (default true), with `/up` exempt from the redirect. Verify: `spec/requests/health_spec.rb` expects `/up` over HTTP to return 200, not 301, in a production-like config.
- [ ] 2.4 `bin/docker-entrypoint` runs `db:prepare` then `db:seed` before `exec` for `./bin/rails server`. Verify: two consecutive `docker run` boots against the same DB give a 200 from `/up`, and the seed counts are unchanged after the second.

## 3. Compose fallback

- [ ] 3.1 `docker-compose.yml`: the app plus `postgres:18` (volume at `/var/lib/postgresql`), production mode, SSL flags off and a labelled local `SECRET_KEY_BASE`. Verify: `docker compose up --build` gives `curl -fsS localhost:3000/up` returning 200 and demo sign-in working.

## 4. Render

- [ ] 4.1 `render.yaml` Blueprint:
  - free Postgres 18 database;
  - free Docker web service with `healthCheckPath: /up` and `dockerCommand: ./bin/rails server`;
  - `DATABASE_URL` from `connectionString`;
  - `RAILS_MASTER_KEY` and `DEMO_PASSWORD` as `sync: false`;
  - `WEB_CONCURRENCY=0`, `RAILS_MAX_THREADS=3`, `SOLID_QUEUE_IN_PUMA=1`.

  Verify: the Blueprint is accepted by Render's validation on creation, and `git grep -nE 'RAILS_MASTER_KEY|DEMO_PASSWORD' render.yaml` shows keys only, no values.
- [ ] 4.2 First hosted deploy, done only with the user's go-ahead, because it needs a pushed GitHub repo and the user's Render account. Verify: the preview URL's `/up` returns 200, demo sign-in works, and an approval shows in the admin audit history.
- [ ] 4.3 Check rollback on the free plan: deploy a trivial change, then roll back from the dashboard. Verify: the previous deploy serves traffic. If rollback isn't offered on free, document `git revert` and push instead.
- [ ] 4.4 README deploy runbook:
  - Blueprint creation steps;
  - the required secrets;
  - free-tier limits: sleep after 15 minutes, a cold start of about 1 minute, database expiry at 30 days plus 14, no backups;
  - the database creation date;
  - logs;
  - rollback;
  - `pg_dump` with the external URL.

  Verify: read through against the live service.
- [ ] 4.5 README five-minute demo path:
  - wake the preview first (open `/up`);
  - sign in as each role;
  - cause a two-approver conflict;
  - try a company B invoice UUID from a company A session;
  - check the admin audit history at `/admin/audit_events`;
  - as admin, demote an approver to requester on `/admin/users`, then retry the approval still open in the approver's tab, get the "no longer available" notice, and see the role change in the audit history.

  Verify: each step is followed once on the preview and once on `docker compose up`, and behaves as written.

## 5. CI

- [ ] 5.1 Extend `.github/workflows/ci.yml` with RSpec on a Postgres 18 service plus headless Chrome, and keep the generated Brakeman, bundler-audit and RuboCop jobs. Verify: the first pushed run is green, and a deliberately failing spec turns it red.

## 6. Secrets hygiene

- [ ] 6.1 Confirm `config/master.key` and `.env*` are git-ignored, and no secrets are tracked. Verify: `git ls-files | grep -E 'master.key|\.env'` returns nothing.

## 7. Submission documents (required by `docs/brief/CANDIDATE-GUIDE.md`)

- [ ] 7.1 `README.md` built from `docs/brief/SUBMISSION-README.md`. It covers every template section:
  - **demo:** the preview URL (or "use compose" if it has expired), the five-minute path from 4.5, and the run command;
  - **chosen scope:** declared time box (extended, 1-2 days), actual time spent, what was completed and what was omitted;
  - **run locally and test:** with exact commands;
  - **approach:** source of truth, the main invariant, the main tradeoff, and deployment (Render free tier plus compose) with its limitations;
  - **trust boundary:** what's trusted (the server session plus a DB-read role and company), what isn't (URL, body, hidden fields, realtime signals), the public demo password, and the OIDC production path;
  - **development tools and AI:** the model and harness, one consequential contribution or assumption, how output was verified, and one rejected suggestion or failure;
  - **known limitations:** linked to `DECISIONS.md`.

  Verify: every template heading is present and filled, and every command in the README runs as written.
- [ ] 7.2 Complete `DECISIONS.md`:
  - **assumption ledger:** for example: a single approval step, one company per user, drafts private to their author, demo password auth;
  - **key decisions:**
    - optimistic version vs. row lock;
    - idempotency vs. concurrency;
    - audit atomic with the transition;
    - 404/403/409 precedence;
    - realtime refresh without data;
    - Render free tier plus a compose fallback, with Kamal dropped;
  - **time-box section:** what was simplified and what refused simplification;
  - **deliberate omissions with next steps:**
    - outbox and notifications;
    - multi-step policies and approval limits;
    - delegation;
    - feature flags, metrics and tracing;
    - Postgres RLS;
    - keyset pagination;
    - idempotency-key expiry;
    - SSO;
    - paid-plan backups.

  Verify: no template placeholder text remains, and every brief "non-negotiable behavior" maps to a decision or a spec.
- [ ] 7.3 Brief traceability check: a table in the README maps each non-negotiable and edge case from `docs/brief/h1-approval-workbench.md` to the spec requirement and the RSpec file that proves it. Verify: every row links to an existing spec file, and the specs are green.
