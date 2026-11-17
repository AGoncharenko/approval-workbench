# Tasks

## 1. Connection

- [ ] 1.1 `ApplicationCable::Connection` authenticates from the signed session cookie and rejects anonymous clients. Sign-out disconnects the user's sockets. Verify: `spec/channels/application_cable/connection_spec.rb` covers rejection without a session and acceptance with a session.

## 2. Broadcasts

- [ ] 2.1 `Invoice` `after_commit` calls `broadcast_refresh_to company, :invoices` (synchronous, with no job dependency). Verify: `spec/models/invoice_broadcast_spec.rb` uses `have_broadcasted_to` on the company stream, checks the payload has no invoice attributes, and checks that no broadcast happens on a rolled-back transaction.
- [ ] 2.2 Company B changes don't broadcast to company A's stream. Verify: same spec.

## 3. Views

- [ ] 3.1 `turbo_stream_from Current.company, :invoices` plus morph and scroll-preserve meta on the list and detail pages. Verify: request spec checks for a signed stream tag.
- [ ] 3.2 The decision form's reason, version and key live in a `data-turbo-permanent` element. Verify: system spec below.
- [ ] 3.3 System spec with two sessions:
  - approver 1 approves, and approver 2's open page shows APPROVED without a manual reload;
  - a reason typed by approver 2 survives the refresh, and a stale submit shows the conflict notice.

  Verify: `spec/system/realtime_refresh_spec.rb` is green.
