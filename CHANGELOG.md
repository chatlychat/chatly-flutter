# Changelog

All notable changes to the Chatly Flutter SDK are documented here.

## Unreleased

### Fixed

- **Realtime could not connect, at all, for anyone.** The handshake sent
  `{ publicId, visitorToken }` with the long-lived session token from
  `/v1/widget/init`. The gateway accepts `{ token, kind? }` where `kind`
  **defaults to agent**, so a visitor's HS256 token was verified as RS256
  against the platform public key and refused with a bare `Unauthorized`
  naming neither credential. The socket now mints a conversation-scoped token
  at `POST /v1/widget/realtime/token` and sends `{ token, kind: 'visitor' }`.

  The auth payload is a per-attempt callback (`setAuthFn`), re-read on every
  reconnect, and the token is re-minted when the socket drops: a frozen
  credential outlives its 1h TTL and is then refused silently for the rest of
  the session. `Chatly.openConversation(id)` is new and is what opens the
  socket — a realtime token names ONE conversation, so there is no
  session-wide visitor socket. `ChatlyChatPage` calls it for you.

  `subscribe()` is gone: the gateway registers no `subscribe` listener for a
  visitor (its room comes from the token's claim), and this emitted an
  envelope on the `event` channel, which nothing has ever read. `typingStart`
  / `typingStop` now emit on `typing.start` / `typing.stop`, which is where
  the gateway listens; `markRead` is new.

- **`uploadAttachment` posted a shape the route does not accept.** It sent
  `{ filename, mimeType, data }` — base64 bytes — to
  `POST /v1/widget/uploads/presign`, whose schema is
  `{ visitorToken, publicId, filename, contentType, sizeBytes }` and which
  takes no bytes at all, so zod dropped two keys and answered 400 on the
  missing `contentType`. It is now the real three-step flow: presign, PUT the
  raw bytes to the returned URL with the returned method and headers, then put
  `{ id, filename, mimeType, sizeBytes, url }` on the message.

- **The three refusal messages are no longer collapsed into "Upload failed.
  Try again."** Attachments off for the channel, a MIME type outside the
  allow-list and a file over the cap each have copy written for the visitor;
  `ChatlyRestException.visitorMessage` carries it and the composer shows it.
  `ChatlyUploadException` is new, for a failure in the half of the flow that
  does not go through our API.

## 0.1.0

Initial public release.

- `Chatly.instance.configure(ChatlyConfig)` — one-time SDK bootstrap.
- `Chatly.instance.identify(ChatlyIdentity)` — attach a known user.
- `Chatly.instance.setPushToken(token)` — register a push token (APNs / FCM).
- `Chatly.instance.show(context)` — open the full-page chat route.
- `ChatlyWidget()` — embeddable floating-bubble widget.
- Streamed `unreadCount`, `messages`, and `events` for app-level reactivity.
- REST client mirroring the public `/v1/widget/*` endpoints.
- Socket.IO realtime transport speaking the v1 envelope protocol.
- Material 3 default chat UI with a customisable `ChatlyTheme`.
- Secure visitor-token persistence via `flutter_secure_storage`.
- Knowledge-base search + article retrieval helpers.
