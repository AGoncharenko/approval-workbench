# Design

## Context

This is a greenfield Rails 8.1 app on Ruby 4.0. Action Mailer was skipped at generation, and there is no identity provider (see proposal.md).

## Goals / Non-Goals

**Goals:**
- Real credential checks and revocable server-side sessions.
- A tenant boundary that can't be bypassed by accident.
- Clear documentation of which inputs are trusted.

**Non-Goals:**
- Account lifecycle: sign-up, password reset, email confirmation, MFA.
- Production SSO.

## Decisions

- **Authentication comes from `bin/rails generate authentication`, the Rails 8 built-in, kept as owned code.**
  - **What it generates:** a `User` with `has_secure_password` and `email_address`, a `Session` model (with `user_id`, `ip_address`, `user_agent`), an `Authentication` concern, `SessionsController` with `rate_limit to: 10, within: 3.minutes`, and `Current.session`.
  - **Alternative 1: Devise.** Rejected:
    - it's a large surface (mailers, registration, Warden) that the brief doesn't need;
    - it isn't owned code, so it's harder to explain;
    - its Ruby 4.0/Rails 8.1 support is unverified.
  - **Alternative 2: a password-less user picker.** Rejected at the user's request, since it doesn't exercise real credential checks.
- **Generator output trimmed:** remove `PasswordsController`, `PasswordsMailer` and their routes and views (no mailer), and add `company_id` and `role` to `users`.
- **The cookie holds only a signed, HTTP-only `session_id`.** Each request runs `Session.find_by(id:)`, then `Current.user = session.user`, with company and role read fresh from the DB. Role and company never live in the cookie.
  - Deleting a user cascades to their sessions (`dependent: :destroy` plus an FK `on_delete: :cascade`).
  - Alternative: a cookie-only session or a JWT holding claims. Rejected because it trusts stale role claims and can't be revoked.
- **Public UUIDs alongside bigint primary keys.** `companies`, `users` and `invoices` get `uuid uuid NOT NULL DEFAULT uuidv7()` with a unique index. `uuidv7()` is native in PostgreSQL 18. Models override `to_param` to return `uuid`, so every Rails URL helper emits it, and lookups use `find_by!(uuid: params[:id])`. Internal FKs and composite FKs stay on `bigint id`.
  - Alternative: UUID primary keys everywhere. Rejected: the benefit (opaque URLs) only needs a public column, and bigint FKs keep joins, composite FKs and indexes small.
  - Why v7, not v4: it's time-ordered, so the unique index stays append-mostly. It still has 74 random bits, so it can't be guessed.
  - Trade-off: v7 reveals the creation time to the millisecond, which is acceptable because creation dates aren't secret.
  - Defence in depth only: tenant isolation still comes from scoping, and UUIDs just stop enumeration and hide volume.
- **All tenant queries start from `Current.company`** (for example `Current.company.invoices.find_by!(uuid: params[:id])`). A missing record raises `ActiveRecord::RecordNotFound`, which renders as 404.
  - Alternative: a default scope or Postgres row-level security (RLS). Rejected: a default scope is easy to bypass and hides intent, and RLS adds operational complexity for a take-home. RLS is noted as a next step.
- **Roles are a Postgres CHECK constraint plus a string-backed Rails enum**, so the value stays readable in SQL and the audit log.
- **Seeds are plain `db/seeds.rb` with fixed literals and `find_or_create_by!` on natural keys** (company name, user email address).
  - Every demo user gets the same documented demo password, read from `ENV.fetch("DEMO_PASSWORD", "demo-password-2026")`. The README lists all accounts.
  - Alternative: FactoryBot in seeds. Rejected for four reasons:
    - it's dev/test-only, so it's absent from the production image, where the entrypoint runs `db:seed` on every boot (Render's free tier has no shell);
    - factories favour sequences and throwaway values, which break documented demo steps;
    - factories always insert, so re-running duplicates rows;
    - factories set state directly instead of going through commands (see `add-invoice-submission`).

    FactoryBot stays for spec setup only.
- **Role changes are made by company admins on `/admin/users`** (see `add-admin-area`). No rake task or console step is needed. Sessions aren't touched on a role change, because roles are re-read every request.
- **Production path:** add an OIDC callback (for example `omniauth_openid_connect`) that maps an IdP subject to `users` and creates the same `Session` record. Everything downstream depends only on `Current.user`, so nothing else changes.

## Risks / Trade-offs

- [A demo password is documented and public on the deployed preview] → All data is synthetic. Override it with `DEMO_PASSWORD` on a deploy. The sign-in page is labelled demo. Real deployments would use SSO.
- [A developer forgets to scope a query] → A request spec checks cross-tenant 404s for every invoice route.
- [`rate_limit` uses `Rails.cache` (Solid Cache), which a multi-node deploy shares through the DB] → That's acceptable. It's noted in the operations docs.
