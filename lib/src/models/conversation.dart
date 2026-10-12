/// Lifecycle state of a conversation.
enum ChatlyConversationStatus {
  /// Open for replies.
  open,

  /// Snoozed and scheduled to reopen.
  snoozed,

  /// Closed.
  closed,

  /// Awaiting first agent reply.
  pending;

  /// Parses a wire-format status string. Falls back to [open] for unknowns.
  static ChatlyConversationStatus parse(String? raw) {
    switch (raw) {
      case 'snoozed':
        return ChatlyConversationStatus.snoozed;
      case 'closed':
        return ChatlyConversationStatus.closed;
      case 'pending':
        return ChatlyConversationStatus.pending;
      case 'open':
      default:
        return ChatlyConversationStatus.open;
    }
  }

  /// Wire format of this status (matches the server enum).
  String get wireName => name;
}

/// Summary of a conversation as returned by
/// `POST /v1/widget/conversations/list`.
class ChatlyConversation {
  /// Creates a [ChatlyConversation]. Generally constructed via [fromJson].
  const ChatlyConversation({
    required this.id,
    required this.status,
    required this.subject,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadContactCount,
    required this.createdAt,
  });

  /// Conversation id.
  final String id;

  /// Lifecycle status.
  final ChatlyConversationStatus status;

  /// Optional subject line (always null for chat-first conversations).
  final String? subject;

  /// Plain-text preview of the most recent message.
  final String? lastMessagePreview;

  /// Timestamp of the most recent message.
  final DateTime? lastMessageAt;

  /// Number of messages unread by the contact.
  final int unreadContactCount;

  /// Timestamp the conversation was created.
  final DateTime createdAt;

  /// Parses a [ChatlyConversation] from the wire format.
  factory ChatlyConversation.fromJson(Map<String, Object?> json) {
    return ChatlyConversation(
      id: json['id'] as String? ?? '',
      status:
          ChatlyConversationStatus.parse(json['status'] as String?),
      subject: json['subject'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: _parseDate(json['lastMessageAt']),
      unreadContactCount: (json['unreadContactCount'] as num?)?.toInt() ?? 0,
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now().toUtc(),
    );
  }

  /// Serialises this [ChatlyConversation] to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'status': status.wireName,
        'subject': subject,
        'lastMessagePreview': lastMessagePreview,
        'lastMessageAt': lastMessageAt?.toUtc().toIso8601String(),
        'unreadContactCount': unreadContactCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
