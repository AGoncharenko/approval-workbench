# Design

## Context

This builds on `tenancy` (the `Current.company` scope) and `authentication` (`Current.user` re-read per request).

## Goals / Non-Goals

**Goals:** correct money at the storage layer, and one place that decides which invoices a role can see.

**Non-Goals:** rich grid features such as column sorting, saved views and export.

## Decisions

- **`total_minor_units bigint` plus `currency char(3)`, with DB CHECKs** (`>= 0`, `~ '^[A-Z]{3}$'`). Alternative: `decimal(15,2)`. Rejected because the exponent varies by currency (JPY 0, BHD 3), and a fixed scale either hides errors or rounds them away.
- **Money formatting:** a small `Money` value object with an exponent table (default exponent 2, JPY 0, BHD/KWD 3) and pure integer arithmetic (`divmod 10**exp`). Alternative: the `money` gem. Rejected: a big dependency for formatting alone. Revisit if FX conversion appears.
- **Visibility in one query object:** `InvoicePolicy::Scope.new(Current.user).resolve` returns `company.invoices`, narrowed to the actor's own invoices for requesters and to non-drafts for approvers and admins. `index` and `show` both use it, so detail and list can't drift apart.
- **Composite unique index `(company_id, id)`** so child tables can use a composite FK that enforces same-tenant references.
- **Routes use the invoice UUID** (`Invoice#to_param` returns `uuid`). Lookups always go through the visibility scope with `find_by!(uuid:)`. See the tenancy design for why UUIDs are public columns, not primary keys.
- **Pagination:** a hand-rolled `limit/offset` with 25 rows per page. Alternative: the pagy gem. Rejected for now: tiny data, and it's easy to swap later.
- **Status as a Postgres CHECK constraint plus a string-backed Rails enum.** Raw values stay readable in the audit log and SQL.

- **Design system: Tailwind CSS (`tailwindcss-rails`) plus owned ERB partials.**
  - **Why Tailwind:** the gem ships a standalone Tailwind binary. `bin/rails tailwindcss:install` wires it into Propshaft and hooks `assets:precompile`, so the Dockerfile and Render need no Node and no changes. Styles are explicit in the markup, which is easy to review and explain.
  - **The partials** in `app/views/shared/` are the design system. Each one holds an accessibility rule from the specs, so pages can't forget it:
    - `_status_badge`: text label plus color, never color alone;
    - `_money`: `tabular-nums`, right-aligned, always with the currency code, and taking an `Invoice` or `Money`, never a Float;
    - `_notice`: the single `role="status"` live region, with variants for success, info, conflict and error, used for flash and command outcomes;
    - `_button`: primary, secondary and danger styles, `data-turbo-submits-with`, visible `focus-visible` rings, and a disabled state;
    - `_data_table`: a `<caption>`, `scope="col"` headers, a responsive horizontal scroll, and an empty-state row;
    - `_form_field`: label, input and inline error linked with `aria-describedby`, with `aria-invalid` on error.
  - **Tokens** live in Tailwind's `@theme`, in `app/assets/tailwind/application.css`: a brand color, status colors that meet WCAG AA contrast against their text, and a focus-ring color. Pages use only the partials and these tokens, with no inline `style=` attributes.
  - **Alternatives considered:**
    - Pico CSS: the fastest option, but its generic look is hard to adapt to a dense approvals table.
    - daisyUI or Flowbite: they need an npm build or plugin workarounds.
    - Bootstrap: heavy, and needs Node or a CDN.
    - GOV.UK Frontend or USWDS: excellent accessibility, but they need a Sass/npm build and are too much for the time box.
- **`bin/dev` becomes two processes,** Rails plus `tailwindcss:watch`, through foreman and `Procfile.dev`. RSpec and CI must build the CSS first (`bin/rails tailwindcss:build`) so system specs render styled pages without a missing-asset error.

## Risks / Trade-offs

- [Long utility class lists in templates] → They're contained in the shared partials, and page templates mostly compose partials.
- [The Tailwind build is missing in tests or CI, giving an unstyled page or an asset error] → `tailwindcss:build` runs in `bin/setup`, before RSpec in CI, and in `assets:precompile` for Docker.
- [Offset pagination drifts while rows change] → Acceptable at demo scale. Keyset pagination is listed as a next step.
- [Exponent table incomplete] → Unknown currencies default to 2, and the seeds only use known currencies. A full ISO table is a follow-up.
