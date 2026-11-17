# Design

## Context

`approval_events` is created by `add-approval-commands`, with `actor_role` snapshotted and `actor_id` FK RESTRICT. Its events are written only by `TransitionInvoice`. Users have a public `uuid` (from `add-tenancy-and-demo-auth`), and their role is re-read on every request.

## Goals / Non-Goals

**Goals:**
- Immutability enforced below the application.
- A tenant-scoped, admin-only area.
- Role changes that can't lock a company out and are always audited.

**Non-Goals:**
- User lifecycle: invite, deactivate, delete.
- Cryptographic tamper evidence.
- Protection against a DB superuser.

## Decisions

- **Routes:**
  ```ruby
  namespace :admin do
    resources :users, only: %i[index update]
    resources :audit_events, only: :index
  end
  ```
  - There's no show page and no edit page, because the role is the only editable field. Each user row holds its own small form that sends `PATCH /admin/users/:id`, where `:id` is the user's UUID through `to_param`.
  - A GET to `/admin/users/:id` isn't routed, so it returns 404.
- **`Admin::BaseController`** has a `before_action` that requires `Current.user.admin?`, re-read per request. A failure gives 403. The pages' existence isn't secret, so 404 isn't needed. Every admin controller inherits from it, so a new admin page can't forget the check.
- **`ChangeUserRole` service** (`app/services/change_user_role.rb`) returns `applied`, `unchanged`, `forbidden`, `not_found` or `invalid`. It runs in one transaction:
  1. `Current.company.lock!` (`SELECT … FOR UPDATE` on the company row). This serialises every role change within a company, so two admins demoting each other can't both pass the "one admin remains" check. Lock scope is one row, held for milliseconds.
  2. `Current.company.users.find_by!(uuid:)`. Missing gives `not_found` (404).
  3. If the target is the actor, return `forbidden` (403). If the role is outside the enum, return `invalid` (422). If the role is the same as now, return `unchanged`, with no write.
  4. If this would demote the last admin (`company.users.admin.where.not(id: target).none?`), return `invalid` (422).
  5. `target.update!(role:)`, then insert the `role_change_events` row and commit.
  - Only `params.require(:user).permit(:role)` is read.
  - Concurrent changes to the same user are last-write-wins, which is safe because setting a role gives the same result however many times it's sent, and every change is audited. No version check is needed.
- **`role_change_events` table:** `company_id`, `actor_id` and `target_user_id` (FK RESTRICT), `from_role`, `to_role` (CHECKed), `created_at`. Composite FKs `(company_id, actor_id)` and `(company_id, target_user_id)` reference `users(company_id, id)`, which needs a unique index on `users (company_id, id)`. A role event therefore can't cross tenants. It gets the same append-only trigger as `approval_events`.
- **Append-only via a Postgres trigger.** One trigger function, `forbid_audit_mutation()`, is attached `BEFORE UPDATE OR DELETE … FOR EACH ROW` to both tables. It's written with `execute` in a reversible migration.
  - Alternative 1: model-level `readonly?` plus `before_destroy` raising. Rejected as the only guard, because it's bypassed by `update_all`, `delete_all` and raw SQL. It's kept anyway as a fast, friendly error.
  - Alternative 2: `REVOKE UPDATE, DELETE` from the app role. Stronger, but on Render's free Postgres the app connects as the database owner, so it owns the table. Noted for production with separate migration and runtime roles.
  - Truncate isn't blocked: test cleanup uses it, and it requires owner privileges.
- **No audit gem.** These were considered and rejected:
  - **paper_trail and audited:** they rely on ActiveRecord callbacks, so any `update_all`, `delete_all` or raw SQL write goes unrecorded. They record column diffs, not business events with role-at-the-time and a reason. Their polymorphic `versions` table has no real FK, no tenant column and no immutability.
  - **logidze:** it uses triggers, but keeps history as editable JSON inside the audited row.

  Explicit inserts in the same transaction, plus composite FKs and a trigger, give every guarantee the brief asks for, in code that's owned and testable.
- **Unified history through a read-only SQL view.** `audit_entries` is a `UNION ALL` of both tables, projected to common columns: `kind`, `company_id`, `actor_id`, `actor_role`, `invoice_id`, `target_user_id`, `action`, `from_value`, `to_value`, `reason`, `created_at`, `source_id`. The `AuditEntry` model is `readonly`.
  - `Current.company.audit_entries` plus `AuditFilter`, which takes event type or action, actor UUID, invoice UUID and a date range. Every identifier is matched only inside that scope, so a forged one gives an empty result.
  - Ordered by `created_at DESC, source_id DESC`, 50 rows per page. Each base table has an index on `(company_id, created_at DESC)`.
  - Alternative: one polymorphic `audit_events` table. Rejected: it loses the composite FK to invoices and makes nullable columns ambiguous.
- **Display:** stored in UTC as `timestamptz`, and shown as ISO-8601 UTC with a localized `<time datetime>` element. Role selects have visually hidden labels ("Role for <name>"). A refused change re-renders the index with 422 and the error on that row.
- **Per-invoice history** is a shared partial driven by `invoice.approval_events.order(:created_at, :id)`. The invoice is already loaded through the visibility scope, so the history inherits that scope.

## Risks / Trade-offs

- [A superuser or the table owner can drop the triggers] → Out of scope. Production would use a separate runtime role, plus log shipping for tamper evidence.
- [A company-row lock serialises role changes] → Role changes are rare, and the lock is held for milliseconds.
- [Offset pagination over a growing view] → Acceptable at demo scale. Keyset pagination on `(created_at, source_id)` is a next step.
- [The view must be updated when either table changes shape] → It lives in a migration next to the tables, and a spec checks that both kinds appear.

## Migration Plan

Additive throughout: a new table, a view, triggers and indexes. Every migration is reversible (`DROP VIEW`, `DROP TRIGGER`, `DROP FUNCTION`, drop table), so a rollback is safe.
