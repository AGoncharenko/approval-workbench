# invoice-submission Specification

## Purpose
This capability covers how a requester creates, edits, discards and submits their own draft invoices. Amounts are entered as exact decimals and become minor units.

## Requirements

### Requirement: Requester creates drafts
Only a requester SHALL be able to create an invoice. A new invoice SHALL start as `DRAFT` at version 1, owned by its author and in the author's company. Vendor (1 to 200 characters), amount, a supported currency and a due date SHALL all be required.

#### Scenario: Requester creates a draft
- **WHEN** a requester submits a valid new-invoice form
- **THEN** a `DRAFT` invoice at version 1 is created in their company, with them as author

#### Scenario: Non-requester tries to create
- **WHEN** an approver or admin posts a new invoice
- **THEN** the system responds 403 and nothing is created

#### Scenario: Company in the request body is ignored
- **WHEN** a requester's create request includes another company's id
- **THEN** the invoice is created in the requester's own company

### Requirement: Exact amount parsing
The system SHALL convert the entered amount to integer minor units using the currency's exponent, and SHALL NOT round. Input with more decimal places than the currency allows, a negative value, a value above the invoice maximum or a non-numeric value SHALL be rejected with a field error, never a server error.

#### Scenario: Valid USD amount
- **WHEN** a requester enters `1,234.56` with currency USD
- **THEN** the stored total is 123456 minor units

#### Scenario: Too many decimals
- **WHEN** a requester enters `10.005` with currency USD, or `1.5` with currency JPY
- **THEN** the form is rejected with an amount error and nothing is saved

#### Scenario: Amount above the maximum
- **WHEN** a requester enters `1,000,000,000,000.00` with currency USD
- **THEN** the form is rejected with an amount error and nothing is saved

### Requirement: Draft editing and discarding
A requester SHALL be able to edit or discard only their own drafts. An edit SHALL require the version the requester last saw. It SHALL fail with a conflict if the draft changed since then. A successful edit increments the version. Non-draft invoices SHALL NOT be editable or discardable by anyone.

#### Scenario: Edit own draft
- **WHEN** a requester saves changes to their draft at the version they opened
- **THEN** the fields update and the version increases by one

#### Scenario: Edit after submission
- **WHEN** a requester tries to edit or discard their invoice after it has been submitted
- **THEN** the system refuses the change and the invoice is unchanged

#### Scenario: Stale draft edit
- **WHEN** a requester saves a draft whose version moved on since they opened it (for example, edited in another tab)
- **THEN** the system reports a conflict and shows the current values, and nothing is overwritten

### Requirement: Submit for approval
A requester SHALL be able to submit their own draft, moving it from `DRAFT` to `PENDING`. Submission SHALL follow the same version check, idempotency and audit rules as approval decisions.

#### Scenario: Submit own draft
- **WHEN** a requester submits their draft at the current version
- **THEN** the invoice becomes `PENDING`, the version increases by one, and a `submit` audit event records the requester

#### Scenario: Submit another user's draft
- **WHEN** a requester attempts to submit a draft they did not author
- **THEN** the system responds 404, because drafts are visible only to their author

#### Scenario: Duplicate submit
- **WHEN** the same submit request is retried with the same idempotency key
- **THEN** the original result is returned and no second event is written
