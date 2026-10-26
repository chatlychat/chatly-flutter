/// Lifecycle state of a conversation.
///
/// FIVE states, and `merged` was missing until 2026-10-20. The server's
/// `conversationStatusSchema` has had it all along and
/// `POST /v1/widget/conversations/list` applies **no status filter**, so an
/// agent merging two of a contact's threads — an ordinary thing to do to a
/// visitor who opened the chat twice — hands this client a row it could not
/// represent. [parse] falls back to [open] for anything it does not know, so
/// the loser of a merge read as a live thread, and `ChatlyChatPage` resumed
/// it: the app wrote into a conversation that had been merged away and no
/// agent was looking at.
enum ChatlyConversationStatus {
  /// Open for replies.
  open,

  /// Snoozed and scheduled to reopen.
  snoozed,

  /// Closed.
  closed,

  /// Awaiting first agent reply.
  pending,

  /// Merged into another conversation. This thread is a tombstone: its
  /// messages now live on the winner, and the server answers `conflict`
  /// rather than a no-op if you try to close it.
  merged;

  /// Parses a wire-format status string. Falls back to [open] for unknowns.
  ///
  /// The fallback is deliberate — a status this build has never heard of must
  /// not make the whole list undecodable — but it is also what hid `merged`,
  /// so do not branch on `!= closed` to mean "usable". Use [isResumable],
  /// which is false for every state that is not, including the unknown one
  /// this fallback cannot distinguish.
  static ChatlyConversationStatus parse(String? raw) {
    switch (raw) {
      case 'snoozed':
        return ChatlyConversationStatus.snoozed;
      case 'closed':
        return ChatlyConversationStatus.closed;
      case 'pending':
        return ChatlyConversationStatus.pending;
      case 'merged':
        return ChatlyConversationStatus.merged;
      case 'open':
      default:
        return ChatlyConversationStatus.open;
    }
  }

  /// Whether a visitor may keep writing into a thread in this state.
  ///
  /// One place, so a state added later is decided once rather than by
  /// whichever `!=` comparison a caller happened to write. `merged` is not
  /// resumable even though it is not closed, which is exactly the
  /// distinction a `!= closed` test cannot make.
  bool get isResumable =>
      this == ChatlyConversationStatus.open ||
      this == ChatlyConversationStatus.pending ||
      this == ChatlyConversationStatus.snoozed;

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
