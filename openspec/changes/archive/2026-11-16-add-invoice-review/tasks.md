# Tasks

## 0. UI foundation (design system)

- [x] 0.1 Add `tailwindcss-rails` and run `bin/rails tailwindcss:install`. `bin/dev` now starts Rails plus the watcher through `Procfile.dev`. Update `.claude/launch.json` if the command changes. Add `bin/rails tailwindcss:build` to `bin/setup`. Verify: `bin/rails tailwindcss:build` succeeds, `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` includes the Tailwind CSS, and `bin/dev` serves a styled page on port 3000.
- [x] 0.2 Tokens in `@theme` (brand, status colors and focus ring) in `app/assets/tailwind/application.css`. Verify: each status badge's text and background pair meets WCAG AA contrast (4.5:1), with the computed ratios listed in the task notes or a spec comment.
- [x] 0.3 Shared partials in `app/views/shared/`: `_status_badge`, `_money`, `_notice`, `_button`, `_data_table`, `_form_field`, with the accessibility rules from design.md. Verify: `spec/views/shared/*_spec.rb` render each partial and assert:
  - the badge has a text label;
  - money has the currency code and no float formatting;
  - the notice has `role="status"`;
  - the button has `data-turbo-submits-with`;
  - the table has a `<caption>` and `scope="col"` headers, and an empty-state row when there are no rows;
  - the form field links its error with `aria-describedby` and sets `aria-invalid`.
- [x] 0.4 Restyle `layouts/application` (header with the signed-in user, company and sign-out, a skip link, and a main landmark) and `sessions/new` (from change 1) using the partials, removing every inline `style=`. Verify: `grep -rn "style=" app/views` is empty, and the existing sign-in request and system specs stay green.

## 1. Schema

- [x] 1.1 Migration for `invoices` with CHECKs (status set, `total_minor_units BETWEEN 0 AND 99999999999999`, currency format), `version` default 1, FK to `users` for `submitted_by`, a unique `(company_id, id)` index, and `uuid uuid NOT NULL DEFAULT uuidv7()` (unique). Verify: `spec/models/invoice_spec.rb` shows the DB rejecting bad status, negative or over-maximum total and bad currency, and that `uuid` is assigned on insert and `to_param` returns it.

## 2. Money

- [x] 2.1 `Money` value object with an exponent table and integer-only formatting. Verify: `spec/models/money_spec.rb` covers USD/JPY/BHD, zero, and large values.

## 3. Read side

- [x] 3.1 `InvoicePolicy::Scope` with role-based visibility. Verify: `spec/policies/invoice_policy_spec.rb` covers each role, draft-author-only visibility and cross-company access.
- [x] 3.2 `InvoicesController#index` with status filter, due-date order, pagination and an empty state. Verify: `spec/requests/invoices_spec.rb`.
- [x] 3.3 `InvoicesController#show`, returning 404 for cross-tenant ids (looked up by UUID), for a sequential id in the URL, and for a requester viewing another requester's invoice. Verify: request spec.

## 4. Seeds

- [x] 4.1 Add about 15 `DRAFT` invoices to `db/seeds.rb`, across 2 companies in USD/EUR/JPY. Use fixed vendor, amount and currency literals, due dates as fixed day offsets from the load date (for example `Date.current + 14`) so the demo never looks stale, `find_or_create_by!` on `(company, vendor_name)` with vendor names unique within each company's seeds, and no direct non-draft status. Verify: `spec/seeds_spec.rb` expects stable invoice counts after 2 loads.

## 5. Accessibility

- [x] 5.1 Shared layout, building on the 0.x partials: the `_notice` live region for flash and outcome notices, `aria-busy` on Turbo frames and forms during requests (via `turbo:submit-start`/`turbo:submit-end`), `data-turbo-submits-with` labels, status badges with text, a visible focus style, and a custom 404 page with a link back to the list. Verify: request specs for the 404 text, and a system spec that tabs through the list, a filter and the detail page, then checks `aria-busy` during a submit.
- [x] 5.2 The detail page labels approved invoices "Approved (not paid)" and offers no controls on terminal statuses. Verify: request spec.
