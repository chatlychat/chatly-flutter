/// The leaf values a rich block is built from — money, actions, badges,
/// variants, cards, table cells and timeline steps.
///
/// Mirrors `packages/sdk-react-native/src/blocks/types.ts`, which is itself a
/// hand-written restatement of the server's zod schema. Two deliberate
/// differences from that file, both documented on the members below:
///
///  * an action is ONE class with a [ChatlyBlockActionKind] and a single
///    [ChatlyBlockAction.value], not six classes — see that class;
///  * the spatial fields (`card.model`, `card_grid.placement`) are omitted.
///    They exist for a host embedding a 3D world and nothing on a phone
///    screen can draw them.
///
/// Nothing here is parsed or serialised: `readChatlyBlocks` in
/// `read_blocks.dart` is the only constructor path, and the raw envelope stays
/// on [ChatlyMessage.blocks] for a host that wants to read it itself.
library;

/// A price on a card, in MINOR units of [currency].
///
/// 4820 is $48.20, and also ¥4,820, and also 4.820 KWD — the divisor is NOT
/// 100. `formatChatlyMoney` in `block_text.dart` is what resolves it.
class ChatlyMoney {
  /// Creates a [ChatlyMoney].
  const ChatlyMoney({
    required this.amount,
    required this.currency,
    this.compareAt,
  });

  /// Amount in the currency's smallest unit. Never negative.
  final int amount;

  /// ISO 4217, upper case.
  final String currency;

  /// The was-price, in minor units. Rendered only when above [amount].
  final int? compareAt;
}

/// What a block button does.
///
/// The server's vocabulary is six variants each carrying one required string
/// (`url.href`, `postback.value`, `host_event.event`, `step.canvasId`,
/// `copy.text`, `navigate.path`). This SDK collapses that to one class whose
/// [ChatlyBlockAction.value] holds whichever string the [kind] requires,
/// because every consumer here — the renderer and the host callback — needs
/// the pair and never the union. The reader still enforces the per-kind
/// requirement, so a `url` with no href never becomes an action at all.
enum ChatlyBlockActionKind {
  /// Open [ChatlyBlockAction.value] as a link. `https:`, `mailto:` or `tel:`.
  url,

  /// Send [ChatlyBlockAction.value] to the owning bot as a postback.
  postback,

  /// Hand [ChatlyBlockAction.value] to the host app as a named event.
  hostEvent,

  /// Ask for the canvas step named by [ChatlyBlockAction.value].
  step,

  /// Copy [ChatlyBlockAction.value] to the clipboard.
  copy,

  /// Go to the host app's own path, [ChatlyBlockAction.value].
  navigate,
}

/// One pressable action on a block or card.
class ChatlyBlockAction {
  /// Creates a [ChatlyBlockAction].
  const ChatlyBlockAction({
    required this.kind,
    required this.label,
    required this.value,
    this.data,
    this.silent = false,
    this.id,
    this.style,
  });

  /// What pressing it means.
  final ChatlyBlockActionKind kind;

  /// What the visitor reads on the button. Never empty.
  final String label;

  /// The one string [kind] requires. See [ChatlyBlockActionKind].
  final String value;

  /// `postback.payload` or `host_event.data`, verbatim and unvalidated.
  final Map<String, Object?>? data;

  /// `postback.silent` — true when pressing must write no visitor message.
  final bool silent;

  /// The author's own id for this action, where they set one.
  final String? id;

  /// The author's style hint (`primary`, `secondary`, …). Advisory.
  final String? style;
}

/// What a badge MEANS, not what colour it is.
///
/// "Great price" and "Above typical" are both badges and they say opposite
/// things, which is the one case a single pill cannot express.
enum ChatlyBadgeTone {
  /// A positive claim.
  success,

  /// A caution.
  warning,

  /// A negative claim.
  danger,

  /// No claim — a plain pill, which is what every badge stored before tones
  /// existed is.
  neutral,
}

/// A badge on a card, collapsed by the reader to text plus a tone.
class ChatlyCardBadge {
  /// Creates a [ChatlyCardBadge].
  const ChatlyCardBadge({required this.text, required this.tone});

  /// The words on the pill. Never empty.
  final String text;

  /// Always present: an absent tone would leave each renderer picking a
  /// different default.
  final ChatlyBadgeTone tone;
}

/// Whether the thing on a card can be bought right now. Three states, no count.
enum ChatlyCardStock {
  /// Available.
  inStock,

  /// Nearly gone.
  low,

  /// Unavailable.
  outOfStock,
}

/// A reaction a card offers. An enum because the value travels to a bot.
enum ChatlyCardReaction {
  /// Thumbs up.
  like,

  /// Thumbs down.
  dislike,
}

/// One purchasable option on a card — a size, a colour, a plan tier.
class ChatlyCardVariant {
  /// Creates a [ChatlyCardVariant].
  const ChatlyCardVariant({
    required this.label,
    required this.value,
    this.inStock,
  });

  /// What the shopper reads.
  final String label;

  /// What a program receives.
  final String value;

  /// Tri-state on purpose: null means the author did not say, which is not
  /// the same as `false`. A renderer dims a `false` and leaves a null alone.
  final bool? inStock;
}

/// A label/value pair — a `fields` row, or a quick reply.
class ChatlyBlockField {
  /// Creates a [ChatlyBlockField].
  const ChatlyBlockField({required this.label, required this.value});

  /// What the visitor reads.
  final String label;

  /// The value behind it. For a quick reply, what gets sent.
  final String value;
}

/// One card: the unit a product, an order or an article arrives as.
///
/// The list fields are EMPTY rather than null when the author set nothing —
/// nothing here is re-serialised, so "absent" and "empty" are the same thing
/// to every consumer, and an empty list is one fewer null check per renderer.
class ChatlyCard {
  /// Creates a [ChatlyCard].
  const ChatlyCard({
    required this.title,
    this.id,
    this.subtitle,
    this.image,
    this.badges = const <ChatlyCardBadge>[],
    this.price,
    this.fields = const <ChatlyBlockField>[],
    this.variants = const <ChatlyCardVariant>[],
    this.stock,
    this.actions = const <ChatlyBlockAction>[],
    this.reactions = const <ChatlyCardReaction>[],
    this.reaction,
    this.action,
  });

  /// The author's id for this card, where they set one.
  final String? id;

  /// Required: a card with no title is dropped by the reader.
  final String title;

  /// Secondary line.
  final String? subtitle;

  /// `https:` image url, already through the media guard.
  final String? image;

  /// Badges, collapsed from the write schema's three spellings.
  final List<ChatlyCardBadge> badges;

  /// The price, dropped by the reader when it could not be read.
  final ChatlyMoney? price;

  /// Attribute rows.
  final List<ChatlyBlockField> fields;

  /// Pickable options.
  final List<ChatlyCardVariant> variants;

  /// Availability.
  final ChatlyCardStock? stock;

  /// The card's buttons.
  final List<ChatlyBlockAction> actions;

  /// The reaction pair the card OFFERS, filtered and deduped.
  final List<ChatlyCardReaction> reactions;

  /// The reaction the AUTHOR says is chosen. Dropped unless [reactions]
  /// offers it, so a chosen thumb always has a control behind it.
  final ChatlyCardReaction? reaction;

  /// Fired by tapping the card's image or title. Never a `postback`: a silent
  /// message sent by tapping a photo is indistinguishable from a mis-tap.
  final ChatlyBlockAction? action;
}

/// The trailing "show me more" tile on a grid.
///
/// Narrowed by the reader to the action kinds that can page — a `copy`,
/// `host_event` or `step` tile is a button that shows no more cards.
class ChatlyGridMore {
  /// Creates a [ChatlyGridMore].
  const ChatlyGridMore({required this.label, required this.action});

  /// The tile's own label, which is what renders.
  final String label;

  /// `postback`, `url` or `navigate` only.
  final ChatlyBlockAction action;
}

/// One thing being compared, across the top of a table.
class ChatlyTableColumn {
  /// Creates a [ChatlyTableColumn].
  const ChatlyTableColumn({required this.label, this.image});

  /// The heading. An unreadable one is coerced to `''` and keeps its
  /// POSITION, because dropping it would draw every row's cells under the
  /// wrong thing.
  final String label;

  /// `https:` image url for the heading, already guarded.
  final String? image;
}

/// One attribute, down the side of a table.
class ChatlyTableRow {
  /// Creates a [ChatlyTableRow].
  const ChatlyTableRow({required this.label, required this.cells});

  /// The attribute's name. Required.
  final String label;

  /// One cell per column, left to right. May be SHORTER than the columns —
  /// the trailing ones render blank — and never longer.
  final List<String> cells;
}

/// How far along an order-status step is.
enum ChatlyStepState {
  /// Finished.
  done,

  /// Happening now.
  current,

  /// Not yet.
  pending,
}

/// One milestone on an `order_status` timeline.
class ChatlyOrderStep {
  /// Creates a [ChatlyOrderStep].
  const ChatlyOrderStep({
    required this.label,
    required this.state,
    this.at,
  });

  /// What happened.
  final String label;

  /// When, where the author said. Dropped by the reader unless it parses, so
  /// the words "Invalid Date" cannot reach a fulfilment milestone.
  final DateTime? at;

  /// Coerced to [ChatlyStepState.pending] when unrecognised: dropping the
  /// step would read as an order that skipped a stage.
  final ChatlyStepState state;
}

/// How a `status` block is going.
enum ChatlyStatusState {
  /// In flight.
  running,

  /// Finished.
  done,

  /// Gave up.
  failed,
}
