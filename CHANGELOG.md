# Changelog

All notable changes to the Chatly Flutter SDK are documented here.

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
