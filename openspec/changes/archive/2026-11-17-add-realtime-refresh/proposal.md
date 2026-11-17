# Proposal

## Why

When two approvers have the same invoice open, the second one should learn that it changed before acting on stale information, not only after a conflict. Live updates must never become a second source of truth, or a channel that leaks data across tenants or roles.

## What Changes

- After any committed invoice change, the server publishes a content-free "changed" signal to that company's stream.
- Open invoice list and detail pages that receive the signal re-request themselves from the server, using the viewer's own session, and morph to the authoritative state. The signal carries no invoice data.
- A text the user is typing (for example a rejection reason) is preserved across a refresh. Their pending decision still carries the version they saw, and if that version is stale, the version check reports the conflict honestly.
- Realtime connections require an authenticated session.
- If the realtime connection drops, pages keep working, and the version check on submit stays authoritative.

## Capabilities

### New Capabilities
- `realtime`: live refresh of open views from authoritative state, with no data in the signal.

### Modified Capabilities

## Impact

- Action Cable with Solid Cable, which is already in the Rails 8 stack: no Redis.
- `turbo_stream_from` on the list and detail pages.
- An `after_commit` broadcast on `Invoice`.
- An authenticated `ApplicationCable::Connection`.

Depends on `add-approval-commands`.

Out of scope: push or email notifications, presence indicators ("Alex is viewing"), and an offline queue.
