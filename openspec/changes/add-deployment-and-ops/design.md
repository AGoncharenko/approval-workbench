# Design

## Context

Change 1 regenerates the app with `rails new … --skip-kamal`, with bundling enabled, so the Solid installers run and `Gemfile.lock` exists. The generated `Dockerfile` (Ruby 4.0.9, `bin/docker-entrypoint` running `db:prepare` for `./bin/rails server`) is the build artifact for both Render and compose.

Render free-tier facts, from Render's docs as of November 2026:

- **Web service:** 0.1 CPU and 512 MB, it sleeps after 15 minutes idle and takes about a minute to wake, with 750 instance hours per month. It has no shell, no pre-deploy command, no one-off jobs, no persistent disk, and no free background workers. `PORT=10000`.
- **Free Postgres:** one per workspace, 1 GB, 256 MB RAM and 100 connections. It has no backups. It expires 30 days after creation and is deleted after a further 14-day grace period. PostgreSQL 18 is the default.
- **Ruby:** the native runtime's default is 3.4.12, and the docs don't mention 4.0.

## Goals / Non-Goals

**Goals:**
- A clickable hosted preview that provisions itself from git.
- A one-command local run that needs no accounts.
- Honest health checks.

**Non-Goals:** paid-plan features, high availability, an observability vendor.

## Decisions

- **Render with the Docker runtime, not the native Ruby runtime.** The Dockerfile pins Ruby 4.0.9, and the native runtime doesn't document 4.0 support. One image also serves compose and CI parity.
  - Alternative 1: Kamal on a VPS. Dropped, because it needs a server, registry and SSH. Reviewers can't click it, and it doubles deploy maintenance.
  - Alternative 2: Fly.io. Not chosen; the user picked Render.
- **The `render.yaml` Blueprint:**
  ```yaml
  databases:
    - name: workbench-db
      plan: free
      postgresMajorVersion: "18"
  services:
    - type: web
      name: workbench
      runtime: docker
      plan: free
      healthCheckPath: /up
      envVars:
        - key: DATABASE_URL
          fromDatabase: { name: workbench-db, property: connectionString }
        - key: RAILS_MASTER_KEY
          sync: false
        - key: DEMO_PASSWORD
          sync: false
        - key: WEB_CONCURRENCY
          value: "0"
        - key: RAILS_MAX_THREADS
          value: "3"
        - key: SOLID_QUEUE_IN_PUMA
          value: "1"
  ```
  - The exact nesting is confirmed with Render's Blueprint validation when it's created.
  - The image's default `CMD` is `./bin/rails server`, so Puma binds `$PORT` directly. Thruster (the generated default, on port 80) is dropped because Render's edge already does TLS and compression. No `dockerCommand` is set: Render's docs don't say whether an override still runs the image's `ENTRYPOINT`, and the entrypoint is what migrates and seeds.
  - `WEB_CONCURRENCY=0` gives single-process Puma, which fits in 512 MB.
- **Start-time provisioning.** `bin/docker-entrypoint` runs `db:prepare`, then `db:seed`, before `exec`. Both are idempotent, which the seeds spec in `demo-data` requires. That replaces the pre-deploy command and shell, which free plans lack.
- **One database for everything.** `config/database.yml` production gets `primary` from `DATABASE_URL` only.
  - Solid Cache, Queue and Cable are configured for a single database: their schema files are converted to regular migrations, and `connects_to` and the separate database entries are removed.
  - Alternative: extra databases inside the Render instance. Rejected, because Render's docs don't say it's possible on free, and one database also matches compose.
- **Solid Queue inside Puma** (`plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]`), because free plans have no workers.
  - `config/queue.yml` raises polling to 1 second for the dispatcher and workers. The 0.1-second default creates needless idle DB load, and a community report says it burned bandwidth.
  - Jobs pause while the instance sleeps, which is acceptable because no correctness depends on jobs. Realtime refreshes are broadcast synchronously (see `add-realtime-refresh`).
- **SSL:** `config.assume_ssl = true` and `config.force_ssl = true`, with `ssl_options: { redirect: { exclude: ->(r) { r.path == "/up" } } }` so the health check works over plain HTTP inside Render. Both flags are read from ENV (default true), so compose can disable them on localhost.
- **Compose fallback:** `docker-compose.yml` builds the same Dockerfile in `RAILS_ENV=production` with `postgres:18`. The volume is mounted at `/var/lib/postgresql`, because the PG 18 image keeps data in a versioned `18/docker` subdirectory.
  - `SECRET_KEY_BASE` is a documented local-only value, labelled non-secret.
  - `RAILS_FORCE_SSL=false` and `RAILS_ASSUME_SSL=false`.
  - The same entrypoint migrates and seeds.
- **Health:** a custom `HealthController#show` runs `SELECT 1`, returns 200 or 503, and skips authentication. It replaces `rails/health#show`, which only proves the app booted.
- **Logs:**
  - `config.log_tags = [:request_id]`;
  - an `around_action` that adds the user and company UUIDs with `Rails.logger.tagged`;
  - `filter_parameters` extended with `:idempotency_key`.

  Logs go to STDOUT and are read in Render's Logs view.
- **Migrations:** expand/contract only, so the previous deploy runs against the current schema.
- **Rollback:** Render's "Rollback" to a previous successful deploy, which redeploys that commit's image. If it's unavailable on free, the fallback is `git revert` and push.
- **Backups:** free Postgres has none. The README documents `pg_dump "$EXTERNAL_DATABASE_URL" > backup.sql`, using the external URL from the dashboard, and notes the database's expiry date.
- **CI:** `.github/workflows/ci.yml` (generated) is extended with:
  - a `test` job with a `postgres:18` service and Chrome, running `bundle exec rspec`;
  - the generated Brakeman, bundler-audit and RuboCop jobs.

  Render auto-deploys from the default branch. CI is advisory unless the user enables branch protection.

## Risks / Trade-offs

- [The free database expires about 44 days after creation and has no backups] → All data is synthetic, and the Blueprint recreates it. Seeds rebuild the demo on start. The creation date is recorded in the README.
- [A cold start of about 1 minute could look like a broken demo] → The README says to open `/up` a minute before the demo.
- [Seeding on every boot] → It's idempotent and cheap (about 30 rows). It's covered by the seeds spec.
- [`db:prepare` at boot could race between instances] → The free plan has one instance. With more than one, move it to a pre-deploy command on a paid plan.
- [Render may restart free instances at any time] → The app is stateless, and all state is in Postgres.
- [Compose uses a known local `SECRET_KEY_BASE`] → It's local-only, labelled, and never used on Render.

## Migration Plan

First deploy: push to GitHub, then go to Render → New → Blueprint, pick the repo, and enter `RAILS_MASTER_KEY` and `DEMO_PASSWORD`. The entrypoint migrates and seeds.

Later deploys: push to the default branch, and Render auto-deploys behind the health check.

Rollback: use the Render dashboard's rollback to the previous deploy.
