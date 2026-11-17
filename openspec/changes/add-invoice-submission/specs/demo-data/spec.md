# Spec Delta

## ADDED Requirements

### Requirement: Seeded workflow history is consistent
Every seeded invoice whose status is not `DRAFT` SHALL reach that status through the same guarded transitions users trigger. Its audit history SHALL therefore record every step, with the actor, the from/to status and a timestamp. Its version SHALL equal 1 plus the number of transitions.

#### Scenario: Seeded approved invoice
- **WHEN** demo data includes an `APPROVED` invoice
- **THEN** its history shows a `submit` event by its requester followed by an `approve` event by an approver other than the requester, and its version is 3

#### Scenario: Re-seeding does not re-transition
- **WHEN** demo data is loaded again
- **THEN** no seeded invoice gains additional audit events and no version changes
