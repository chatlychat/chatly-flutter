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

  /// The API's `error.code`, or null when the body is not one of ours.
  String? get code => _errorField('code');

  /// The API's `error.message` — copy written for the VISITOR to read.
  ///
  /// The upload route refuses on three conditions and each one's message is
  /// meant to be shown as-is: "File uploads are turned off for this chat",
  /// "That file type is not accepted: …", "Files must be under 10 MB". Render
  /// this when it is non-null and keep [toString] for the log.
  ///
  /// The API NESTS every error — `app-exception.filter.ts` ends with
  /// `send({ error: body })` — so the un-nested read is only a fallback for a
  /// proxy answering in its own shape.
  String? get visitorMessage => _errorField('message');

  String? _errorField(String key) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final nested = decoded['error'];
      final value = nested is Map ? nested[key] : decoded[key];
      return value is String && value.isNotEmpty ? value : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'ChatlyRestException($status on $path): $body';
}

/// Thrown when an upload fails somewhere other than the API — the object
/// storage PUT itself, or a deployment with no object storage configured.
///
/// A refusal from the presign route is a [ChatlyRestException] and carries the
/// server's own [ChatlyRestException.visitorMessage]; this is for the half of
/// the flow that does not go through our API at all.
class ChatlyUploadException implements Exception {
  /// Creates a [ChatlyUploadException].
  ChatlyUploadException(this.message, {this.status});

  /// Human-readable reason.
  final String message;

  /// Status returned by object storage, when there was one.
  final int? status;

  @override
  String toString() => 'ChatlyUploadException($message)';
}

/// A minted visitor realtime token: HS256, one conversation, 1h TTL.
class ChatlyRealtimeToken {
  /// Creates a [ChatlyRealtimeToken].
  const ChatlyRealtimeToken({required this.token, required this.expiresAt});

  /// The token to put in the Socket.IO handshake as `auth.token`.
  final String token;

  /// When the gateway stops accepting it.
  final DateTime expiresAt;
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

  /// `POST /v1/widget/realtime/token` — mints the credential the Socket.IO
  /// gateway accepts from a visitor.
  ///
  /// HS256, scoped to ONE conversation, 1h TTL. The long-lived
  /// `session.token` from `init` is not accepted there: an unlabelled
  /// handshake is verified as an agent token (RS256, platform public key) and
  /// refused with a bare `Unauthorized`.
  ///
  /// 404s when the conversation is not this visitor's own — the mint checks
  /// `conv.contactId == session.contactId` server-side.
  Future<ChatlyRealtimeToken> mintRealtimeToken(String conversationId) async {
    final json = await _post('/v1/widget/realtime/token', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'conversationId': conversationId,
    });
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('realtime/token: missing token');
    }
    final expiresAt = json['expiresAt'];
    return ChatlyRealtimeToken(
      token: token,
      expiresAt: expiresAt is String
          ? (DateTime.tryParse(expiresAt) ??
              DateTime.now().toUtc().add(const Duration(hours: 1)))
          : DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  /// Uploads a file and answers the [ChatlyAttachment] a message carries.
  ///
  /// THREE steps, and the first one is what this got wrong for its whole life.
  /// It posted `{ filename, mimeType, data }` — a base64 blob — to the presign
  /// route, whose schema is
  /// `{ visitorToken, publicId, filename, contentType, sizeBytes }` and which
  /// takes no bytes at all. zod dropped `mimeType` and `data` as unknown keys
  /// and answered 400 on the missing `contentType`, so no attachment ever
  /// uploaded from this SDK.
  ///
  /// 1. presign — the API mints the key under `workspaces/<id>/…`, so a
  ///    visitor cannot choose where their file lands;
  /// 2. the bytes go STRAIGHT to object storage with the returned method and
  ///    every returned header. Not multipart, not base64. Proxying a 10 MiB
  ///    file through Node to write it to S3 anyway is latency and memory for
  ///    nothing;
  /// 3. the attachment record, which renames `contentType` to `mimeType` —
  ///    the same string under the two names its two schemas use.
  ///
  /// Throws [ChatlyRestException] when the route refuses (attachments off for
  /// the channel, a MIME type outside the allow-list, a file over the
  /// channel's cap); its `visitorMessage` is copy written for the visitor.
  /// Throws [ChatlyUploadException] when object storage refuses the bytes. Do
  /// not pre-check the size: the cap is per channel and the server owns it.
  Future<ChatlyAttachment> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final sizeBytes = bytes.lengthInBytes;
    final presigned = await _post('/v1/widget/uploads/presign', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      'filename': filename,
      // `contentType` on the way in, `mimeType` on the way out. Same string.
      'contentType': mimeType,
      'sizeBytes': sizeBytes,
    });

    final url = presigned['url'];
    final uploadId = presigned['uploadId'];
    final publicUrl = presigned['publicUrl'];
    if (url is! String || uploadId is! String || publicUrl is! String) {
      throw const FormatException('uploads/presign: malformed response');
    }
    // Dev fallback: no object storage configured. The API answers with a
    // `data:` sentinel rather than a real URL, and PUTting to it would throw a
    // confusing transport error. Same guard as the web widget's `uploadOne`.
    if (url.startsWith('data:')) {
      throw ChatlyUploadException(
        'File uploads are not configured on this deployment',
      );
    }

    final method = (presigned['method'] as String?) ?? 'PUT';
    final rawHeaders = presigned['headers'];
    final headers = <String, String>{
      if (rawHeaders is Map)
        for (final entry in rawHeaders.entries)
          '${entry.key}': '${entry.value}',
    };

    final request = http.Request(method, Uri.parse(url))
      ..bodyBytes = bytes
      ..headers.addAll(headers);
    final streamed = await _http.send(request).timeout(config.requestTimeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ChatlyUploadException(
        'Upload failed (${res.statusCode})',
        status: res.statusCode,
      );
    }

    return ChatlyAttachment(
      id: uploadId,
      url: publicUrl,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
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

  /// `POST /v1/widget/conversations/{id}/read` — persist how far the visitor
  /// has read.
  ///
  /// The DURABLE half of a read receipt, and none of the four mobile SDKs had
  /// it: only the web widget ever called this route. All four render the
  /// unread badge from the server's own `unreadContactCount`, so without this
  /// the count could only go UP — it survived app restarts, and the agent
  /// inbox never learned a native visitor had seen the thread.
  ///
  /// Distinct from `ChatlySocketTransport.markRead`, which emits the live
  /// "Read ✓" tick. That one is advisory and goes with the connection; this
  /// is the row. It is also what `Chatly.markAllRead()` was missing — that
  /// method only ever mutated a local counter while its docstring claimed
  /// "server-side read state is handled by the chat UI", pointing at a caller
  /// that did not exist.
  ///
  /// `upToMessageId` is optional server-side: omitting it means "read as of
  /// now", which is what an app not tracking per-message visibility sends.
  Future<void> markConversationRead({
    required String conversationId,
    String? upToMessageId,
  }) async {
    await _post('/v1/widget/conversations/$conversationId/read', {
      'publicId': config.publicId,
      'visitorToken': visitorToken() ?? '',
      if (upToMessageId != null) 'upToMessageId': upToMessageId,
    });
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
