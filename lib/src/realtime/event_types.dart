/// Strongly-typed realtime event names.
///
/// Mirrors the v1 enum declared in `packages/shared/src/realtime/index.ts`.
/// Use [RealtimeEventTypeExt.parse] to map raw wire strings to enum values
/// safely.
enum RealtimeEventType {
  /// `session.connected`
  sessionConnected,

  /// `session.disconnected`
  sessionDisconnected,

  /// `session.ping`
  sessionPing,

  /// `session.pong`
  sessionPong,

  /// `session.error`
  sessionError,

  /// `subscribe`
  subscribe,

  /// `unsubscribe`
  unsubscribe,

  /// `replay.completed`
  replayCompleted,

  /// `presence.online`
  presenceOnline,

  /// `presence.offline`
  presenceOffline,

  /// `presence.away`
  presenceAway,

  /// `conversation.created`
  conversationCreated,

  /// `conversation.updated`
  conversationUpdated,

  /// `conversation.assigned`
  conversationAssigned,

  /// `conversation.closed`
  conversationClosed,

  /// `conversation.reopened`
  conversationReopened,

  /// `message.created`
  messageCreated,

  /// `message.updated`
  messageUpdated,

  /// `message.deleted`
  messageDeleted,

  /// `message.read`
  messageRead,

  /// `message.delivered`
  messageDelivered,

  /// `typing.start`
  typingStart,

  /// `typing.stop`
  typingStop,

  /// `visitor.identified`
  visitorIdentified,

  /// `visitor.page_view`
  visitorPageView,

  /// `trigger.fired`
  triggerFired,

  /// `ai.copilot.suggestion`
  aiCopilotSuggestion,

  /// `ai.agent.message`
  aiAgentMessage,

  /// Unknown wire value (forward-compatible fallback).
  unknown,
}

/// Wire <-> enum mapping helpers for [RealtimeEventType].
extension RealtimeEventTypeExt on RealtimeEventType {
  /// Wire format of this event type. [RealtimeEventType.unknown] maps to the
  /// literal string `unknown`.
  String get wireName {
    switch (this) {
      case RealtimeEventType.sessionConnected:
        return 'session.connected';
      case RealtimeEventType.sessionDisconnected:
        return 'session.disconnected';
      case RealtimeEventType.sessionPing:
        return 'session.ping';
      case RealtimeEventType.sessionPong:
        return 'session.pong';
      case RealtimeEventType.sessionError:
        return 'session.error';
      case RealtimeEventType.subscribe:
        return 'subscribe';
      case RealtimeEventType.unsubscribe:
        return 'unsubscribe';
      case RealtimeEventType.replayCompleted:
        return 'replay.completed';
      case RealtimeEventType.presenceOnline:
        return 'presence.online';
      case RealtimeEventType.presenceOffline:
        return 'presence.offline';
      case RealtimeEventType.presenceAway:
        return 'presence.away';
      case RealtimeEventType.conversationCreated:
        return 'conversation.created';
      case RealtimeEventType.conversationUpdated:
        return 'conversation.updated';
      case RealtimeEventType.conversationAssigned:
        return 'conversation.assigned';
      case RealtimeEventType.conversationClosed:
        return 'conversation.closed';
      case RealtimeEventType.conversationReopened:
        return 'conversation.reopened';
      case RealtimeEventType.messageCreated:
        return 'message.created';
      case RealtimeEventType.messageUpdated:
        return 'message.updated';
      case RealtimeEventType.messageDeleted:
        return 'message.deleted';
      case RealtimeEventType.messageRead:
        return 'message.read';
      case RealtimeEventType.messageDelivered:
        return 'message.delivered';
      case RealtimeEventType.typingStart:
        return 'typing.start';
      case RealtimeEventType.typingStop:
        return 'typing.stop';
      case RealtimeEventType.visitorIdentified:
        return 'visitor.identified';
      case RealtimeEventType.visitorPageView:
        return 'visitor.page_view';
      case RealtimeEventType.triggerFired:
        return 'trigger.fired';
      case RealtimeEventType.aiCopilotSuggestion:
        return 'ai.copilot.suggestion';
      case RealtimeEventType.aiAgentMessage:
        return 'ai.agent.message';
      case RealtimeEventType.unknown:
        return 'unknown';
    }
  }

  /// Parses a wire-format event name. Unknown strings yield
  /// [RealtimeEventType.unknown] for forward compatibility.
  static RealtimeEventType parse(String? raw) {
    for (final value in RealtimeEventType.values) {
      if (value.wireName == raw) return value;
    }
    return RealtimeEventType.unknown;
  }
}
