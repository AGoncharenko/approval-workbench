# Tasks

## 1. Schema

- [x] 1.1 `approval_events` migration with a composite FK `(company_id, invoice_id) → invoices(company_id, id)`, `actor_id` FK RESTRICT, a CHECK on action and statuses, and `created_at` default `now()`. Verify: `spec/models/approval_event_spec.rb` shows that an event pointing at another company's invoice is rejected by the DB.
- [x] 1.2 `idempotency_keys` migration, unique on `(company_id, user_id, key)`, with `fingerprint` and `approval_event_id`. Verify: migration runs and the model spec checks uniqueness at the DB level.

## 2. Policy

- [x] 2.1 Transition rule table and `InvoicePolicy#transition?(action)`: approver-only, author excluded, from-status match. Verify: `spec/policies/invoice_policy_spec.rb` covers every role × action × status, plus self-approval.

## 3. Command

- [x] 3.1 `TransitionInvoice` with outcomes applied/replayed/conflict/forbidden/not_found/invalid. Verify: `spec/services/transition_invoice_spec.rb` covers:
  - approve success with an event;
  - reject without a reason (invalid);
  - stale version (conflict that names the latest actor);
  - already decided (conflict);
  - draft (not_found);
  - cross-tenant (not_found);
  - another requester's invoice (not_found);
  - own invoice as requester, or as admin (forbidden);
  - an approver demoted to requester before the command (not_found, because the invoice is no longer visible);
  - author later promoted to approver (forbidden);
  - same key and payload (replayed, one event);
  - same key with a different payload (invalid);
  - missing key (invalid).
- [x] 3.2 Atomicity: force the event insert to fail. Verify: the spec asserts the invoice status and version are unchanged.
- [x] 3.3 Concurrency: two threads with separate connections and the same expected version but different keys. Verify: `spec/services/transition_invoice_concurrency_spec.rb` expects exactly one applied, one conflict and one event. The second case uses the same key in two threads and expects one applied, one replayed and one event.

## 4. HTTP and UI

- [x] 4.1 `POST /invoices/:invoice_id/transitions` (`:invoice_id` holds the invoice UUID through `to_param`) maps outcomes to 303/409/403/404/422. Verify: `spec/requests/transitions_spec.rb` covers each outcome, including a forged `company_id` param being ignored.
- [x] 4.2 Decision form with hidden `expected_version` and idempotency key, a required reason field for reject, and `data-turbo-submits-with`. Controls render only when `transition?` is true. Verify: request spec checks the hidden fields and that controls are absent for a requester.
- [x] 4.3 Outcome notices (applied, already recorded, conflict with the current status and actor) and the history list on invoice detail. Verify: request spec on the notice text.
- [x] 4.4 System spec: two sessions open the same invoice, the first approves, the second rejects and sees the conflict notice. Verify: `spec/system/approval_conflict_spec.rb` is green.
- [x] 4.5 Unknown-outcome handling: a Stimulus controller listens for `turbo:submit-end` and `turbo:fetch-request-error` without a response. It shows an "Outcome not confirmed — Retry or reload" notice in the live region and re-enables the same form, keeping the same hidden idempotency key and expected version. Verify: `spec/system/approval_network_failure_spec.rb` makes the server commit and then drop the response, using a Rack middleware toggle that exists only in the test environment. It expects the notice, a Retry that yields "already recorded", and exactly one event.
