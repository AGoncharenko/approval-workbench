# Assumptions and decisions

## Assumption ledger

| Assumption | Why it was necessary | Risk if wrong | How to validate in a real product |
| --- | --- | --- | --- |
| Drafts are private to their author. Admins and approvers see only submitted invoices, plus the full audit trail. | The brief says users see invoices "available to their company and role" and that admins "inspect the audit history", but it never defines who sees drafts. Drafts are unsubmitted work in progress with no audit events, and nobody but the author can act on them. | Admins can't spot forgotten drafts nearing their due date, which is an oversight gap for AP. | Ask AP admins whether unsubmitted drafts matter to their oversight. If they do, add a read-only admin "Drafts" view rather than widening the general visibility rule. |
| An invoice total is between 0 and 99,999,999,999,999 minor units (USD 999,999,999,999.99; the cap is in minor units, so it is ¥99.9 trillion for JPY and BHD 99.9 billion). Negative totals (credit notes) are out of scope. | The brief asks for exact money but sets no range. Without a cap, a typo or a forged value could store an absurd amount, and integers past 2^53 lose precision in any JavaScript or JSON consumer. This cap is far above any real AP invoice, fits easily in `bigint`, and stays below 2^53. One limit is enforced in three places: `Money::MAX_MINOR_UNITS`, the form parser and a DB CHECK. | A legitimate invoice is refused (very unlikely at this size), or credit notes, which are common in AP, cannot be entered. | Check the largest real invoice and the credit-note volume with AP. If credit notes are needed, model them as their own document type rather than allowing negative totals. A per-currency cap would only matter if a single cap proved too loose or too tight in practice. |

## Key decisions

Capture only the few choices that materially shaped the submission. Short bullets are enough.

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
- Evidence or verification: `spec/db/audit_append_only_spec.rb` shows `update_all`, `delete_all` and raw SQL refused on both tables with rows unchanged. Rolling back and re-running the migrations regenerates a byte-identical `structure.sql`.

## Time-box decisions

- What I intentionally simplified:
- What I refused to simplify because it protects a core invariant:
- What I would build next with more time:
- What I would reconsider before production:
