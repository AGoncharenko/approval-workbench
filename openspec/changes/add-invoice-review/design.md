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

## Risks / Trade-offs

- [Offset pagination drifts while rows change] → Acceptable at demo scale. Keyset pagination is listed as a next step.
- [Exponent table incomplete] → Unknown currencies default to 2, and the seeds only use known currencies. A full ISO table is a follow-up.
