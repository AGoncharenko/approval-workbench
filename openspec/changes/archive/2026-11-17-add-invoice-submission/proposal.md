# Proposal

## Why

Invoices have to enter the workflow through a requester, so that `submitted_by` and the first audit event are real rather than seeded. Without this step, segregation of duties (no self-approval) can't be shown end to end.

## What Changes

- Requesters can create a `DRAFT` invoice with vendor, amount (entered as a decimal string, then parsed to minor units), currency and due date.
- Requesters can edit or discard their own drafts.
- Requesters can submit their own draft. This moves `DRAFT → PENDING`, bumps the version and writes an audit event.
- The submit command reuses the guarded transition from `approvals`: version check, idempotency key and an atomic audit event.
- Approvers and admins cannot create or submit invoices.
- Seeds move a fixed subset of the drafts to `PENDING`, `APPROVED` and `REJECTED` by calling the real submit/approve/reject commands. Each seeded step uses a deterministic idempotency key, so re-seeding replays instead of transitioning again.

## Capabilities

### New Capabilities
- `invoice-submission`: draft creation, amount parsing and the requester's submit transition.

### Modified Capabilities
- `demo-data`: adds the requirement that seeded non-draft invoices are produced through the real transitions, with consistent audit history.

## Impact

`InvoicesController#new/create/edit/update/destroy`, plus a `submit` member route. Depends on `add-invoice-review` (table) and `add-approval-commands` (transition command, audit events), so implement it after both.

Out of scope: attachments, bulk import, recalling a submitted invoice back to draft, and editing after submission.
