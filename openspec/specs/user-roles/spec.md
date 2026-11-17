# user-roles Specification

## Purpose
This capability lets company admins see their company's users and change their roles, without ever locking the company out of administration and with every change audited.

## Requirements

### Requirement: Admin-only user management
Only a user who currently has the `admin` role SHALL be able to view the user list or change roles. The list SHALL show every user of the admin's own company with name, email and current role. It SHALL show no user from another company.

#### Scenario: Admin opens the user list
- **WHEN** an admin of company A opens user management
- **THEN** every company A user is listed with their role, and no company B user appears

#### Scenario: Non-admin opens user management
- **WHEN** a requester or approver opens user management or posts a role change
- **THEN** the system responds 403 and nothing changes

#### Scenario: Another company's user
- **WHEN** an admin of company A posts a role change for a company B user's UUID
- **THEN** the system responds 404 and the user is unchanged

### Requirement: Role changes
An admin SHALL be able to set any other user of their company to `requester`, `approver` or `admin`. The new role SHALL apply from that user's next request, without signing them out. Only the role SHALL be changeable. Company, name and email SHALL NOT be.

#### Scenario: Revoke approver role
- **WHEN** an admin changes an approver to `requester`
- **THEN** the list shows the new role with a confirmation naming the user and the old and new role, and that user's next request is evaluated as a requester

#### Scenario: Unchanged role
- **WHEN** an admin saves a user's role without changing it
- **THEN** nothing changes and no audit event is written

#### Scenario: Invalid role
- **WHEN** a role change names a role outside `requester`, `approver` and `admin`
- **THEN** the system responds 422 with an error on that user's row and nothing changes

#### Scenario: Extra fields ignored
- **WHEN** a role change request also includes a company, email or name
- **THEN** only the role is considered, and the other fields are unchanged

### Requirement: Administration lockout guards
An admin SHALL NOT be able to change their own role. A role change SHALL NOT leave a company without any admin. The guard SHALL hold even when two admins submit changes at the same time.

#### Scenario: Admin changes own role
- **WHEN** an admin posts a role change for themselves
- **THEN** the system responds 403 and their role is unchanged

#### Scenario: Demoting the last other admin
- **WHEN** a change would leave the company with zero admins
- **THEN** the system responds 422 explaining that a company needs an admin, and nothing changes

#### Scenario: Two admins demote each other simultaneously
- **WHEN** the only two admins of a company each demote the other at the same moment
- **THEN** exactly one change applies, and the company still has one admin

### Requirement: Audited role changes
Every applied role change SHALL write exactly one role-change audit event in the same transaction as the change. The event records the company, the acting admin, the target user, the old and new role, and a server timestamp. If either write fails, neither SHALL persist.

#### Scenario: Role change recorded
- **WHEN** an admin changes a user's role
- **THEN** one role-change event appears in the company audit history with the admin, the user, the old role, the new role and the time
