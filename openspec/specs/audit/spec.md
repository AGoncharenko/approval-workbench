# audit Specification

## Purpose
This capability covers the durable, append-only record of invoice workflow transitions and user role changes, and who may read it.

## Requirements

### Requirement: Append-only audit events
Once written, an audit event, whether an invoice transition or a role change, SHALL NOT be modified or deleted through the application or through the application's database role.

#### Scenario: Attempted update
- **WHEN** any code path tries to update an existing audit event
- **THEN** the database rejects the statement and the event is unchanged

#### Scenario: Attempted delete
- **WHEN** any code path tries to delete an audit event
- **THEN** the database rejects the statement and the event remains

### Requirement: Actor identity preserved
Each audit event SHALL identify the acting user and the role that user held at the time of the action. A user who has audit events SHALL NOT be hard-deleted.

#### Scenario: Role changes after acting
- **WHEN** an approver approves an invoice and is later changed to requester
- **THEN** the audit event still shows them acting as approver

#### Scenario: Deleting a user with history
- **WHEN** an operator tries to delete a user who has audit events
- **THEN** the deletion is refused and the history stays intact

### Requirement: Company audit history for admins
An admin SHALL be able to view every audit event of their own company, both invoice transitions and role changes, in one history, newest first and paginated. They SHALL be able to filter by event type or action, actor, invoice and date range. Other roles SHALL be refused. Events of other companies SHALL never appear.

#### Scenario: Admin views history
- **WHEN** an admin of company A opens the audit history
- **THEN** all company A events are listed newest first, showing the time, actor, actor's role, action, from/to status and reason, and no company B event appears. Role-change entries show the acting admin, the target user, and the old and new role

#### Scenario: Filter by actor and action
- **WHEN** an admin filters by one approver and action `reject`
- **THEN** only that approver's rejections in the company are listed

#### Scenario: Non-admin opens audit history
- **WHEN** a requester or approver opens the audit history
- **THEN** the system responds 403

#### Scenario: Filter by role changes
- **WHEN** an admin filters by event type `role change`
- **THEN** only role-change events of the company are listed

#### Scenario: Forged filter for another company's invoice
- **WHEN** an admin of company A filters by an invoice UUID from company B
- **THEN** the result is empty

### Requirement: Per-invoice history
Any actor allowed to view an invoice SHALL see its full audit history on the invoice detail page, in chronological order.

#### Scenario: Approver views an approved invoice
- **WHEN** an approver opens an approved invoice
- **THEN** they see a `submit` event and an `approve` event, each with its actor and time
