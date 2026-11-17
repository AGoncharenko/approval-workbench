# authentication Specification

## Purpose
This capability identifies the acting user for every request with email and password sign-in and server-side sessions. The actor is re-validated against current data on every request.

## Requirements

### Requirement: Password sign-in
The system SHALL sign a user in only when the submitted email address and password match a stored user. Passwords SHALL be stored only as salted one-way hashes. The failure response SHALL NOT reveal whether the email exists.

#### Scenario: Valid credentials
- **WHEN** a visitor submits a seeded user's email and the correct password
- **THEN** a server-side session is created for that user and the invoice list is shown

#### Scenario: Invalid credentials
- **WHEN** a visitor submits an unknown email or a wrong password
- **THEN** sign-in fails with the same generic message in both cases, and no session is created

#### Scenario: Repeated failed attempts
- **WHEN** more than 10 sign-in attempts arrive from one client within 3 minutes
- **THEN** further attempts are refused until the window passes

### Requirement: Server-side sessions with sign-out
Each sign-in SHALL create a server-side session record. The browser SHALL hold only an opaque, signed, HTTP-only session identifier. Signing out SHALL destroy the server-side record so the identifier can't be reused.

#### Scenario: Sign out
- **WHEN** a signed-in user signs out
- **THEN** the session record is deleted and further app requests redirect to sign-in

#### Scenario: Replayed cookie after sign-out
- **WHEN** a request presents a session identifier whose record was destroyed
- **THEN** the request is treated as unauthenticated

### Requirement: Authentication required
The system SHALL redirect every application request without a valid session to the sign-in page. The health check and the sign-in page itself are the only exceptions.

#### Scenario: Anonymous request
- **WHEN** a request without a session targets the invoice list
- **THEN** the system redirects to sign-in

### Requirement: Actor re-validated per request
The system SHALL load the actor's current role and company from the database on every request. It SHALL NOT trust any role or company cached in the cookie or the page.

#### Scenario: Role revoked while page is open
- **WHEN** an approver's role changes to requester, and they then submit an approval from a page that was already open
- **THEN** the command is not applied, and because the invoice is no longer visible to a requester the system responds 404 with a notice that the invoice is no longer available to them

#### Scenario: User removed
- **WHEN** a user with no audit history is deleted while they have an active session
- **THEN** their sessions are removed and their next request redirects to sign-in
