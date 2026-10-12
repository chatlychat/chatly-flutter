# Chatly Flutter SDK

Official Flutter SDK for [Chatly](https://chatlychat.com) — a live chat and
customer messaging platform.

The package ships with:

- A singleton client (`Chatly.instance`) speaking the public `/v1/widget/*`
  REST surface.
- A realtime Socket.IO transport implementing the v1 envelope protocol.
- An embeddable bubble widget (`ChatlyWidget`) and a full-page chat
  experience (`ChatlyChatPage`).
- Knowledge-base search and article retrieval helpers.
- Secure visitor-token persistence via `flutter_secure_storage`.

## Install

```yaml
dependencies:
  chatly: ^0.1.0
```

Then run `flutter pub get`.

## Hello world

```dart
import 'package:flutter/material.dart';
import 'package:chatly/chatly.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Chatly.instance.configure(
    const ChatlyConfig(
      publicId: 'pub_abc123',
      apiHost: 'api.chatlychat.com',
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Center(child: Text('Hello!')),
            const ChatlyWidget(), // floating bubble bottom-right
          ],
        ),
      ),
    );
  }
}
```

To open the bundled full-page chat route from your own button:

```dart
ElevatedButton(
  onPressed: () => Chatly.instance.show(context),
  child: const Text('Talk to us'),
);
```

## Identifying users

```dart
await Chatly.instance.identify(
  const ChatlyIdentity(
    externalId: 'user_42',
    email: 'alice@example.com',
    name: 'Alice',
    // userHash: '<HMAC computed server-side>', // if Identity Verification on
  ),
);
```

## Listening to streams

```dart
Chatly.instance.unreadCount.listen((n) => print('Unread: $n'));
Chatly.instance.messages.listen((m) => print('New: ${m.body}'));
Chatly.instance.events.listen((env) => print('Event: ${env.type}'));
```

## Theme customisation

`ChatlyConfig.theme` accepts a `ChatlyTheme`. Defaults:

| Token            | Default           |
| ---------------- | ----------------- |
| `primary`        | `Color(0xFF2563EB)` |
| `background`     | `Color(0xFFFFFFFF)` |
| `foreground`     | `Color(0xFF0F172A)` |
| `mutedForeground`| `Color(0xFF64748B)` |

```dart
await Chatly.instance.configure(
  ChatlyConfig(
    publicId: 'pub_abc123',
    apiHost: 'api.chatlychat.com',
    theme: const ChatlyTheme(
      primary: Color(0xFF8B5CF6),
      headerTitle: 'Support',
      borderRadius: 20,
    ),
  ),
);
```

## Push notifications

The SDK forwards a device token to the Chatly backend so agent replies can
wake the app. Wire it up to your push handler of choice:

```dart
// Inside your FCM / APNs handler:
await Chatly.instance.setPushToken(token);
```

Platform is auto-detected (`apns` on iOS / macOS, `fcm` on Android). Pass
`platformOverride` if your stack routes both providers through a single app
instance.

### iOS

Add `UIBackgroundModes` -> `remote-notification` to `Info.plist` and request
notification permission from the OS as usual. Then forward the APNs token
once received.

### Android

Configure Firebase Cloud Messaging and forward the FCM token returned by
`FirebaseMessaging.instance.getToken()`.

## Knowledge base

```dart
final hits = await Chatly.instance.searchKb(query: 'refund policy');
final article = await Chatly.instance.getKbArticle(hits.first.slug);
```

## License

MIT — see [LICENSE](./LICENSE).

---

## About this repository

This is a **mirror**. `chatly-flutter` is built from a private monorepo where the rest
of the platform, its migrations and its contract checks live, so a pull request here
cannot be merged directly — but a patch is still the fastest way to get something
fixed and we will port it with attribution.

What you can do here: read the source, run the tests, open an issue, or open a PR
and we will treat the diff as the proposal.

Issues: https://github.com/chatlychat/chatly-flutter/issues · Docs: https://chatlychat.com/docs
