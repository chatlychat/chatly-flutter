/// Author of a message.
enum ChatlyMessageAuthor {
  /// The end-user / visitor.
  contact,

  /// A human agent.
  agent,

  /// An AI agent or bot.
  bot,

  /// The platform itself (system event).
  system;

  /// Parses a wire-format author string. Falls back to [contact] for unknowns.
  static ChatlyMessageAuthor parse(String? raw) {
    switch (raw) {
      case 'agent':
        return ChatlyMessageAuthor.agent;
      case 'bot':
        return ChatlyMessageAuthor.bot;
      case 'system':
        return ChatlyMessageAuthor.system;
      case 'contact':
      default:
        return ChatlyMessageAuthor.contact;
    }
  }

  /// Wire format of this author kind.
  String get wireName => name;
}

/// Kind / shape of a message body.
enum ChatlyMessageKind {
  /// Plain text.
  text,

  /// Image attachment.
  image,

  /// File attachment.
  file,

  /// Attachment(s) with no body text.
  attachmentOnly,

  /// In-stream event (joined, assigned, etc.).
  event,

  /// Internal note (only visible to agents).
  internalNote;

  /// Parses a wire-format kind. Falls back to [text] for unknowns.
  static ChatlyMessageKind parse(String? raw) {
    switch (raw) {
      case 'image':
        return ChatlyMessageKind.image;
      case 'file':
        return ChatlyMessageKind.file;
      case 'attachment_only':
        return ChatlyMessageKind.attachmentOnly;
      case 'event':
        return ChatlyMessageKind.event;
      case 'internal_note':
        return ChatlyMessageKind.internalNote;
      case 'text':
      default:
        return ChatlyMessageKind.text;
    }
  }

  /// Wire format of this kind.
  String get wireName {
    switch (this) {
      case ChatlyMessageKind.internalNote:
        return 'internal_note';
      case ChatlyMessageKind.text:
        return 'text';
      case ChatlyMessageKind.image:
        return 'image';
      case ChatlyMessageKind.file:
        return 'file';
      case ChatlyMessageKind.attachmentOnly:
        return 'attachment_only';
      case ChatlyMessageKind.event:
        return 'event';
    }
  }
}

/// One file or image attached to a message.
///
/// Produced by `POST /v1/widget/uploads`. The SDK renders image mime types as
/// inline thumbnails and everything else as a small file row with name and
/// human-readable size.
class ChatlyAttachment {
  /// Creates an [ChatlyAttachment].
  const ChatlyAttachment({
    required this.id,
    required this.url,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
  });

  /// Server-minted id.
  final String id;

  /// Stable URL the SDK can fetch the bytes from.
  final String url;

  /// Original filename, sanitised by the server.
  final String filename;

  /// MIME type as reported on upload.
  final String mimeType;

  /// Size in bytes.
  final int sizeBytes;

  /// Convenience flag — true when [mimeType] starts with `image/`.
  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  /// Parses an attachment from a JSON map (REST or realtime payload).
  factory ChatlyAttachment.fromJson(Map<String, Object?> json) {
    return ChatlyAttachment(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] is num)
          ? (json['sizeBytes'] as num).toInt()
          : 0,
    );
  }

  /// Serialises this attachment to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };
}

/// A single message inside a conversation.
class ChatlyMessage {
  /// Creates a [ChatlyMessage]. Generally constructed via [fromJson].
  const ChatlyMessage({
    required this.id,
    required this.author,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.attachments = const <ChatlyAttachment>[],
    this.conversationId,
  });

  /// Message id.
  final String id;

  /// Author kind.
  final ChatlyMessageAuthor author;

  /// Body kind.
  final ChatlyMessageKind kind;

  /// Body text. For attachments this is the caption (may be empty).
  final String body;

  /// Inline attachments — empty for plain text messages.
  final List<ChatlyAttachment> attachments;

  /// Server timestamp the message was created.
  final DateTime createdAt;

  /// Conversation id, populated when the source includes it (realtime
  /// events) and null otherwise (`/messages/list` responses).
  final String? conversationId;

  /// Parses a message from the REST `/messages/list` envelope.
  factory ChatlyMessage.fromJson(Map<String, Object?> json) {
    final raw = json['attachments'];
    final atts = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((m) => ChatlyAttachment.fromJson(Map<String, Object?>.from(m)))
            .toList(growable: false)
        : const <ChatlyAttachment>[];
    return ChatlyMessage(
      id: json['id'] as String? ?? '',
      author: ChatlyMessageAuthor.parse(json['authorType'] as String?),
      kind: ChatlyMessageKind.parse(json['kind'] as String?),
      body: json['body'] as String? ?? '',
      attachments: atts,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      conversationId: json['conversationId'] as String?,
    );
  }

  /// Parses a message from a realtime `message.created` payload.
  factory ChatlyMessage.fromRealtime(Map<String, Object?> payload) {
    final raw = payload['attachments'];
    final atts = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((m) => ChatlyAttachment.fromJson(Map<String, Object?>.from(m)))
            .toList(growable: false)
        : const <ChatlyAttachment>[];
    return ChatlyMessage(
      id: payload['id'] as String? ?? '',
      author: ChatlyMessageAuthor.parse(payload['authorType'] as String?),
      kind: ChatlyMessageKind.text,
      body: payload['body'] as String? ?? '',
      attachments: atts,
      createdAt: DateTime.tryParse(payload['createdAt'] as String? ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      conversationId: payload['conversationId'] as String?,
    );
  }

  /// Serialises this message to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'authorType': author.wireName,
        'kind': kind.wireName,
        'body': body,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (conversationId != null) 'conversationId': conversationId,
      };

  /// Returns a copy of this message with the given fields overridden.
  ChatlyMessage copyWith({
    String? id,
    ChatlyMessageAuthor? author,
    ChatlyMessageKind? kind,
    String? body,
    List<ChatlyAttachment>? attachments,
    DateTime? createdAt,
    String? conversationId,
  }) {
    return ChatlyMessage(
      id: id ?? this.id,
      author: author ?? this.author,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      conversationId: conversationId ?? this.conversationId,
    );
  }
}
