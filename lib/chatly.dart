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

/// Failure types a host may need to catch: a refused widget call (whose
/// `visitorMessage` is copy written for the visitor to read) and an upload
/// that failed outside our API.
export 'src/transport/rest_client.dart'
    show ChatlyRealtimeToken, ChatlyRestException, ChatlyUploadException;

export 'src/models/init_response.dart'
    show InitResponse, InitSession, InitWorkspace;
export 'src/models/conversation.dart'
    show ChatlyConversation, ChatlyConversationStatus;
export 'src/models/message.dart'
    show ChatlyAttachment, ChatlyMessage, ChatlyMessageAuthor, ChatlyMessageKind;
/// The rich-block vocabulary a `rich` message carries, and the lenient
/// reader that turns [ChatlyMessage.blocks] into it. Exported so a host can
/// render cards with its own design system instead of the bundled one —
/// `readChatlyBlocks` is the only safe way to interpret that value.
export 'src/blocks/block_text.dart';
export 'src/blocks/block_types.dart';
export 'src/blocks/block_values.dart';
export 'src/blocks/read_blocks.dart';

export 'src/models/kb_article.dart' show ChatlyKbArticle;
export 'src/models/kb_result.dart' show ChatlyKbResult;

export 'src/realtime/envelope.dart' show RealtimeEnvelope;
export 'src/realtime/event_types.dart' show RealtimeEventType;

export 'src/ui/chatly_widget.dart' show ChatlyWidget;
export 'src/ui/chatly_chat_page.dart' show ChatlyChatPage;
export 'src/ui/chatly_block_card.dart'
    show ChatlyActionButton, ChatlyBlockActionHandler, ChatlyBlockCard;
export 'src/ui/chatly_blocks.dart' show ChatlyBlocks, ChatlyQuickReplyHandler;
export 'src/ui/chatly_messages_list.dart' show ChatlyMessagesList;
export 'src/ui/chatly_composer.dart' show ChatlyComposer;
export 'src/ui/chatly_theme.dart' show ChatlyTheme;
