# Tasks

## 0. App generation and test harness

- [x] 0.0 Generate the app into the repo root, keeping `docs/`, `openspec/`, `DECISIONS.md`, `.claude/`, `.idea/` and `.ruby-version`: `rails new . --name=workbench --database=postgresql --skip-test --skip-kamal --skip-jbuilder --skip-action-mailbox --skip-action-mailer --skip-action-text --skip-active-storage`, with bundling on so the Solid installers run. Then `bundle lock --add-platform x86_64-linux`. `rails new` doesn't generate `DECISIONS.md`, so it stays as is. Set development and test in `database.yml` to `host: localhost` and `port: <%= ENV.fetch("PGPORT", 5433) %>`, because local PG 18 runs on 5433 in Postgres.app. Verify: `Gemfile.lock` exists and lists the `x86_64-linux` platform, `bin/rails db:prepare` creates the dev and test databases on PG 18 (`select version()` reports 18), `Gemfile` has no `kamal`, `bin/rails about` runs, and `git check-ignore config/master.key` confirms the key is ignored.
- [x] 0.1 Add `rspec-rails` and `factory_bot_rails` (development and test), plus `capybara` and `selenium-webdriver` (test). Run `bin/rails g rspec:install`, include `FactoryBot::Syntax::Methods`, and configure system specs to use headless Chrome. Concurrency specs opt out of transactional tests and truncate afterwards. Verify: `bundle exec rspec` runs green with 0 examples, and a sample system spec boots Chrome.
- [x] 0.2 Factories in `spec/factories` use only fixed fictional strings and `@example.com` addresses, with sequences for uniqueness. There's no Faker and no real-looking data. Verify: `spec/factories_spec.rb` lints every factory with `FactoryBot.lint` and asserts every email ends in `example.com`.

## 1. Authentication generator

- [x] 1.1 Run `bin/rails generate authentication`, then remove the password-reset controller, mailer, views and routes. Verify: `bin/rails routes` lists no `passwords` routes and the app boots.
- [x] 1.2 Migrations: `companies` (with `uuid uuid NOT NULL DEFAULT uuidv7()`, unique), and add `uuid` (same definition), `name` (not null, 1 to 100 characters), `company_id` (FK, not null) and `role` (CHECK requester/approver/admin) to `users`. Give `sessions.user_id` an FK `on_delete: :cascade`. Verify: `bin/rails db:migrate` succeeds and `spec/models/user_spec.rb` expects the DB to reject an unknown role.
- [x] 1.0 Confirm local Postgres is 18 (`uuidv7()` exists). Done: Postgres.app 18.7 on port 5433, and `select uuidv7()` returns a UUID. CI is checked in `add-deployment-and-ops` 5.1.
- [x] 1.3 `Company` and `User` associations plus the role enum. `Company#to_param` and `User#to_param` return `uuid`. Expose `Current.user` and `Current.company` from `Current.session`. Verify: model spec.

## 2. Sign-in behavior

- [x] 2.1 Request specs for valid sign-in, invalid email or password (same generic message), sign-out destroying the `Session` row, a cookie replayed after sign-out, and an anonymous redirect. Verify: `spec/requests/sessions_spec.rb` is green.
- [x] 2.2 Rate limit: the 11th attempt within 3 minutes is refused. Verify: request spec with a memory cache store.
- [x] 2.3 Deleting a user removes their sessions, and their next request redirects. Verify: request spec.
- [x] 2.4 Label the sign-in page as demo and list the demo accounts outside production. Verify: request spec checks the label.

## 2b. Tenancy proof boundary

- [x] 2.6 Prove the company comes from the session: a request spec posts a forged `company_id` to a sign-in-protected endpoint that exists in this change (for example sign-out, or a temporary spec-only route), and asserts that `Current.company` is the user's own company. The cross-company 404 scenarios in the `tenancy` spec need company-scoped records, so they're proven in `add-invoice-review` task 3.3. Keep this change unarchived until that task is green. Verify: `spec/requests/tenancy_spec.rb` is green.

## 3. Seeds

- [x] 3.1 `db/seeds.rb`: 2 companies, each with a requester, 2 approvers and an admin. Use fixed literals, `@example.com` addresses, `find_or_create_by!` on name/email, and a password from `DEMO_PASSWORD` (with a documented default). No FactoryBot, no randomness. Verify: `spec/seeds_spec.rb` loads twice, expects the same counts and documented roles, and checks a seeded user can authenticate.
- [x] 3.2 Prove seeds don't need dev/test gems. Verify: `RAILS_ENV=production bundle exec rails db:seed` against a scratch DB, run with `BUNDLE_WITHOUT=development:test`.
