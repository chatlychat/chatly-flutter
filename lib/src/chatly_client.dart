import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chatly_config.dart';
import 'chatly_identity.dart';
import 'models/conversation.dart';
import 'models/init_response.dart';
import 'models/kb_article.dart';
import 'models/kb_result.dart';
import 'models/message.dart';
import 'push/push_registrar.dart';
import 'realtime/envelope.dart';
import 'realtime/event_types.dart';
import 'storage/token_store.dart';
import 'transport/rest_client.dart';
import 'transport/socket_transport.dart';
import 'ui/chatly_chat_page.dart';

/// Public entry point for the Chatly Flutter SDK.
///
/// The SDK is a singleton — access it via [Chatly.instance]. Lifecycle:
///
/// 1. Call [configure] once during app startup.
/// 2. Optionally call [identify] when a known user is signed in.
/// 3. Optionally call [setPushToken] when your FCM/APNs handler fires.
/// 4. Either embed [ChatlyWidget] or call [show] to present the chat UI.
class Chatly {
  Chatly._();

  /// The single, app-wide [Chatly] instance.
  static final Chatly instance = Chatly._();

  ChatlyConfig? _config;
  ChatlyTokenStore? _tokenStore;
  ChatlyRestClient? _rest;
  ChatlySocketTransport? _socket;
  ChatlyPushRegistrar? _push;

  String? _visitorToken;
  InitResponse? _session;
  ChatlyIdentity? _identity;

  final _unreadCount = StreamController<int>.broadcast();
  final _messages = StreamController<ChatlyMessage>.broadcast();
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _conversations =
      StreamController<List<ChatlyConversation>>.broadcast();

  int _lastUnread = 0;

  /// Stream of unread message counts. Emits a fresh count every time the
  /// SDK observes a new agent / bot message.
  Stream<int> get unreadCount => _unreadCount.stream;

  /// Stream of every realtime [ChatlyMessage] observed by the SDK
  /// (regardless of conversation).
  Stream<ChatlyMessage> get messages => _messages.stream;

  /// Stream of raw realtime [RealtimeEnvelope]s — useful for advanced
  /// integrations that need access to non-message events (presence, typing,
  /// triggers, etc.).
  Stream<RealtimeEnvelope> get events => _events.stream;

  /// Stream of conversation summary lists. Refreshed whenever
  /// [listConversations] is called.
  Stream<List<ChatlyConversation>> get conversations => _conversations.stream;

  /// The active [ChatlyConfig], or `null` before [configure] runs.
  ChatlyConfig? get config => _config;

  /// The most recent [InitResponse]. Null until [configure] completes.
  InitResponse? get session => _session;

  /// Whether the SDK has successfully run `init` at least once.
  bool get isConfigured => _session != null;

  /// Configures the SDK. Idempotent — calling again replaces the active
  /// session.
  Future<InitResponse> configure(ChatlyConfig config) async {
    await _teardown();
    _config = config;
    _tokenStore = ChatlyTokenStore(publicId: config.publicId);
    _visitorToken = await _tokenStore!.read();

    _rest = ChatlyRestClient(
      config: config,
      visitorToken: () => _visitorToken,
    );
    _push = ChatlyPushRegistrar(_rest!);

    final init = await _rest!.init(identity: _identity);
    _session = init;
    if (init.session.token.isNotEmpty) {
      _visitorToken = init.session.token;
      await _tokenStore!.write(init.session.token);
    }

    if (config.autoConnectRealtime) {
      _attachSocket(init);
    }
    return init;
  }

  /// Attaches a known-user identity. Triggers a fresh `init` so the backend
  /// can re-resolve the visitor.
  Future<void> identify(ChatlyIdentity identity) async {
    _identity = identity;
    if (_rest == null) return;
    final init = await _rest!.init(identity: identity);
    _session = init;
    if (init.session.token.isNotEmpty &&
        init.session.token != _visitorToken) {
      _visitorToken = init.session.token;
      await _tokenStore?.write(init.session.token);
      if (_config?.autoConnectRealtime ?? true) {
        await _socket?.dispose();
        _socket = null;
        _attachSocket(init);
      }
    }
  }

  /// Forgets the current identity, clears the persisted token, disconnects
  /// the socket, and runs a fresh anonymous `init`.
  Future<void> logout() async {
    _identity = null;
    await _tokenStore?.clear();
    _visitorToken = null;
    await _socket?.dispose();
    _socket = null;
    if (_rest != null) {
      final init = await _rest!.init();
      _session = init;
      if (init.session.token.isNotEmpty) {
        _visitorToken = init.session.token;
        await _tokenStore?.write(init.session.token);
      }
      if (_config?.autoConnectRealtime ?? true) {
        _attachSocket(init);
      }
    }
  }

  /// Registers a device push token (FCM or APNs).
  Future<void> setPushToken(String token, {String? platformOverride}) async {
    _ensureReady();
    await _push!.register(token, platformOverride: platformOverride);
  }

  /// Starts a new conversation with [body] as the first message. Optional
  /// [attachments] are sent inline — each entry must be the result of a prior
  /// [uploadAttachment] call.
  Future<StartConversationResult> startConversation(
    String body, {
    List<ChatlyAttachment>? attachments,
  }) async {
    _ensureReady();
    return _rest!.startConversation(body, attachments: attachments);
  }

  /// Sends [body] as a reply on [conversationId]. Optional [attachments] are
  /// included inline on the message.
  Future<void> sendMessage({
    required String conversationId,
    required String body,
    List<ChatlyAttachment>? attachments,
  }) async {
    _ensureReady();
    await _rest!.sendMessage(
      conversationId: conversationId,
      body: body,
      attachments: attachments,
    );
  }

  /// Uploads a file/image to the public widget upload endpoint and returns
  /// the persisted [ChatlyAttachment]. The returned object can be passed to
  /// [startConversation] or [sendMessage] (via their `attachments` parameter)
  /// to attach it to a message.
  Future<ChatlyAttachment> uploadAttachment(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    _ensureReady();
    return _rest!.uploadAttachment(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  /// Fetches the visitor's conversation list. Also emits on
  /// [conversations] for subscribers.
  Future<List<ChatlyConversation>> listConversations({int limit = 20}) async {
    _ensureReady();
    final list = await _rest!.listConversations(limit: limit);
    _conversations.add(list);
    return list;
  }

  /// Fetches the message history for [conversationId].
  Future<List<ChatlyMessage>> listMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    _ensureReady();
    return _rest!.listMessages(
      conversationId: conversationId,
      limit: limit,
    );
  }

  /// Searches the workspace's knowledge base.
  Future<List<ChatlyKbResult>> searchKb({
    required String query,
    int limit = 8,
  }) async {
    _ensureReady();
    return _rest!.searchKb(query: query, limit: limit);
  }

  /// Fetches a full knowledge-base article by slug.
  Future<ChatlyKbArticle> getKbArticle(String slug) async {
    _ensureReady();
    return _rest!.getKbArticle(slug);
  }

  /// Emits a typing-start signal on [conversationId].
  void typingStart(String conversationId) =>
      _socket?.typingStart(conversationId);

  /// Emits a typing-stop signal on [conversationId].
  void typingStop(String conversationId) =>
      _socket?.typingStop(conversationId);

  /// Pushes the bundled full-page chat UI onto the navigator stack.
  Future<void> show(BuildContext context) async {
    if (!isConfigured) {
      throw StateError('Chatly: call configure() before show().');
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChatlyChatPage(),
      ),
    );
  }

  /// Marks all unread messages as read locally. Mainly drives the
  /// [unreadCount] stream — server-side read state is handled by the chat UI.
  void markAllRead() {
    if (_lastUnread != 0) {
      _lastUnread = 0;
      _unreadCount.add(0);
    }
  }

  void _attachSocket(InitResponse init) {
    final config = _config!;
    final socket = ChatlySocketTransport(
      config: config,
      token: init.session.token,
      workspaceId: init.session.workspaceId,
      contactId: init.session.contactId,
    );
    socket.envelopes.listen(_onEnvelope);
    socket.connect();
    socket.subscribe(<String>[
      'workspace:${init.session.workspaceId}',
      'contact:${init.session.contactId}',
    ]);
    _socket = socket;
  }

  void _onEnvelope(RealtimeEnvelope envelope) {
    _events.add(envelope);
    if (envelope.type == RealtimeEventType.messageCreated) {
      final msg = ChatlyMessage.fromRealtime(envelope.payload);
      _messages.add(msg);
      if (msg.author != ChatlyMessageAuthor.contact) {
        _lastUnread += 1;
        _unreadCount.add(_lastUnread);
      }
    }
  }

  void _ensureReady() {
    if (_rest == null || _session == null) {
      throw StateError('Chatly: configure() must be called first.');
    }
  }

  Future<void> _teardown() async {
    await _socket?.dispose();
    _socket = null;
    _rest?.dispose();
    _rest = null;
    _push = null;
    _session = null;
  }

  /// Releases all resources held by the singleton. Used in tests.
  Future<void> dispose() async {
    await _teardown();
    await _unreadCount.close();
    await _messages.close();
    await _events.close();
    await _conversations.close();
  }
}
