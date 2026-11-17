# realtime Specification

## Purpose
This capability keeps open invoice views close to current by signalling changes. Every displayed value still comes from an authorized server read.

## Requirements

### Requirement: Change signals carry no data
When an invoice change commits, the system SHALL send a change signal to open views of that invoice's company. The signal SHALL contain no invoice fields, amounts, names or statuses.

#### Scenario: Inspecting a signal
- **WHEN** an invoice is approved and the signal is captured
- **THEN** it contains only a refresh instruction, with no invoice data

### Requirement: Views refresh from authoritative state
On receiving a change signal, an open invoice list or detail view SHALL re-read itself from the server under the viewer's own session and visibility rules, and display the result.

#### Scenario: Second approver sees the decision
- **WHEN** approver 1 approves an invoice that approver 2 has open
- **THEN** approver 2's page updates to show `APPROVED`, the new version and the new history entry, and their decision controls are no longer offered

#### Scenario: Signal arrives before the command response
- **WHEN** the acting user's page receives the change signal before its own command response
- **THEN** the final display matches the server state, with no duplicated history rows and no contradictory notices

#### Scenario: Requester does not gain visibility
- **WHEN** a change signal arrives for an invoice the viewing requester is not allowed to see
- **THEN** the refreshed list still excludes that invoice

### Requirement: Realtime is tenant-isolated and authenticated
Only authenticated users SHALL be able to open a realtime connection. A user SHALL receive signals only for their own company.

#### Scenario: Anonymous connection
- **WHEN** a client without a valid session opens a realtime connection
- **THEN** the connection is refused

#### Scenario: Other company's change
- **WHEN** an invoice in company B changes
- **THEN** no signal reaches company A users

### Requirement: Realtime is an enhancement, not a guarantee
Missing, delayed or duplicated signals SHALL NOT affect correctness. Commands SHALL remain protected by version checks whether or not a refresh occurred.

#### Scenario: Realtime unavailable
- **WHEN** the realtime connection is down and another user approves the invoice
- **THEN** a stale decision is still reported as a conflict on submit

#### Scenario: In-progress input preserved
- **WHEN** a refresh arrives while the user is typing a rejection reason
- **THEN** the typed text remains, and if they submit, the command still uses the version they saw, giving a conflict if that version is stale
