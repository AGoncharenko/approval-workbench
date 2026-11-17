# Tasks

## 1. Amount parsing

- [ ] 1.1 `Money.parse(input, currency)`, integer-only, rejecting excess decimals, negatives, over-maximum values and non-numerics. Verify: `spec/models/money_spec.rb` covers `1,000,000,000,000.00 USD` rejected, `1,234.56 USD → 123456`, `10.005 USD` rejected, `1.5 JPY` rejected, `0.001 BHD → 1`.

## 2. Drafts

- [ ] 2.1 `InvoicePolicy#create?/update?/destroy?`: requester only, own drafts only. Verify: policy spec for each role.
- [ ] 2.2 `InvoicesController#new/create`, with company taken from `Current.company` and `company_id` params ignored. Verify: request spec, including the forged-company case.
- [ ] 2.3 `edit/update` with `expected_version` and a conditional update. `destroy` only for own drafts. Verify: request specs for a stale edit (409, current values shown), editing a submitted invoice (refused) and discarding another user's draft (404).

## 3. Submit

- [ ] 3.1 Add the `submit` action (`DRAFT → PENDING`, author-only) to the `TransitionInvoice` rules. Verify: `spec/services/transition_invoice_spec.rb` covers success with an event, a non-author (404), and a duplicate key replay.
- [ ] 3.2 Submit button on the draft detail page, carrying `expected_version` and an idempotency key. Verify: request spec.

## 4. Seeds

- [ ] 4.1 Seeds move a fixed subset of drafts to PENDING, APPROVED and REJECTED through `TransitionInvoice`, using deterministic `seed:` keys. Verify: `spec/seeds_spec.rb` checks that an approved invoice has `submit` then `approve` events by different users, that its version is 3, and that a second seed run adds no events.

## 5. End to end

- [ ] 5.1 System spec: the requester creates and submits, then an approver sees it as PENDING. Verify: `spec/system/submission_spec.rb` is green.
