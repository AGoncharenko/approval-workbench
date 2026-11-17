# Proposal

## Why

Approvers need to see their company's invoices with exact amounts and their current status before they can act. This is the read side of the workbench.

## What Changes

- An `invoices` table holding:
  - vendor;
  - total in integer minor units;
  - ISO-4217 currency;
  - due date;
  - status;
  - version;
  - who submitted it.
- An invoice list scoped to the actor's company, filterable by status, sorted by due date and paginated.
- An invoice detail page showing amount, currency, vendor, due date, status, version and approval history (the history list is fed by the `approvals` change).
- Money is formatted using the currency's minor-unit exponent. Floats are never used.
- What each role sees:
  - requesters see only invoices they authored, including their own drafts;
  - drafts are visible only to their author;
  - approvers and admins see every non-draft invoice in their company.
- **A UI foundation every later change reuses:** Tailwind CSS through the `tailwindcss-rails` gem, which needs no Node, plus a small set of ERB partials forming the app's design system:
  - status badge;
  - money;
  - notice and live region;
  - button;
  - data table;
  - form field.

  The application layout and the sign-in page from `add-tenancy-and-demo-auth` move onto it.
- Accessible loading, empty, not-found, conflict and failure states (text, not color alone; keyboard operable).
- `APPROVED` and `REJECTED` are terminal. Approval records a decision and is not payment.
- Seeds: about 15 synthetic `DRAFT` invoices across the 2 companies and several currencies (USD, EUR, JPY), with fixed literals and keyed for idempotency. Non-draft statuses get seeded later, through real commands (see `add-invoice-submission`), so no invoice has a status without matching audit history.

## Capabilities

### New Capabilities
- `invoices`: invoice data integrity, money representation, and role-filtered list/detail queries.

### Modified Capabilities

## Impact

New `invoices` table and model, `InvoicesController#index/show`, a money formatting helper and seed data. Also:
- the `tailwindcss-rails` gem;
- `app/assets/tailwind/application.css`;
- `Procfile.dev`, with `bin/dev` running Rails plus the Tailwind watcher through foreman;
- shared partials in `app/views/shared/`;
- a restyled `layouts/application` and `sessions/new`.

Out of scope: editing invoice fields after submission, attachments, line items, currency conversion and payment.
