# approvals Specification

## Purpose
This capability covers the rules and guarantees for deciding on pending invoices: who may approve or reject, what happens with stale or repeated commands, and how each decision is recorded atomically.

## Requirements

### Requirement: Eligible decision makers
The system SHALL allow a decision only when every condition holds:
- the actor currently has the `approver` role;
- the actor belongs to the invoice's company;
- the actor did not author the invoice;
- the invoice is `PENDING`.

The system SHALL evaluate these conditions on the server at command time, regardless of what the page displayed.

#### Scenario: Approver approves a pending invoice
- **WHEN** an approver who did not author a pending invoice approves it at its current version
- **THEN** the invoice becomes `APPROVED` and its version increases by one

#### Scenario: Admin attempts a decision
- **WHEN** an admin posts an approve or reject command for a pending invoice in their company
- **THEN** the system responds 403 and the invoice is unchanged

#### Scenario: Requester attempts a decision on their own invoice
- **WHEN** a requester posts an approve command for a pending invoice they authored
- **THEN** the system responds 403 and the invoice is unchanged

#### Scenario: Requester attempts a decision on someone else's invoice
- **WHEN** a requester posts an approve command for a pending invoice authored by another requester
- **THEN** the system responds 404 and the invoice is unchanged

#### Scenario: Self-approval
- **WHEN** a user who authored an invoice as a requester and was later made an approver posts a decision on that invoice
- **THEN** the system responds 403 and the invoice is unchanged

#### Scenario: Decision on a decided invoice
- **WHEN** an approver posts a decision for an invoice that is already `APPROVED` or `REJECTED`
- **THEN** the system responds 409, shows the current status and its latest actor, and writes no event

#### Scenario: Decision on a draft
- **WHEN** an approver posts a decision for a draft's UUID
- **THEN** the system responds 404, because drafts are visible only to their author

#### Scenario: Cross-tenant decision
- **WHEN** an approver posts a decision for another company's invoice UUID
- **THEN** the system responds 404 and the invoice is unchanged

### Requirement: Refusal precedence
A refused command SHALL apply nothing and write no event. The system SHALL choose the response in this order:
- 404 when the invoice isn't visible to the actor under the `invoices` visibility rules;
- 403 when the invoice is visible but the actor may not take the action;
- 409 when the action is allowed but the status or version no longer matches.

#### Scenario: Invisible and stale at once
- **WHEN** a requester posts a stale approval for another requester's invoice
- **THEN** the system responds 404, not 403 or 409

### Requirement: Rejection requires a reason
A rejection SHALL include a non-blank reason of at most 1000 characters. The reason SHALL be stored with the audit event.

#### Scenario: Reject without reason
- **WHEN** an approver rejects with a blank reason
- **THEN** the command is refused with a field error and nothing changes

### Requirement: Stale commands never apply
Every decision SHALL state the invoice version the actor saw. If the invoice's current version differs, the system SHALL NOT apply the command. It SHALL report a conflict that shows the current status, the version, and the actor and time of the latest change.

#### Scenario: Two approvers act on the same version
- **WHEN** two approvers both open version 7, one approves, and then the other rejects with expected version 7
- **THEN** the approval applies, the rejection is reported as a conflict showing `APPROVED` by the first approver, and exactly one event exists for that transition

#### Scenario: Simultaneous decisions
- **WHEN** two decisions on the same version arrive at the same moment
- **THEN** exactly one applies, the other is reported as a conflict, and exactly one event is written

### Requirement: Idempotent retries
Every decision SHALL carry a client-generated idempotency key. Keys are scoped to the acting user and company.
- A command whose key was already applied with an identical payload SHALL return the original outcome without applying again.
- A reused key with a different payload (action, invoice, expected version or reason) SHALL be rejected with 422 and SHALL NOT apply.

#### Scenario: Browser retries after a timeout
- **WHEN** the server commits an approval, the response is lost, and the browser resends the same form
- **THEN** the system reports that the approval was already recorded, with its original time, and the invoice is not changed again

#### Scenario: Concurrent duplicates
- **WHEN** two identical requests with the same key arrive at the same moment
- **THEN** exactly one applies, and the other returns the same applied outcome

#### Scenario: Key reused with different payload
- **WHEN** a key that applied an approval is sent again with action reject
- **THEN** the system responds 422 and nothing changes

#### Scenario: Missing key
- **WHEN** a decision arrives without an idempotency key
- **THEN** the system responds 422 and nothing changes

### Requirement: Atomic audit of every transition
Every applied transition SHALL write exactly one audit event in the same transaction as the status change. The event records the company, invoice, actor, the actor's role at that moment, the action, the from and to status, the reason if any, and a server timestamp. If either write fails, neither SHALL persist.

#### Scenario: Audit write fails
- **WHEN** the audit insert fails during an approval
- **THEN** the invoice status and version are unchanged

#### Scenario: Refused commands leave no trace in workflow state
- **WHEN** a command is refused for authorization, conflict or validation
- **THEN** no audit event is written and the invoice version is unchanged

### Requirement: Honest outcome reporting
The system SHALL show the user which of these outcomes occurred: applied, already recorded (replay), conflict, not allowed, or not found. After any outcome, the invoice view SHALL show the current server state.

#### Scenario: Conflict view
- **WHEN** a decision is reported as a conflict
- **THEN** the page shows a conflict notice with the current status and latest actor, and the decision controls reflect the current state

### Requirement: Honest handling of ambiguous network failures
When a decision request fails without a server response (a timeout, a dropped connection or going offline), the client SHALL NOT claim success or failure. It SHALL tell the user that the outcome is unknown. It SHALL keep the form with the same idempotency key, so retrying can't apply the decision twice.

#### Scenario: Timeout after the server committed
- **WHEN** an approval commits on the server but the browser receives no response
- **THEN** the page says the outcome could not be confirmed and offers "Retry". Retrying returns "already recorded" with the original time, and the invoice has one approve event

#### Scenario: Timeout before the server received the request
- **WHEN** a decision never reaches the server and the user retries
- **THEN** the retry applies the decision once, using the same idempotency key

#### Scenario: Reload instead of retry
- **WHEN** after an unknown outcome the user reloads the invoice instead of retrying
- **THEN** the page shows the authoritative current status and history, with no notice claiming the decision succeeded or failed
