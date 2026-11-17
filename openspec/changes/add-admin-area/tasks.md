# Tasks

## 1. Schema and immutability

- [x] 1.1 Migration: `role_change_events`, with composite FKs to `users(company_id, id)` and a unique `users (company_id, id)` index. Verify: `spec/models/role_change_event_spec.rb` shows that an event whose target is in another company is rejected by the DB.
- [x] 1.2 Reversible migration: a `forbid_audit_mutation()` trigger on `approval_events` and `role_change_events`. Verify: `spec/db/audit_append_only_spec.rb` checks that `update_all`, `delete_all` and raw SQL UPDATE/DELETE raise on both tables, and the rows are unchanged.
- [x] 1.3 Model guards: `readonly?` is true after create on both event models. Verify: model specs expect `ActiveRecord::ReadOnlyRecord`.
- [x] 1.4 A user with events can't be deleted. Verify: model spec expects a FK violation and the history intact.
- [x] 1.5 `audit_entries` view (`UNION ALL`) and a read-only `AuditEntry` model. Verify: `spec/models/audit_entry_spec.rb` shows both kinds listed with common columns, and writes raising.

## 2. Admin base

- [x] 2.1 `admin` namespace routes (`users` index/update, `audit_events` index) and `Admin::BaseController` requiring admin. Verify: `spec/requests/admin/access_spec.rb` expects requester and approver to get 403 on every admin route, and `GET /admin/users/:uuid` to return 404.

## 3. User roles

- [x] 3.1 `ChangeUserRole` service with company lock, scoped lookup, self-change, invalid, unchanged and last-admin guards, and an atomic event insert. Verify: `spec/services/change_user_role_spec.rb` covers each outcome, an unchanged role writing no event, and a forced event-insert failure leaving the role unchanged.
- [x] 3.2 Concurrency: two threads where two admins demote each other. Verify: `spec/services/change_user_role_concurrency_spec.rb` expects exactly 1 applied and 1 admin remaining.
- [x] 3.3 `Admin::UsersController#index/update`: a list of company users with an inline role form per row (labelled select), only `role` permitted, a confirmation notice, and 422 with a row error re-rendering the index. Verify: `spec/requests/admin/users_spec.rb` covers another company's user UUID (404), forged `company_id`/`email` params ignored, own row with no select, and own-change POST giving 403.
- [x] 3.4 Effect without sign-out: after an approver is changed to requester, their existing session's next decision is refused. Verify: request spec with 2 sessions.

## 4. Audit history

- [x] 4.1 `AuditFilter` (event type or action, actor UUID, invoice UUID, date range) over `Current.company.audit_entries`, plus base-table indexes. Verify: `spec/queries/audit_filter_spec.rb` covers each filter, plus forged company-B UUIDs returning empty.
- [x] 4.2 `Admin::AuditEventsController#index`, newest first and paginated, showing transition and role-change entries. Verify: `spec/requests/admin/audit_events_spec.rb` shows the admin getting 200 with own-company entries only, and role-change rows with from/to role.
- [x] 4.3 The actor's role at the time is shown. Verify: request spec changes a user's role after they acted and expects the old role still displayed on their earlier event.

## 5. Per-invoice history

- [x] 5.1 Shared history partial on invoice detail, in chronological order. Verify: request spec checks that an approved seeded invoice shows the submit and approve events.

## 6. End to end

- [x] 6.1 System spec: the admin demotes an approver on `/admin/users`, and the approver's already-open invoice page then refuses the approval with the "no longer available" notice. The admin sees the role change on `/admin/audit_events`. Verify: `spec/system/admin_role_revocation_spec.rb` is green.
