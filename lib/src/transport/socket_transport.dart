import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../chatly_config.dart';
import '../realtime/envelope.dart';
import 'rest_client.dart';

/// Mints a conversation-scoped realtime token — `ChatlyRestClient.mintRealtimeToken`.
typedef ChatlyRealtimeTokenMinter = Future<ChatlyRealtimeToken> Function(
  String conversationId,
);

/// A socket.io connection, narrowed to what this transport uses.
///
/// The seam exists so the handshake can be asserted in a unit test without a
/// gateway: the defect it was written for was invisible to every
/// response-shaped test, because the socket was refused before any response
/// existed.
abstract class ChatlySocketHandle {
  /// Whether the socket is open.
  bool get connected;

  /// Registers a handler for a socket.io event.
  void on(String event, void Function(Object? data) handler);

  /// Emits an event with an optional payload.
  void emit(String event, [Object? data]);

  /// Opens the connection.
  void connect();

  /// Closes it and releases its listeners.
  void dispose();
}

/// Opens a socket for [url] with [options]. Replaced in tests.
typedef ChatlySocketOpener = ChatlySocketHandle Function(
  String url,
  Map<String, dynamic> options,
);

class _IoSocketHandle implements ChatlySocketHandle {
  _IoSocketHandle(this._socket);

  final io.Socket _socket;

  @override
  bool get connected => _socket.connected;

  @override
  void on(String event, void Function(Object? data) handler) =>
      _socket.on(event, handler);

  @override
  void emit(String event, [Object? data]) => _socket.emit(event, data);

  @override
  void connect() => _socket.connect();

  @override
  void dispose() => _socket.dispose();
}

/// The real opener.
ChatlySocketHandle defaultSocketOpener(
  String url,
  Map<String, dynamic> options,
) =>
    _IoSocketHandle(io.io(url, options));

/// Socket.IO transport for a VISITOR socket.
///
/// ── The credential, and why there are two of them ─────────────────────────
///
/// A visitor holds two tokens and they are not interchangeable:
///
///  * `session.token` from `POST /v1/widget/init` — long-lived, identifies the
///    visitor, carried in the BODY of every REST call. **The gateway does not
///    accept it.**
///  * a realtime token from `POST /v1/widget/realtime/token` — HS256, scoped
///    to ONE conversation, 1h TTL. This is what the socket wants.
///
/// This transport used to hand the gateway `{ publicId, visitorToken }`.
/// `handshakeAuthSchema` (`apps/realtime/src/gateway.ts:54-59`) is
/// `{ token, kind? }` and `kind` **defaults to agent**, so the gateway
/// verified a visitor's HS256 token as RS256 against the platform public key,
/// failed, and answered a bare `Unauthorized` naming neither credential —
/// which is why "realtime does not work on mobile" had no diagnosis for so
/// long. Every field of that handshake was wrong: the key names, the
/// credential, and the missing `kind`.
///
/// ── Scope ──────────────────────────────────────────────────────────────────
///
/// The token names one conversation, and the gateway joins the socket to
/// `v:<workspace>:<conversation>` from the token's own claim. It registers no
/// `subscribe` listener for a visitor at all — the old `subscribe()` here
/// emitted an envelope on the `event` channel, which nothing on the server
/// has ever read — so a conversation switch is a re-mint and a reconnect, not
/// a second subscribe. [connectTo] does both.
class ChatlySocketTransport {
  /// Creates a transport. [mintToken] is called once per connection ATTEMPT
  /// path — on connect, and again before a reconnect.
  ChatlySocketTransport({
    required this.config,
    required this.mintToken,
    required this.workspaceId,
    required this.contactId,
    ChatlySocketOpener? opener,
  }) : _opener = opener ?? defaultSocketOpener;

  /// Active SDK config.
  final ChatlyConfig config;

  /// Mints the conversation-scoped realtime token.
  final ChatlyRealtimeTokenMinter mintToken;

  /// Workspace id, for callers that need it alongside the stream.
  final String workspaceId;

  /// Contact id, for callers that need it alongside the stream.
  final String contactId;

  final ChatlySocketOpener _opener;

  ChatlySocketHandle? _socket;
  final _envelopes = StreamController<RealtimeEnvelope>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  String? _currentToken;
  String? _conversationId;

  /// Bumped by every [connectTo] and every [close].
  ///
  /// A mint is a round trip. Without this, one that lands after the caller
  /// switched conversations (or closed the chat) would open a socket for a
  /// thread nobody is looking at.
  int _generation = 0;

  /// Stream of decoded inbound envelopes.
  Stream<RealtimeEnvelope> get envelopes => _envelopes.stream;

  /// Stream of connection state changes (`true` = connected).
  Stream<bool> get connected => _connected.stream;

  /// The conversation this socket is scoped to, or null when closed.
  String? get conversationId => _conversationId;

  /// Mints a token for [conversationId] and opens the socket with it.
  ///
  /// Closing the previous socket happens FIRST and synchronously: an await
  /// before it would leave two sockets alive across a switch, and the old one
  /// would keep delivering the old conversation's events.
  ///
  /// Throws whatever the mint throws — a [ChatlyRestException] 404 for a
  /// conversation that is not this visitor's own, or a 403 on a channel with
  /// an origin allow-list (a native app sends no `Origin`, so it passes only
  /// where no list is configured). Treat it as "live delivery is unavailable,
  /// keep polling", not as a dead thread.
  Future<void> connectTo(String conversationId) async {
    _close();
    final generation = ++_generation;
    _conversationId = conversationId;

    final minted = await mintToken(conversationId);
    if (generation != _generation) {
      // Stood down while the mint was in flight — switched, or disposed.
      return;
    }
    _currentToken = minted.token;

    final socket = _opener(
      config.realtimeBaseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .setPath('/socket.io')
          .disableAutoConnect()
          /*
           * `setAuthFn`, not `setAuth`. socket_io_client calls this on every
           * engine `open` — including every reconnect (`Socket.onopen` →
           * `auth(cb)`), which is the whole reason it exists. A static map is
           * captured once and replayed verbatim, so a visitor whose socket
           * dropped after the token's 1h lifetime reconnects with an expired
           * credential and is refused silently for the rest of the session.
           *
           * This is why no hand-rolled reconnect loop is needed here: the
           * Dart client has the same per-attempt hook the browser one does.
           */
          .setAuthFn((void Function(Map<dynamic, dynamic> auth) callback) {
            callback(<String, String>{
              'token': _currentToken ?? minted.token,
              'kind': 'visitor',
            });
          })
          .setReconnectionAttempts(0x7fffffff)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    socket.on('connect', (_) => _connected.add(true));
    socket.on('disconnect', (_) {
      _connected.add(false);
      // Re-mint on the way down so the token is already fresh by the time
      // the backoff gets to the next attempt. The auth hook above makes a
      // refreshed token reachable; this is what makes it exist.
      unawaited(_refreshToken(generation));
    });
    socket.on('connect_error', (_) => unawaited(_refreshToken(generation)));
    socket.on('event', _handleRaw);
    socket.connect();
    _socket = socket;
  }

  Future<void> _refreshToken(int generation) async {
    if (generation != _generation) return;
    final conversationId = _conversationId;
    if (conversationId == null) return;
    try {
      final minted = await mintToken(conversationId);
      if (generation != _generation) return;
      _currentToken = minted.token;
    } on Object {
      // Keep the token we hold: socket.io retries on its own backoff either
      // way, and a stale token has a chance where none has none. A failed
      // mint is usually the same outage as the dropped socket.
    }
  }

  void _handleRaw(Object? raw) {
    if (raw is! Map) return;
    try {
      _envelopes.add(RealtimeEnvelope.fromJson(Map<String, Object?>.from(raw)));
    } on FormatException {
      // Forward-compat: drop malformed frames silently rather than killing
      // the stream.
    }
  }

  /// Emits a typing-start signal for the connected conversation.
  ///
  /// `typing.start` is its own socket.io channel and the gateway reads
  /// NOTHING from the payload — every field that matters for trust comes from
  /// the token, so a client cannot claim another conversation, another contact
  /// or agent authorship. These used to be emitted as v1 envelopes on the
  /// `event` channel, where no listener exists.
  void typingStart(String conversationId) => _emit('typing.start');

  /// Emits a typing-stop signal for the connected conversation.
  void typingStop(String conversationId) => _emit('typing.stop');

  /// Tells the agent side the visitor has read up to [upToMessageId].
  ///
  /// The one other thing a visitor socket may publish. The gateway refuses a
  /// payload whose ids do not match the token's, so this asserts a fact about
  /// this visitor in this conversation only.
  ///
  /// The anchor key is `upToMessageId`. It was `messageId`, which is not a
  /// field `messageReadPayloadSchema` declares — and because the other four
  /// fields here were already correct, the parse SUCCEEDED with the anchor
  /// silently stripped: a published read envelope with no position. The
  /// server treats `upToMessageId` as optional precisely so a client may say
  /// "I opened this as of now" without one, which is what made the wrong name
  /// invisible rather than a refusal.
  ///
  /// Nullable for that same reason, and omitted rather than sent as null when
  /// absent. `sdk-kotlin` had the identical defect and `apps/widget` pins the
  /// omit-rather-than-null behaviour in its own spec.
  void markRead([String? upToMessageId]) {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    _emit('message.read', <String, Object?>{
      'conversationId': conversationId,
      if (upToMessageId != null) 'upToMessageId': upToMessageId,
      'readerType': 'contact',
      'readerId': contactId,
      'readAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _emit(String event, [Object? payload]) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit(event, payload);
  }

  void _close() {
    _generation += 1;
    _currentToken = null;
    _conversationId = null;
    _socket?.dispose();
    _socket = null;
  }

  /// Closes the socket, keeping the streams open for a later [connectTo].
  void close() => _close();

  /// Tears the socket down and closes all streams.
  Future<void> dispose() async {
    _close();
    await _envelopes.close();
    await _connected.close();
  }
}
