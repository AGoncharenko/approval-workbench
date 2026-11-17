# Proposal

## Why

The brief requires a deployed or reproducibly deployable build, and the interview covers deployment, roll forward/back and operations. Reviewers should be able to click a hosted preview, and also run the app themselves without our accounts or secrets.

## What Changes

- **A hosted preview on Render's free tier,** described by a versioned `render.yaml` Blueprint:
  - one Docker-runtime web service built from the repo's `Dockerfile`;
  - one free Render Postgres 18 database;
  - the `/up` health check gates each deploy;
  - TLS is terminated by Render.
- **Migrations and idempotent demo seeding run at container start,** because the free tier has no shell, pre-deploy command or one-off jobs.
- **Solid Cache, Solid Queue and Solid Cable share the single primary database,** because the free tier gives one database. Solid Queue runs inside Puma, because the free tier has no background workers.
- **No secrets in git.** `RAILS_MASTER_KEY` and `DEMO_PASSWORD` are entered on Render (`sync: false`), and `DATABASE_URL` comes from the database's connection string.
- **A Docker Compose fallback** (app + Postgres 18) for reviewers. It needs no account and no secrets beyond a labelled local-only key.
- **A health endpoint** that reports unhealthy when the database is unreachable.
- **Logs:**
  - tagged with request id, user id and company id;
  - passwords, tokens and idempotency keys filtered.
- **GitHub Actions CI on every push and PR:**
  - RSpec, including system specs, against Postgres 18;
  - RuboCop;
  - Brakeman;
  - bundler-audit.
- **Documented platform limits and procedures:** idle sleep, cold start, database expiry (30 days plus a 14-day grace), no backups, the migration policy, rollback and a `pg_dump` command.
- **Kamal is not used.** The `kamal` gem isn't installed, and there is no `config/deploy.yml`.
- **Submission documents required by the candidate guide:** `README.md` from the template (including the trust boundary, AI tools and a traceability table), and a completed `DECISIONS.md`.

## Capabilities

### New Capabilities
- `operations`: observable deploy, health, logging, CI and secret-handling guarantees.

### Modified Capabilities

## Impact

`render.yaml`, `docker-compose.yml`, the `Dockerfile` and `bin/docker-entrypoint`, `config/database.yml` (single database), the Solid configs, `config/environments/production.rb` (SSL and logging), `config/routes.rb` (health route), `.github/workflows/ci.yml`, README and DECISIONS.

Most of this can land early: the Render, compose and CI scaffolding can be set up right after change 1's app generation, so every later change is deployable.

Out of scope:
- paid Render plans: backups, pre-deploy command, workers, persistent disks;
- multi-instance or high-availability setups;
- metrics and tracing backends;
- automated backups beyond a documented `pg_dump`.
