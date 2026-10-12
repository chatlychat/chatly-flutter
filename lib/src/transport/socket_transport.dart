import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../chatly_config.dart';
import '../realtime/envelope.dart';
import '../realtime/event_types.dart';

/// Socket.IO based realtime transport speaking the v1 envelope protocol.
///
/// Translates raw socket payloads into typed [RealtimeEnvelope]s exposed
/// through the [envelopes] stream, and provides a tiny imperative API for
/// (un)subscribing to channels.
class ChatlySocketTransport {
  /// Creates a transport. [token] is the visitor token returned by
  /// `/v1/widget/init`; [workspaceId] / [contactId] are needed for outbound
  /// envelopes.
  ChatlySocketTransport({
    required this.config,
    required this.token,
    required this.workspaceId,
    required this.contactId,
  });

  /// Active SDK config.
  final ChatlyConfig config;

  /// Visitor session token.
  final String token;

  /// Workspace id stamped on outbound envelopes.
  final String workspaceId;

  /// Contact id used for typing payloads.
  final String contactId;

  io.Socket? _socket;
  final _envelopes = StreamController<RealtimeEnvelope>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  /// Stream of decoded inbound envelopes.
  Stream<RealtimeEnvelope> get envelopes => _envelopes.stream;

  /// Stream of connection state changes (`true` = connected).
  Stream<bool> get connected => _connected.stream;

  /// Opens the underlying socket. Safe to call multiple times — re-uses an
  /// existing socket when present.
  void connect() {
    if (_socket != null) return;
    final socket = io.io(
      config.realtimeBaseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .disableAutoConnect()
          .setAuth(<String, String>{
            'publicId': config.publicId,
            'visitorToken': token,
          })
          .setReconnectionAttempts(0x7fffffff)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    socket.onConnect((_) => _connected.add(true));
    socket.onDisconnect((_) => _connected.add(false));
    socket.on('event', _handleRaw);
    socket.on('envelope', _handleRaw);
    socket.connect();
    _socket = socket;
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

  /// Subscribes to one or more realtime channels. Channels are workspace-
  /// scoped strings like `workspace:{id}` or `conversation:{id}`.
  void subscribe(List<String> channels, {String? lastEventId}) {
    _emit(RealtimeEventType.subscribe, {
      'channels': channels,
      if (lastEventId != null) 'lastEventId': lastEventId,
    });
  }

  /// Emits a typing-start event for [conversationId].
  void typingStart(String conversationId) {
    _emit(RealtimeEventType.typingStart, {
      'conversationId': conversationId,
      'actorType': 'contact',
      'actorId': contactId,
    });
  }

  /// Emits a typing-stop event for [conversationId].
  void typingStop(String conversationId) {
    _emit(RealtimeEventType.typingStop, {
      'conversationId': conversationId,
      'actorType': 'contact',
      'actorId': contactId,
    });
  }

  void _emit(RealtimeEventType type, Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    final envelope = <String, Object?>{
      'v': kRealtimeProtocolVersion,
      'type': type.wireName,
      'id': _generateClientId(),
      'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
      'workspace_id': workspaceId,
      'payload': payload,
    };
    socket.emit('event', envelope);
  }

  /// Tears down the socket and closes all streams.
  Future<void> dispose() async {
    _socket?.dispose();
    _socket = null;
    await _envelopes.close();
    await _connected.close();
  }

  /// Generates a client-local identifier for outbound envelopes. Server
  /// regenerates server-authoritative ids on receipt; this only needs to be
  /// unique within the socket lifetime.
  String _generateClientId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'c$now';
  }
}
