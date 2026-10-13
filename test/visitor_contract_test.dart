/// The visitor contract, asserted on what the SDK SENDS.
///
/// Two defects, both of which a response-shaped test cannot see:
///
///   1. the socket handshake sent `{ publicId, visitorToken }` — the gateway
///      accepts `{ token, kind? }` and `kind` DEFAULTS TO AGENT, so a
///      visitor's HS256 token was verified as RS256 against the platform
///      public key and refused with a bare `Unauthorized`;
///   2. `uploadAttachment` posted `{ filename, mimeType, data }` to
///      `POST /v1/widget/uploads/presign`, which takes
///      `{ visitorToken, publicId, filename, contentType, sizeBytes }` and no
///      bytes at all — zod drops `mimeType` and `data` and answers 400 on the
///      missing `contentType`.
///
/// A fake transport that answers every route with whatever the SDK asked for
/// agrees with both bugs. These assert on the request.
///
/// Ground truth: `docs/prompts/5/mobile-sdk-visitor-contract.md`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatly/chatly.dart';
import 'package:chatly/src/transport/rest_client.dart';
import 'package:chatly/src/transport/socket_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ChatlyConfig _config = ChatlyConfig(
  publicId: 'pub_test',
  apiHost: 'api.chatly.test',
);

/// The session token, which must never reach the gateway.
const String _sessionToken = 'vt_session_long_lived';

/// A socket that records instead of connecting.
class _FakeSocket implements ChatlySocketHandle {
  final Map<String, void Function(Object?)> handlers =
      <String, void Function(Object?)>{};
  final List<List<Object?>> emissions = <List<Object?>>[];
  bool connectCalled = false;
  bool disposed = false;

  @override
  bool get connected => connectCalled && !disposed;

  @override
  void on(String event, void Function(Object? data) handler) {
    handlers[event] = handler;
  }

  @override
  void emit(String event, [Object? data]) {
    emissions.add(<Object?>[event, data]);
  }

  @override
  void connect() {
    connectCalled = true;
  }

  @override
  void dispose() {
    disposed = true;
  }

  void fire(String event, [Object? data]) => handlers[event]?.call(data);
}

/// Drains pending microtasks so an async re-mint can land.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Invokes the handshake hook and returns what the gateway would receive.
Map<String, Object?> _handshakeAuth(Map<String, dynamic> options) {
  final fn = options['auth'];
  expect(
    fn,
    isA<Function>(),
    reason: 'auth must be a per-attempt callback, or a reconnect replays an '
        'expired token verbatim for the rest of the session',
  );
  Map<String, Object?>? seen;
  (fn as void Function(void Function(Map<dynamic, dynamic> auth)))(
    (Map<dynamic, dynamic> auth) => seen = Map<String, Object?>.from(auth),
  );
  expect(seen, isNotNull, reason: 'the auth callback never called back');
  return seen!;
}

void main() {
  group('the visitor handshake', () {
    late List<String> minted;
    late List<Map<String, dynamic>> opened;
    late List<String> openedUrls;
    late List<_FakeSocket> sockets;

    ChatlySocketTransport build() {
      minted = <String>[];
      opened = <Map<String, dynamic>>[];
      openedUrls = <String>[];
      sockets = <_FakeSocket>[];
      return ChatlySocketTransport(
        config: _config,
        workspaceId: 'w_1',
        contactId: 'c_1',
        mintToken: (String conversationId) async {
          minted.add(conversationId);
          return ChatlyRealtimeToken(
            token: 'rt_${conversationId}_${minted.length}',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          );
        },
        opener: (String url, Map<String, dynamic> options) {
          openedUrls.add(url);
          opened.add(options);
          final socket = _FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
    }

    test("carries kind: 'visitor'", () async {
      final transport = build();
      await transport.connectTo('conv_1');
      expect(_handshakeAuth(opened.last)['kind'], 'visitor');
      await transport.dispose();
    });

    test('carries a MINTED realtime token, never the session token', () async {
      final transport = build();
      await transport.connectTo('conv_1');
      expect(minted, <String>['conv_1']);
      final auth = _handshakeAuth(opened.last);
      expect(auth['token'], 'rt_conv_1_1');
      expect(auth['token'], isNot(_sessionToken));
      // The gateway schema is exactly { token, kind? }.
      expect(auth.keys.toList()..sort(), <String>['kind', 'token']);
      await transport.dispose();
    });

    test('opens the realtime URL with websocket transport', () async {
      final transport = build();
      await transport.connectTo('conv_1');
      expect(openedUrls.single, 'wss://api.chatly.test');
      expect(opened.last['transports'], <String>['websocket']);
      expect(sockets.single.connectCalled, isTrue);
      await transport.dispose();
    });

    test('re-reads the auth payload on a second attempt', () async {
      final transport = build();
      await transport.connectTo('conv_1');
      expect(_handshakeAuth(opened.last)['token'], 'rt_conv_1_1');

      // The socket dropped. socket.io retries on its own backoff; what it
      // retries WITH is the bug — a 1h TTL outlives plenty of mobile
      // sessions, and a frozen credential is refused silently forever after.
      sockets.single.fire('disconnect', 'transport close');
      await _settle();

      expect(minted.length, 2, reason: 'a reconnect must re-mint');
      expect(_handshakeAuth(opened.last)['token'], 'rt_conv_1_2');
      expect(_handshakeAuth(opened.last)['kind'], 'visitor');
      await transport.dispose();
    });

    test('re-mints and reconnects when the conversation changes', () async {
      final transport = build();
      await transport.connectTo('conv_1');
      await transport.connectTo('conv_2');

      expect(minted, <String>['conv_1', 'conv_2']);
      expect(sockets.first.disposed, isTrue,
          reason: 'reusing the socket delivers the old conversation events');
      expect(sockets.length, 2);
      expect(_handshakeAuth(opened.last)['token'], 'rt_conv_2_2');
      await transport.dispose();
    });

    test('emits visitor typing on the channels the gateway listens on',
        () async {
      final transport = build();
      await transport.connectTo('conv_1');
      transport.typingStart('conv_1');
      transport.typingStop('conv_1');
      expect(
        sockets.single.emissions.map((e) => e[0]).toList(),
        <String>['typing.start', 'typing.stop'],
      );
      await transport.dispose();
    });
  });

  group('uploadAttachment', () {
    final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d]);
    const presigned = <String, Object?>{
      'uploadId': 'up_123',
      'url': 'https://s3.test/bucket/workspaces/w_1/up_123.png?sig=abc',
      'method': 'PUT',
      'headers': <String, String>{
        'content-type': 'image/png',
        'x-amz-acl': 'private',
      },
      'publicUrl': 'https://cdn.test/workspaces/w_1/up_123.png',
      'expiresAt': '2026-10-12T23:00:00.000Z',
    };

    late List<http.Request> requests;

    ChatlyRestClient build({
      http.Response Function(http.Request)? presignResponse,
      int storageStatus = 200,
    }) {
      requests = <http.Request>[];
      final mock = MockClient((http.Request req) async {
        requests.add(req);
        if (req.url.path == '/v1/widget/uploads/presign') {
          return presignResponse?.call(req) ??
              http.Response(jsonEncode(presigned), 200,
                  headers: {'content-type': 'application/json'});
        }
        if (req.url.host == 's3.test') {
          return http.Response('', storageStatus);
        }
        return http.Response('{}', 404);
      });
      return ChatlyRestClient(
        config: _config,
        visitorToken: () => _sessionToken,
        httpClient: mock,
      );
    }

    Map<String, Object?> presignBody() {
      final req = requests
          .firstWhere((r) => r.url.path == '/v1/widget/uploads/presign');
      return jsonDecode(req.body) as Map<String, Object?>;
    }

    test('presigns with contentType and sizeBytes', () async {
      final client = build();
      await client.uploadAttachment(
        bytes: bytes,
        filename: 'shot.png',
        mimeType: 'image/png',
      );
      final body = presignBody();
      expect(body['contentType'], 'image/png');
      expect(body['sizeBytes'], bytes.lengthInBytes);
    });

    test('never sends mimeType or bytes to the presign route', () async {
      final client = build();
      await client.uploadAttachment(
        bytes: bytes,
        filename: 'shot.png',
        mimeType: 'image/png',
      );
      final body = presignBody();
      expect(body.containsKey('mimeType'), isFalse);
      expect(body.containsKey('data'), isFalse);
      expect(
        body.keys.toList()..sort(),
        <String>[
          'contentType',
          'filename',
          'publicId',
          'sizeBytes',
          'visitorToken',
        ],
      );
    });

    test('PUTs the raw bytes with every returned header', () async {
      final client = build();
      await client.uploadAttachment(
        bytes: bytes,
        filename: 'shot.png',
        mimeType: 'image/png',
      );
      final put = requests.firstWhere((r) => r.url.host == 's3.test');
      expect(put.method, 'PUT');
      expect(put.bodyBytes, bytes);
      expect(put.headers['x-amz-acl'], 'private');
      expect(put.headers['content-type'], 'image/png');
    });

    test('answers the attachment a message carries', () async {
      final client = build();
      final attachment = await client.uploadAttachment(
        bytes: bytes,
        filename: 'shot.png',
        mimeType: 'image/png',
      );
      expect(attachment.id, 'up_123');
      expect(attachment.filename, 'shot.png');
      // contentType on the way in, mimeType on the way out. Same string.
      expect(attachment.mimeType, 'image/png');
      expect(attachment.sizeBytes, bytes.lengthInBytes);
      expect(attachment.url, 'https://cdn.test/workspaces/w_1/up_123.png');
    });

    test('fails loudly when object storage refuses the bytes', () async {
      final client = build(storageStatus: 403);
      await expectLater(
        client.uploadAttachment(
          bytes: bytes,
          filename: 'shot.png',
          mimeType: 'image/png',
        ),
        throwsA(isA<ChatlyUploadException>()),
      );
    });

    test('names the real reason when storage is not configured', () async {
      final client = build(
        presignResponse: (_) => http.Response(
          jsonEncode(<String, Object?>{...presigned, 'url': 'data:,dev'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        client.uploadAttachment(
          bytes: bytes,
          filename: 'shot.png',
          mimeType: 'image/png',
        ),
        throwsA(
          isA<ChatlyUploadException>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
      expect(requests.where((r) => r.url.host == 's3.test'), isEmpty);
    });

    /// Three refusals, each with copy written for the VISITOR to read.
    /// Collapsing them into "Upload failed. Try again." throws away the only
    /// part of the answer that tells them what to do about it.
    for (final message in <String>[
      'File uploads are turned off for this chat',
      'That file type is not accepted: application/x-msdownload',
      'Files must be under 10 MB',
    ]) {
      test('surfaces verbatim: "$message"', () async {
        final client = build(
          presignResponse: (_) => http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'validation_failed',
                'message': message,
              },
            }),
            400,
            headers: {'content-type': 'application/json'},
          ),
        );
        final err = await client
            .uploadAttachment(
              bytes: bytes,
              filename: 'shot.png',
              mimeType: 'image/png',
            )
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(err, isA<ChatlyRestException>());
        // EQUALITY, not `contains`: the old client stringified the whole
        // response body into its exception, so the copy was technically in
        // there — buried in a developer string no visitor should be shown.
        expect((err as ChatlyRestException).visitorMessage, message);
      });
    }
  });

  group('mintRealtimeToken', () {
    test('posts the conversation it is scoped to', () async {
      final requests = <http.Request>[];
      final mock = MockClient((http.Request req) async {
        requests.add(req);
        return http.Response(
          jsonEncode(<String, Object?>{
            'token': 'rt_abc',
            'expiresAt': '2026-10-12T23:00:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ChatlyRestClient(
        config: _config,
        visitorToken: () => _sessionToken,
        httpClient: mock,
      );
      final token = await client.mintRealtimeToken('conv_7');
      expect(token.token, 'rt_abc');
      expect(requests.single.url.path, '/v1/widget/realtime/token');
      expect(
        jsonDecode(requests.single.body) as Map<String, Object?>,
        <String, Object?>{
          'publicId': 'pub_test',
          'visitorToken': _sessionToken,
          'conversationId': 'conv_7',
        },
      );
    });
  });
}
