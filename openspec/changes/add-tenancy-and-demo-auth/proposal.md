# Proposal

## Why

Every later feature depends on knowing who the actor is and which company they belong to. The tenant boundary has to be authoritative on the server before any invoice data is exposed.

## What Changes

- Companies and users, where each user belongs to exactly one company and has one role: `requester`, `approver` or `admin`.
- Email/password sign-in built with the Rails 8 authentication generator (`bin/rails generate authentication`):
  - `has_secure_password` (bcrypt);
  - a DB-backed `sessions` table;
  - rate-limited sign-in;
  - sign-out that destroys the server-side session.

  The password-reset flow the generator creates is removed, because the app has no mailer.
- On every request the actor is re-read from the database, so a role change or removed user takes effect on the next request.
- Unauthenticated requests to the app are redirected to sign-in.
- App generation with `rails new` (no Kamal, no Minitest), plus an RSpec and FactoryBot test harness with synthetic-only factories.
- Seed data: two companies, each with one requester, two approvers and one admin. Seeds are deterministic fixed literals, idempotent, and runnable in production. They don't use FactoryBot, which is test-only.

## Capabilities

### New Capabilities
- `tenancy`: the company boundary and how records are scoped to the actor's company.
- `authentication`: password sign-in/sign-out, server-side sessions, and re-validating the actor on each request.
- `demo-data`: a synthetic, deterministic and idempotent demo dataset that can be loaded in every environment.

### Modified Capabilities

## Impact

New tables `companies`, `users` and `sessions`. Generator output: `Authentication` concern, `SessionsController`, `Current`, sign-in view. New runtime gem `bcrypt`. Also seeds.

Out of scope:
- password reset and email confirmation (no mailer);
- self-registration;
- MFA;
- an SSO/OIDC identity provider (documented as the production path);
- users in more than one company.
