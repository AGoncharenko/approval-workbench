# Proposal

## Why

Approving or rejecting a pending invoice is the workbench's core action. It must stay correct when two approvers act at nearly the same time, when a browser retries after a timeout, and when a role changes while a page is open. Every outcome must be honest, and every applied transition must be audited.

## What Changes

- Approvers can approve or reject a `PENDING` invoice in their company. A rejection requires a reason.
- Segregation of duties: an approver cannot decide on an invoice they authored. Admins and requesters cannot approve or reject.
- Every command carries the `expected_version` the user saw. A mismatch never applies, and returns a conflict that shows the current status and who changed it.
- Every command carries an idempotency key:
  - a retry with the same key and payload replays the original result;
  - the same key with a different payload is rejected.
- Each applied transition writes an `approval_events` row in the same DB transaction (actor, actor role, action, from/to status, reason, time).
- Honest outcome pages for applied, replayed, conflict, forbidden and not-found results.
- An honest "outcome not confirmed" state when the browser gets no response. Retrying safely reuses the same idempotency key.
- One command implementation, shared with `submit` (from `add-invoice-submission`).

## Capabilities

### New Capabilities
- `approvals`: approval and rejection rules, optimistic concurrency, idempotent retries and atomic recording of each transition.

### Modified Capabilities

## Impact

New `approval_events` and `idempotency_keys` tables, the `TransitionInvoice` command, an `InvoicePolicy` decision method, a transitions controller and route, and the history section on invoice detail. Depends on `add-invoice-review`.

Out of scope:
- multi-step or amount-based approval policies;
- delegation;
- un-rejecting or re-opening;
- payment;
- notifications;
- idempotency-key expiry jobs (noted as a next step).
