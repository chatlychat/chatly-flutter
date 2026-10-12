/// Chatly — Flutter SDK for the Chatly live chat and customer messaging
/// platform.
///
/// Public entry point for app integrators. Import this single file:
///
/// ```dart
/// import 'package:chatly/chatly.dart';
/// ```
///
/// The SDK is a singleton, accessed via [Chatly.instance].
library chatly;

export 'src/chatly_client.dart' show Chatly;
export 'src/chatly_config.dart' show ChatlyConfig;
export 'src/chatly_identity.dart' show ChatlyIdentity;

export 'src/models/init_response.dart'
    show InitResponse, InitSession, InitWorkspace;
export 'src/models/conversation.dart'
    show ChatlyConversation, ChatlyConversationStatus;
export 'src/models/message.dart'
    show ChatlyAttachment, ChatlyMessage, ChatlyMessageAuthor, ChatlyMessageKind;
export 'src/models/kb_article.dart' show ChatlyKbArticle;
export 'src/models/kb_result.dart' show ChatlyKbResult;

export 'src/realtime/envelope.dart' show RealtimeEnvelope;
export 'src/realtime/event_types.dart' show RealtimeEventType;

export 'src/ui/chatly_widget.dart' show ChatlyWidget;
export 'src/ui/chatly_chat_page.dart' show ChatlyChatPage;
export 'src/ui/chatly_messages_list.dart' show ChatlyMessagesList;
export 'src/ui/chatly_composer.dart' show ChatlyComposer;
export 'src/ui/chatly_theme.dart' show ChatlyTheme;
