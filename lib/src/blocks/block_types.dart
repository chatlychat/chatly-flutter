/// The rich-block vocabulary: twelve block types, as a sealed hierarchy.
///
/// Sealed so a `switch` over a block is exhaustive — a type added here and
/// forgotten in the renderer is a compile error rather than a blank space on
/// a shopper's screen. That is the job RN's `default:` case does in
/// `packages/sdk-react-native/src/components/MessageBlocks.tsx`.
library;

import 'block_values.dart';

/// One rich block. Construct these with `readChatlyBlocks`, never directly:
/// the reader is where the safety guards live.
sealed class ChatlyBlock {
  /// Creates a [ChatlyBlock].
  const ChatlyBlock({this.id});

  /// The author's id for this block, where they set one. A `status` block
  /// always has one — it exists to be patched.
  final String? id;
}

/// Prose. The markdown is rendered as PLAIN text by the bundled renderer: a
/// markdown parser would be a dependency, and `**bold**` reads acceptably raw.
class ChatlyTextBlock extends ChatlyBlock {
  /// Creates a [ChatlyTextBlock].
  const ChatlyTextBlock({required this.markdown, super.id});

  /// The body, as the author wrote it.
  final String markdown;
}

/// Whether a `media` block is a still or a clip.
enum ChatlyMediaKind {
  /// A still image.
  image,

  /// A video.
  video,
}

/// An image or a video. The block is dropped entirely when its url fails the
/// media guard — a media block IS its image, so there is nothing left to draw.
class ChatlyMediaBlock extends ChatlyBlock {
  /// Creates a [ChatlyMediaBlock].
  const ChatlyMediaBlock({
    required this.kind,
    required this.url,
    required this.alt,
    super.id,
  });

  /// Still or clip.
  final ChatlyMediaKind kind;

  /// `https:` url, already guarded.
  final String url;

  /// Alternative text. Required by the schema.
  final String alt;
}

/// A list of label/value rows.
class ChatlyFieldsBlock extends ChatlyBlock {
  /// Creates a [ChatlyFieldsBlock].
  const ChatlyFieldsBlock({required this.items, super.id});

  /// The rows. Never empty — the reader drops the block instead.
  final List<ChatlyBlockField> items;
}

/// One card.
class ChatlyCardBlock extends ChatlyBlock {
  /// Creates a [ChatlyCardBlock].
  const ChatlyCardBlock({required this.card, super.id});

  /// The card itself.
  final ChatlyCard card;
}

/// A set of cards — a product grid, or a carousel.
class ChatlyCardGridBlock extends ChatlyBlock {
  /// Creates a [ChatlyCardGridBlock].
  const ChatlyCardGridBlock({
    required this.cards,
    this.carousel = false,
    this.more,
    super.id,
  });

  /// The cards. Never empty — the reader drops the block instead.
  final List<ChatlyCard> cards;

  /// True for `layout: 'carousel'`, which scrolls horizontally. Every other
  /// layout — including the spatial ones — draws as a vertical stack: two
  /// cards side by side on a phone are narrower than the images they carry.
  final bool carousel;

  /// The trailing "show me more" tile, where the author set a usable one.
  final ChatlyGridMore? more;
}

/// A row of buttons.
class ChatlyActionsBlock extends ChatlyBlock {
  /// Creates a [ChatlyActionsBlock].
  const ChatlyActionsBlock({required this.actions, super.id});

  /// The buttons. Never empty.
  final List<ChatlyBlockAction> actions;
}

/// Suggested replies. Pressing one sends an ordinary visitor message.
class ChatlyQuickRepliesBlock extends ChatlyBlock {
  /// Creates a [ChatlyQuickRepliesBlock].
  const ChatlyQuickRepliesBlock({required this.options, super.id});

  /// The options: `label` is what the visitor reads, `value` what gets sent.
  final List<ChatlyBlockField> options;
}

/// A read-only fulfilment timeline — "where is my order", answered in the
/// thread. Nothing in it is a control: no action, no amount, no payment
/// reference.
class ChatlyOrderStatusBlock extends ChatlyBlock {
  /// Creates a [ChatlyOrderStatusBlock].
  const ChatlyOrderStatusBlock({required this.steps, super.id});

  /// The milestones. Never empty.
  final List<ChatlyOrderStep> steps;
}

/// A comparison table: the things across, their attributes down.
class ChatlyTableBlock extends ChatlyBlock {
  /// Creates a [ChatlyTableBlock].
  const ChatlyTableBlock({
    required this.columns,
    required this.rows,
    this.caption,
    super.id,
  });

  /// The headings. At least one has a non-empty label.
  final List<ChatlyTableColumn> columns;

  /// The attribute rows. Never empty.
  final List<ChatlyTableRow> rows;

  /// An optional caption above the table.
  final String? caption;
}

/// A named destination, in words — never coordinates. A world resolves it in
/// its own scene; a phone can only name it.
class ChatlyPlaceBlock extends ChatlyBlock {
  /// Creates a [ChatlyPlaceBlock].
  const ChatlyPlaceBlock({
    required this.label,
    this.detail,
    this.ref,
    super.id,
  });

  /// What the place is called.
  final String label;

  /// A second line about it.
  final String? detail;

  /// The host world's own id for it. Unread by this SDK.
  final String? ref;
}

/// Progress on something the bot is doing, patched in place as it happens.
class ChatlyStatusBlock extends ChatlyBlock {
  /// Creates a [ChatlyStatusBlock].
  const ChatlyStatusBlock({
    required String id,
    required this.text,
    this.state,
  }) : super(id: id);

  /// What is happening.
  final String text;

  /// How it is going, where the author said.
  final ChatlyStatusState? state;
}

/// A horizontal rule.
class ChatlyDividerBlock extends ChatlyBlock {
  /// Creates a [ChatlyDividerBlock].
  const ChatlyDividerBlock({super.id});
}

/// A read envelope: protocol version 1 plus at least one readable block.
class ChatlyBlocksEnvelope {
  /// Creates a [ChatlyBlocksEnvelope].
  const ChatlyBlocksEnvelope({required this.blocks});

  /// The blocks that survived the read, in order. Never empty.
  final List<ChatlyBlock> blocks;
}
