# Proposal

## Why

Administrators must be able to answer who did what, and when, across their company's invoices and access rights, and they must be able to change who may approve. Both need to be trustworthy: the audit trail can't be edited, even by the application, and role changes are themselves audited.

## What Changes

- An admin-only area under `/admin`. The admin check is shared by every admin page and re-read on every request.
- **`/admin/users`:** lists the users in the admin's company with their roles.
  - Each row has an inline form to change that user's role. There is no per-user show or edit page.
  - Guards: an admin can't change their own role, and a company must always keep at least one admin.
  - A role change takes effect on the user's next request, without signing them out.
  - Each role change writes an append-only `role_change_events` row in the same transaction.
- **`/admin/audit_events`:** company-wide audit history, newest first and paginated.
  - Covers invoice workflow events and role-change events.
  - Filters: event type or action, actor, invoice, and date range.
- Audit events of both kinds are append-only. The database refuses UPDATE and DELETE on them.
- Every invoice's detail page shows that invoice's history to anyone allowed to see the invoice.
- This replaces the earlier rake-task plan for revoking roles. The README demo path revokes a role through `/admin/users`.

## Capabilities

### New Capabilities
- `audit`: immutability of audit events and who can read the audit history.
- `user-roles`: how company admins view and change user roles, with lockout guards and audited changes.

### Modified Capabilities

## Impact

- New `role_change_events` table, plus append-only triggers on it and on `approval_events`.
- `Admin::BaseController`, `Admin::UsersController#index/update`, `Admin::AuditEventsController#index`.
- A `ChangeUserRole` service, an `AuditFilter` query object and the shared invoice-history partial.
- Depends on `add-approval-commands`.

Out of scope:
- inviting, creating, deactivating or deleting users;
- moving users between companies;
- admin pages showing per-user sessions;
- CSV export, retention policies and tamper-evidence hashing;
- auditing reads and sign-ins (logged, not audited; see `operations`).
