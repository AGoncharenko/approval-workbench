# Design

## Context

Rails 8 ships Turbo 8 page refreshes with morphing, and Solid Cable (Action Cable backed by Postgres). Invoice views are server-rendered per viewer.

## Goals / Non-Goals

**Goals:** fresher screens with zero new trust surface.

**Non-Goals:** sub-second guarantees, and diff-style partial streams.

## Decisions

- **Broadcast a refresh, not content.** `Invoice` has `after_commit -> { broadcast_refresh_to company, :invoices }`, synchronous rather than `_later`, so refreshes don't depend on Solid Queue, which pauses while a free Render instance sleeps. The pages subscribe with `turbo_stream_from Current.company, :invoices`.
  - Turbo then re-fetches the page under the viewer's session, so visibility, role and tenant rules apply automatically.
  - Turbo debounces refreshes, and it ignores refreshes caused by the same client's own request (`X-Turbo-Request-Id`). That handles the case where the signal arrives before the response.
  - Alternative: `broadcast_replace_to` with rendered partials. Rejected: a partial rendered once for all subscribers can't respect per-viewer visibility, so it risks leaking data across roles.
- **`<meta name="turbo-refresh-method" content="morph">` and `turbo-refresh-scroll="preserve"`.** The decision form is split so that:
  - the reason `<textarea>` is `data-turbo-permanent`, and keeps what the user typed;
  - the hidden `expected_version` and idempotency key are also inside the permanent element, so they keep the version the user actually reviewed.

  This is deliberate: if they act, the version check makes the result honest. The refreshed status and history above the form show them that it changed.
- **Stream names are signed** (Turbo's `signed_stream_name`), derived from the company GlobalID. They can't be guessed, and a client can only subscribe to a stream name the server rendered for them.
- **`ApplicationCable::Connection`** finds the session from the signed `session_id` cookie and rejects the connection without one. The connection is identified by `current_user`. When a user signs out, `ActionCable.server.remote_connections.where(current_user:).disconnect` closes their sockets.
- **Solid Cable on the primary Postgres** (the Rails 8 default multi-DB `cable` config). No Redis to operate.

## Risks / Trade-offs

- [Refresh storms under heavy write load, since every change refreshes every open company view] → Debounced. At scale, narrow the streams to per-invoice for detail pages and add throttling.
- [Morphing breaks a third-party widget] → None are used. Keep the forms simple.
- [Solid Cable polling latency (about 100 ms by default)] → Acceptable for this use.
