# Design

## Context

Built on `invoices` (table, `Money`, visibility scope) and `approvals` (the `TransitionInvoice` command, idempotency keys, audit events). Implement it after both.

## Goals / Non-Goals

**Goals:** exact amount entry, and one transition path for every status change, including seeds.

**Non-Goals:** recalling a submitted invoice, line items, attachments, drafts shared between requesters.

## Decisions

- **Amount parsing is a string-to-integer function on `Money`.**
  - Strip thousands separators.
  - Match `\A\d+(\.\d{0,exp})?\z`.
  - Split on `.` and right-pad the fraction to `exp` digits, then compute `Integer(whole) * 10**exp + Integer(frac)`.
  - Never use `to_f`, `BigDecimal` rounding or `round`.

  Alternative: `BigDecimal(input) * 10**exp` with a scale check. Rejected: correct, but adds a rounding-mode question for no gain.
- **Supported currencies are a closed list** (`USD EUR GBP JPY BHD`) shared with the `Money` exponent table. A form select prevents free-text codes, and the DB CHECK is the backstop.
- **Draft edits lock, then check, the way transitions do:** in one transaction, `SELECT ... FOR UPDATE WHERE id AND company_id AND submitted_by = actor AND status = 'DRAFT' AND version = expected`, then `update!` with the version bumped. No row means a reload, then a 409 conflict, a 403 or a 404. Using `update!` rather than a bare `UPDATE` keeps model callbacks, so the realtime `after_commit` broadcast fires for drafts too. Discard locks the same way and uses `destroy!`. Draft edits aren't audited, because they're pre-workflow work in progress. Discarding a draft is a hard delete, allowed because drafts have no audit events.
- **Submit goes through `TransitionInvoice` with action `submit`** (allowed: `DRAFT → PENDING`, actor must be the author with role requester). This keeps one implementation of version checks, idempotency and the audit insert.
- **Seeding non-draft invoices:** seeds call `TransitionInvoice` as the seeded actors, with idempotency keys like `seed:<invoice-natural-key>:<action>`. Re-running replays from the stored keys. To survive DB resets, the key is derived from natural keys, never from ids. Seeds read `invoice.version` live instead of hard-coding it.

## Risks / Trade-offs

- [The requester can't see an invoice they submitted and later lost access to] → This matches the visibility rules. It's documented.
- [Retrying a draft edit after a lost response reports a false conflict, because the version already moved and edits carry no idempotency key] → Accepted. The conflict view shows the current values, which match what the user saved, so nothing is lost or applied twice. Adding keys to edits isn't worth it before submission.
- [A hard-deleted draft leaves no trace] → It never entered the workflow, so this is acceptable. Next step: soft-delete if the business needs a trail of drafts.
