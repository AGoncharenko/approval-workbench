# Tasks

## 1. Schema

- [ ] 1.1 Migration for `invoices` with CHECKs (status set, `total_minor_units BETWEEN 0 AND 99999999999999`, currency format), `version` default 1, FK to `users` for `submitted_by`, a unique `(company_id, id)` index, and `uuid uuid NOT NULL DEFAULT uuidv7()` (unique). Verify: `spec/models/invoice_spec.rb` shows the DB rejecting bad status, negative or over-maximum total and bad currency, and that `uuid` is assigned on insert and `to_param` returns it.

## 2. Money

- [ ] 2.1 `Money` value object with an exponent table and integer-only formatting. Verify: `spec/models/money_spec.rb` covers USD/JPY/BHD, zero, and large values.

## 3. Read side

- [ ] 3.1 `InvoicePolicy::Scope` with role-based visibility. Verify: `spec/policies/invoice_policy_spec.rb` covers each role, draft-author-only visibility and cross-company access.
- [ ] 3.2 `InvoicesController#index` with status filter, due-date order, pagination and an empty state. Verify: `spec/requests/invoices_spec.rb`.
- [ ] 3.3 `InvoicesController#show`, returning 404 for cross-tenant ids (looked up by UUID), for a sequential id in the URL, and for a requester viewing another requester's invoice. Verify: request spec.

## 4. Seeds

- [ ] 4.1 Add about 15 `DRAFT` invoices to `db/seeds.rb`, across 2 companies in USD/EUR/JPY. Use fixed vendor, amount and currency literals, due dates as fixed day offsets from the load date (for example `Date.current + 14`) so the demo never looks stale, `find_or_create_by!` on `(company, vendor_name)` with vendor names unique within each company's seeds, and no direct non-draft status. Verify: `spec/seeds_spec.rb` expects stable invoice counts after 2 loads.

## 5. Accessibility

- [ ] 5.1 Shared layout: a `role="status"` live region for flash and outcome notices, `aria-busy` on Turbo frames and forms during requests (via `turbo:submit-start`/`turbo:submit-end`), `data-turbo-submits-with` labels, status badges with text, a visible focus style, and a custom 404 page with a link back to the list. Verify: request specs for the 404 text, and a system spec that tabs through the list, a filter and the detail page, then checks `aria-busy` during a submit.
- [ ] 5.2 The detail page labels approved invoices "Approved (not paid)" and offers no controls on terminal statuses. Verify: request spec.
