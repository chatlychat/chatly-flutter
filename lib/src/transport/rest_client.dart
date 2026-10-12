import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../chatly_config.dart';
import '../chatly_identity.dart';
import '../models/conversation.dart';
import '../models/init_response.dart';
import '../models/kb_article.dart';
import '../models/kb_result.dart';
import '../models/message.dart';

/// Result envelope for `POST /v1/widget/conversations`.
class StartConversationResult {
  /// Creates a [StartConversationResult].
  const StartConversationResult({
    required this.conversationId,
    required this.message,
  });

  /// Id of the newly created conversation.
  final String conversationId;

  /// The first message that was created alongside the conversation.
  final ChatlyMessage message;
}

/// Exception thrown when the widget REST API returns a non-2xx response.
class ChatlyRestException implements Exception {
  /// Creates a [ChatlyRestException].
  ChatlyRestException(this.status, this.path, this.body);

  /// HTTP status code returned by the server.
  final int status;

  /// API path that was hit (e.g. `/v1/widget/init`).
  final String path;

  /// Response body returned by the server (may be empty).
  final String body;

  @override
  String toString() => 'ChatlyRestException($status on $path): $body';
}

/// Thin HTTP client that mirrors the public `/v1/widget/*` REST surface
/// exactly as exposed in `apps/widget/src/client.ts`.
class ChatlyRestClient {
  /// Creates a [ChatlyRestClient]. Pass an [http.Client] for testing.
  ChatlyRestClient({
    required this.config,
    required this.visitorToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Active SDK config.
  final ChatlyConfig config;

  /// Mutable getter for the current visitor token — the SDK refreshes it
  /// after `init` succeeds.
  final String? Function() visitorToken;

  final http.Client _http;

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();

  /// `POST /v1/widget/init`
  Future<InitResponse> init({
    ChatlyIdentity? identity,
    Map<String, Object?>? page,
  }) async {
    final body = <String, Object?>{
      'publicId': config.publicId,
      if (visitorToken() != null) 'visitorToken': visitorToken(),
      if (config.locale != null) 'locale': config.locale,
      if (config.timezone != null) 'timezone': config.timezone,
      if (page != null) 'page': page,
      if (identity != null) 'identity': identity.toJson(),
    };
    final json = await _post('/v1/widget/init', body);
    return InitResponse.fromJson(json);
  }

  /// `POST /v1/widget/conversations`
  Future<StartConversationResult> startConversation(
    String body, {
    List<ChatlyAttachment>? attachments,
  }) async {
    final json = await _post('/v1/widget/conversations', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'body': body,
      if (attachments != null && attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
    });
    final conv = json['conversation'];
    final msg = json['message'];
    if (conv is! Map || msg is! Map) {
      throw const FormatException('start: malformed response');
    }
    final conversationId = (conv['id'] as String?) ?? '';
    return StartConversationResult(
      conversationId: conversationId,
      message: ChatlyMessage.fromJson(<String, Object?>{
        ...Map<String, Object?>.from(msg),
        'authorType': 'contact',
        'kind': (attachments != null && attachments.isNotEmpty && body.isEmpty)
            ? 'attachment_only'
            : 'text',
        'attachments':
            (attachments ?? const <ChatlyAttachment>[]).map((a) => a.toJson()).toList(),
        'conversationId': conversationId,
      }),
    );
  }

  /// `POST /v1/widget/messages`
  Future<void> sendMessage({
    required String conversationId,
    required String body,
    List<ChatlyAttachment>? attachments,
  }) async {
    await _post('/v1/widget/messages', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'conversationId': conversationId,
      'body': body,
      if (attachments != null && attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
    });
  }

  /// `POST /v1/widget/uploads` — stores raw bytes server-side and returns the
  /// resulting [ChatlyAttachment]. Bytes are sent base64-encoded so the widget
  /// surface stays single-content-type (no multipart parser registered).
  Future<ChatlyAttachment> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final encoded = base64Encode(bytes);
    final json = await _post('/v1/widget/uploads/presign', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'filename': filename,
      'mimeType': mimeType,
      'data': encoded,
    });
    return ChatlyAttachment.fromJson(Map<String, Object?>.from(json));
  }

  /// `POST /v1/widget/conversations/list`
  Future<List<ChatlyConversation>> listConversations({int limit = 20}) async {
    final json = await _post('/v1/widget/conversations/list', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'limit': limit,
    });
    final list = json['conversations'];
    if (list is! List) return const <ChatlyConversation>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => ChatlyConversation.fromJson(Map<String, Object?>.from(m)))
        .toList(growable: false);
  }

  /// `POST /v1/widget/messages/list`
  Future<List<ChatlyMessage>> listMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    final json = await _post('/v1/widget/messages/list', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'conversationId': conversationId,
      'limit': limit,
    });
    final list = json['messages'];
    if (list is! List) return const <ChatlyMessage>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => ChatlyMessage.fromJson(<String, Object?>{
              ...Map<String, Object?>.from(m),
              'conversationId': conversationId,
            }))
        .toList(growable: false);
  }

  /// `POST /v1/widget/kb/search`
  Future<List<ChatlyKbResult>> searchKb({
    required String query,
    int limit = 8,
  }) async {
    final json = await _post('/v1/widget/kb/search', {
      'publicId': config.publicId,
      if (visitorToken() != null) 'visitorToken': visitorToken(),
      'query': query,
      'limit': limit,
    });
    final list = json['results'];
    if (list is! List) return const <ChatlyKbResult>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => ChatlyKbResult.fromJson(Map<String, Object?>.from(m)))
        .toList(growable: false);
  }

  /// `POST /v1/widget/kb/article`
  Future<ChatlyKbArticle> getKbArticle(String slug) async {
    final json = await _post('/v1/widget/kb/article', {
      'publicId': config.publicId,
      if (visitorToken() != null) 'visitorToken': visitorToken(),
      'slug': slug,
    });
    final art = json['article'];
    if (art is! Map) {
      throw const FormatException('kb/article: missing article');
    }
    return ChatlyKbArticle.fromJson(Map<String, Object?>.from(art));
  }

  /// `POST /v1/widget/push/register` — registers a device push token.
  ///
  /// Not part of the documented surface yet, but kept here so the public API
  /// can call it without UI code having to know URLs.
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    await _post('/v1/widget/push/register', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'token': token,
      'platform': platform,
    });
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final uri = Uri.parse('${config.restBaseUrl}$path');
    final res = await _http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
            'idempotency-key': _newIdempotencyKey(),
          },
          body: jsonEncode(body),
        )
        .timeout(config.requestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ChatlyRestException(res.statusCode, path, res.body);
    }
    if (res.body.isEmpty) return const <String, Object?>{};
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw FormatException('Non-object JSON response on $path');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// Generates a short, opaque idempotency token per request attempt. Not a
  /// real UUID generator — collisions don't matter for the widget surface
  /// where the server already de-dupes by (visitor, conversation, body).
  String _newIdempotencyKey() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd =
        (DateTime.now().millisecond * 7919 + now.hashCode).abs().toRadixString(36);
    return 'flutter-$now-$rnd';
  }
}
