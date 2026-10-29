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
///
/// This union was wrong in BOTH directions until 2026-10-20. It listed
/// `image`, `file`, `event` and `internalNote` — four values that are not
/// members of the server's `message_kind` enum
/// (`text | rich | note | system_event | attachment_only`) and that nothing
/// can therefore ever send, so `ChatlyMessagesList`'s system-bubble branch
/// compared against `event` and was always false — while `rich` was absent
/// altogether.
///
/// `rich` is the one that cost something: it is the kind every formatted
/// reply and every bot card carries, and [parse] falls back to [text], so an
/// app branching on `kind` could not tell a product grid from a sentence.
///
/// `note` is deliberately not here, and that narrowing is the correct one —
/// an agent's internal comment never reaches a visitor. The realtime gateway
/// forwards `text`, `rich`, `attachment_only` and `system_event`
/// (`VISITOR_VISIBLE_MESSAGE_KINDS`); the history route additionally filters
/// `system_event` out in SQL, so that one arrives live and is absent after a
/// reload.
enum ChatlyMessageKind {
  /// Plain text.
  text,

  /// A formatted body, or one carrying rich blocks — a card, a product grid,
  /// a fulfilment timeline. Read [ChatlyMessage.blocks] with
  /// `readChatlyBlocks` when it is present, which is what the bundled
  /// [ChatlyMessagesList] does.
  rich,

  /// Attachment(s) with no body text.
  attachmentOnly,

  /// The platform's own audit turn ("assigned to …"). Arrives on the
  /// socket; the history route does not serve it.
  systemEvent;

  /// Parses a wire-format kind. Falls back to [text] for unknowns.
  static ChatlyMessageKind parse(String? raw) {
    switch (raw) {
      case 'rich':
        return ChatlyMessageKind.rich;
      case 'attachment_only':
        return ChatlyMessageKind.attachmentOnly;
      case 'system_event':
        return ChatlyMessageKind.systemEvent;
      case 'text':
      default:
        return ChatlyMessageKind.text;
    }
  }

  /// Wire format of this kind.
  String get wireName {
    switch (this) {
      case ChatlyMessageKind.text:
        return 'text';
      case ChatlyMessageKind.rich:
        return 'rich';
      case ChatlyMessageKind.attachmentOnly:
        return 'attachment_only';
      case ChatlyMessageKind.systemEvent:
        return 'system_event';
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
    this.blocks,
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

  /// The rich-block envelope, exactly as the server sent it.
  ///
  /// Deliberately untyped. `messages.blocks` is a jsonb column written by
  /// whoever holds an API key and read by apps older than the server they are
  /// talking to, so a strict decode here would throw on a block type this
  /// release has never heard of and lose the whole message. Pass it to
  /// `readChatlyBlocks`, which drops what it cannot draw and keeps the rest;
  /// that is also what [ChatlyMessagesList] does.
  ///
  /// Present on [ChatlyMessageKind.rich] messages — every bot card, product
  /// grid and fulfilment timeline — and null on everything else.
  ///
  /// The RENDERED subset is the twelve block types the React Native SDK
  /// renders: `text`, `media`, `fields`, `card`, `card_grid`, `actions`,
  /// `quick_replies`, `order_status`, `table`, `place`, `status` and
  /// `divider`. The two spatial fields (`card.model`, `card_grid.placement`)
  /// are read by neither this SDK nor any other phone surface — they exist
  /// for a host embedding a 3D world — so they are dropped, and this value
  /// is the place to find them if you are that host.
  final Object? blocks;

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
      blocks: json['blocks'],
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
      // The payload carries `kind` and this used to hard-code `text`, so
      // every card arrived live looking like a sentence and only became a
      // card after a reload re-fetched it over REST.
      kind: ChatlyMessageKind.parse(payload['kind'] as String?),
      body: payload['body'] as String? ?? '',
      attachments: atts,
      createdAt: DateTime.tryParse(payload['createdAt'] as String? ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      conversationId: payload['conversationId'] as String?,
      blocks: payload['blocks'],
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
        if (blocks != null) 'blocks': blocks,
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
    Object? blocks,
  }) {
    return ChatlyMessage(
      id: id ?? this.id,
      author: author ?? this.author,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      conversationId: conversationId ?? this.conversationId,
      blocks: blocks ?? this.blocks,
    );
  }
}
