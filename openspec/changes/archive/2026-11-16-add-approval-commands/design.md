# Design

## Context

Built on `invoices` (version column, the `(company_id, id)` unique index, visibility scope) and `authentication` (`Current.user` re-read per request). The default Postgres isolation level is READ COMMITTED.

## Goals / Non-Goals

**Goals:**
- One command that owns every status transition.
- Correctness under real concurrency, proven by a multi-threaded spec.
- An audit write that is atomic with the transition.

**Non-Goals:** a general workflow engine, an outbox for external delivery, idempotency-key expiry.

## Decisions

- **`TransitionInvoice` is a service object in `app/services/transition_invoice.rb`, called as `TransitionInvoice.call(actor:, invoice_uuid:, action:, expected_version:, idempotency_key:, reason: nil)`.** It returns a `Result` with one outcome: `applied`, `replayed`, `conflict`, `forbidden`, `not_found` or `invalid`. Controllers map outcomes to HTTP:
  - applied/replayed → 303 to the invoice;
  - conflict → 409 with the invoice view;
  - forbidden → 403;
  - not_found → 404;
  - invalid → 422.
- **A rule table** maps each action (`submit`, `approve`, `reject`) to `from`, `to` and `allowed_role`, plus an author rule:
  - `submit` requires the author;
  - `approve` and `reject` forbid the author.

  `InvoicePolicy#transition?(action)` reads this table. The view uses it to show buttons, and the command calls it again inside the transaction, so it's authoritative.
- **Order inside a single transaction:**
  1. `INSERT INTO idempotency_keys (company_id, user_id, key, fingerprint) ON CONFLICT DO NOTHING RETURNING id`. If no row comes back, a concurrent or earlier request owns the key: wait on that unique-index entry (the insert blocks until the other commits or aborts), then read the stored row. A different fingerprint gives `invalid` (422). A matching fingerprint gives `replayed`, with the stored event.
  2. Load the invoice through the actor's visibility scope with `FOR UPDATE`. Missing gives `not_found`.
  3. Run the policy check against the locked row and the actor's current role. Failure gives `forbidden`.
  4. Compare `status`/`version` with the expectation. A mismatch gives `conflict`, with the latest event.
  5. Update `status` and `version = version + 1`, then insert the `approval_events` row.
  6. Store `event_id` on the idempotency row and commit.

  Any non-applied outcome rolls back the transaction, which also removes the key row, so a later retry is evaluated fresh.
- **Why use both a version check and idempotency:**
  - the version check answers "is my decision based on what's current?";
  - idempotency answers "did this exact request already happen?".

  A retry after a lost response would fail the version check (the version moved), and the user would see a false conflict. Idempotency turns that retry into an honest "already recorded". Each covers a failure the other can't.
- **Why `FOR UPDATE` plus a version check** rather than a bare conditional `UPDATE ... WHERE version = ?`. Both are correct. The row lock lets the command read the locked state to explain a conflict or authorization failure without a second race. Lock scope is one row, held for milliseconds.
- **Fingerprint** = SHA-256 of `action|invoice_uuid|expected_version|reason`.
- **Audit table:**
  - `approval_events.company_id` plus a composite FK `(company_id, invoice_id) → invoices(company_id, id)`, so an event can't cross tenants;
  - `actor_id` FK RESTRICT, so users with history can't be hard-deleted;
  - `actor_role` is snapshotted text.

  The append-only trigger is in `add-admin-area`.
- **Form:** each render of the decision form embeds `expected_version` and a fresh `SecureRandom.uuid` key in hidden fields, so a resubmit of the same rendered form reuses the key. The buttons use Turbo's `data-turbo-submits-with` to prevent accidental double clicks. The server guarantees are what actually prevent double application.

- **Unknown outcomes on the client:** a small Stimulus controller (`decision_form_controller.js`) handles Turbo submit errors that have no HTTP response. It shows a neutral notice and keeps the form as rendered, with the same key and version. The server-side replay makes "Retry" safe. Reloading shows the authoritative state. No local storage or offline queue is used.

## Risks / Trade-offs

- [The idempotency table grows without bound] → It's small at demo scale. Next step: a Solid Queue recurring job deletes keys older than 24 hours.
- [A key can't be reused after a refused command] → This is intended: a refused command rolls back its key.
- [The concurrency spec needs real separate DB connections] → It runs with `use_transactional_tests = false` and cleans up explicitly.

## Migration Plan

All changes are additive tables. Rollback means redeploying the previous version (Render rollback), and the tables can stay because nothing older reads them.
