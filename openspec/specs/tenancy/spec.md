# tenancy Specification

## Purpose
A company is the tenant boundary. This capability guarantees that an actor only ever sees or changes their own company's records.

## Requirements

### Requirement: Single-company membership
Each user SHALL belong to exactly one company, and the session SHALL NOT be able to change that company.

#### Scenario: Company is derived from the user, not the request
- **WHEN** a signed-in user sends a request containing a different `company_id`
- **THEN** the system ignores the supplied value and uses the user's own company

### Requirement: Unguessable public identifiers
Companies, users and invoices SHALL each have an immutable, randomly generated UUID as their public identifier. Every URL, link, form and page that references a company, user or invoice SHALL use this UUID. Internal sequential ids SHALL NOT appear in them. The acting company SHALL always come from the signed-in user and SHALL NEVER be read from a URL.

#### Scenario: Invoice URL uses the public identifier
- **WHEN** a user opens an invoice
- **THEN** the URL contains the invoice's UUID, and no sequential number appears in the URL or the page

#### Scenario: Sequential id in the URL
- **WHEN** a user requests an invoice URL with a sequential number in place of a UUID
- **THEN** the system responds 404

### Requirement: Cross-tenant records are indistinguishable from missing records
The system SHALL respond "not found" to any read or write that targets a record belonging to another company. The response SHALL be identical to the one for a record that does not exist.

#### Scenario: Guessed identifier from another company
- **WHEN** a user of company A requests an invoice UUID that belongs to company B (for example, one copied from a company B session)
- **THEN** the system responds 404 and reveals no data about the record

#### Scenario: Cross-tenant mutation attempt
- **WHEN** a user of company A submits a state-changing command for a company B record
- **THEN** the system responds 404 and the record is unchanged
