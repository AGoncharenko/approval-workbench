# invoices Specification

## Purpose
This capability covers invoice records and how actors read them: exact money with currency, status and version, and visibility filtered by role inside the actor's company.

## Requirements

### Requirement: Exact money with currency
The system SHALL store every invoice total as an integer number of minor units together with an ISO-4217 currency code. The system SHALL reject a negative total, a total above 99,999,999,999,999 minor units (for example USD 999,999,999,999.99), a missing currency or a malformed currency.

#### Scenario: Persisting a malformed amount
- **WHEN** an invoice is saved with a negative total, a total above the maximum, or a currency that is not three uppercase letters
- **THEN** the database rejects the write

#### Scenario: Displaying amounts per currency exponent
- **WHEN** invoices of 123456 minor units are displayed in USD, JPY and BHD
- **THEN** they render as `USD 1,234.56`, `JPY 123,456` and `BHD 123.456` respectively

### Requirement: Invoice status and version
Every invoice SHALL have a status of `DRAFT`, `PENDING`, `APPROVED` or `REJECTED`, and an integer version that starts at 1. The version SHALL increase by one on every change to the invoice, whether a field edit or a status transition. `APPROVED` and `REJECTED` SHALL be terminal. Approval SHALL only record a decision and SHALL NOT trigger or imply payment.

#### Scenario: Unknown status
- **WHEN** an invoice is saved with a status outside the allowed set
- **THEN** the database rejects the write

#### Scenario: Approved invoice is final
- **WHEN** an invoice is `APPROVED`
- **THEN** no further transition is offered or accepted, and the detail page labels it "Approved (not paid)"

### Requirement: Role-filtered invoice list
The system SHALL list only invoices in the actor's company. A requester SHALL see only invoices they authored, including their drafts. Approvers and admins SHALL see every non-draft invoice of their company. Drafts SHALL be visible only to their author. The list SHALL be filterable by status, ordered by due date (soonest first) and paginated.

#### Scenario: Approver lists invoices
- **WHEN** an approver of company A opens the invoice list
- **THEN** every non-draft company A invoice is listed, and no draft and no company B invoice appears

#### Scenario: Requester lists invoices
- **WHEN** a requester opens the invoice list
- **THEN** only invoices they authored appear, including their drafts

#### Scenario: Filter by status
- **WHEN** a user filters the list by `PENDING`
- **THEN** only pending invoices visible to that user appear

#### Scenario: Empty result
- **WHEN** no invoices match the filter
- **THEN** an explicit empty-state message is shown

### Requirement: Invoice detail
The system SHALL show an invoice's vendor, amount with currency, due date, status, version and approval history to any actor allowed to list it. Any other actor SHALL get "not found".

#### Scenario: Requester opens another requester's invoice
- **WHEN** a requester opens the detail of a same-company invoice they did not author
- **THEN** the system responds 404

### Requirement: Accessible interface states
Invoice list and detail views SHALL present loading, empty, not-found, conflict and failure states as text that assistive technology can perceive. They SHALL NOT rely on color alone, and SHALL be operable by keyboard. Status SHALL always be shown as a text label.

#### Scenario: Pending request
- **WHEN** a list filter or form submission is in progress
- **THEN** the affected region is marked busy, the submit control is disabled with a text label such as "Saving…", and the change is announced to screen readers

#### Scenario: Not found
- **WHEN** a user opens an invoice that is missing or not visible to them
- **THEN** a 404 page explains, in text, that the invoice is not available, and links back to the list

#### Scenario: Keyboard-only use
- **WHEN** a user operates the list, filters, detail page and decision form with only a keyboard
- **THEN** every control is reachable in a logical order, with a visible focus indicator
