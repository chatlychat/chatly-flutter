/// Read a stored block envelope, refusing what cannot be drawn.
///
/// Mirrors `packages/sdk-react-native/src/blocks/read-envelope.ts`, which
/// mirrors the server's own zero-dependency reader.
///
/// ── The contract, which is the same on every renderer ──────────────────
///
/// Never throw, never render a hole. A row written before a field was
/// validated — or by a server NEWER than this app, which is the ordinary case
/// and not an exceptional one — must produce the most of the message that CAN
/// be drawn, not an exception and not a blank space. So:
///
///   * an unreadable BLOCK is dropped and the rest of the message renders;
///   * an unsafe card image drops the IMAGE, not the card;
///   * an unreadable price drops the PRICE, because a formatter handed a
///     string shows a shopper `NaN`;
///   * an unknown `type` is dropped silently.
///
/// ── The media guard ────────────────────────────────────────────────────
///
/// `https:` only, no control characters, no untrimmed string, length capped.
/// `Image.network` will happily fetch `http:`, and a card is authored by
/// whoever holds an API key — so the refusal the widget applies in a browser
/// applies here too. `http:` on a phone is a downgrade a shopper cannot see.
library;

import 'block_types.dart';
import 'block_values.dart';

/// `https:` and nothing else. Mirrors `isSafeMediaSrc` in the shared guard.
///
/// Exported because a host rendering the envelope itself needs the same
/// refusal — it is the only thing standing between a card author and an
/// `Image.network` call.
bool isSafeMediaSrc(String src) {
  if (!_isCleanUrlString(src)) return false;
  return Uri.tryParse(src)?.scheme == 'https';
}

/// A `url` action's href: `https:`, `mailto:` or `tel:` — exactly the shared
/// schema's set, nothing wider.
///
/// An allow-list of three rather than a deny-list, because a host handing
/// this to the platform launcher would open any scheme the OS has a handler
/// for: `intent:`, `itms-apps:` and an app's own scheme are all refused.
bool isSafeActionHref(String href) {
  if (!_isCleanUrlString(href)) return false;
  final scheme = Uri.tryParse(href)?.scheme;
  return scheme == 'https' || scheme == 'mailto' || scheme == 'tel';
}

final RegExp _control = RegExp('[\u0000-\u001f\u007f]');

bool _isCleanUrlString(String value) =>
    value.isNotEmpty &&
    value.length <= 2000 &&
    value == value.trim() &&
    !_control.hasMatch(value);

Map<String, Object?>? _bag(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final Object? key = entry.key;
    if (key is String) out[key] = entry.value;
  }
  return out;
}

List<Object?> _list(Object? raw) => raw is List<Object?> ? raw : const <Object?>[];

String? _str(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

/// A count of minor units: a non-negative integer, however JSON spelled it.
int? _minor(Object? raw) {
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is double &&
      raw.isFinite &&
      raw >= 0 &&
      raw == raw.roundToDouble() &&
      raw <= 9007199254740991) {
    return raw.toInt();
  }
  return null;
}

final RegExp _currency = RegExp(r'^[A-Z]{3}$');

/// Read a price off a stored card, or null. Refuses what cannot be drawn.
ChatlyMoney? readChatlyMoney(Object? raw) {
  final bag = _bag(raw);
  if (bag == null) return null;
  final amount = _minor(bag['amount']);
  final currency = _str(bag['currency']);
  if (amount == null || currency == null || !_currency.hasMatch(currency)) {
    return null;
  }
  return ChatlyMoney(
    amount: amount,
    currency: currency,
    compareAt: _minor(bag['compareAt']),
  );
}

const Map<String, ChatlyBlockActionKind> _actionKinds =
    <String, ChatlyBlockActionKind>{
  'url': ChatlyBlockActionKind.url,
  'postback': ChatlyBlockActionKind.postback,
  'host_event': ChatlyBlockActionKind.hostEvent,
  'step': ChatlyBlockActionKind.step,
  'copy': ChatlyBlockActionKind.copy,
  'navigate': ChatlyBlockActionKind.navigate,
};

/// Which key carries the kind's one required string.
const Map<ChatlyBlockActionKind, String> _actionValueKeys =
    <ChatlyBlockActionKind, String>{
  ChatlyBlockActionKind.url: 'href',
  ChatlyBlockActionKind.postback: 'value',
  ChatlyBlockActionKind.hostEvent: 'event',
  ChatlyBlockActionKind.step: 'canvasId',
  ChatlyBlockActionKind.copy: 'text',
  ChatlyBlockActionKind.navigate: 'path',
};

ChatlyBlockAction? _readAction(Object? raw) {
  final bag = _bag(raw);
  if (bag == null) return null;
  final label = _str(bag['label']);
  final kind = _actionKinds[bag['kind']];
  if (label == null || kind == null) return null;
  final value = _str(bag[_actionValueKeys[kind]!]);
  if (value == null) return null;
  // A link this SDK or its host may open: the schema's three schemes only.
  if (kind == ChatlyBlockActionKind.url && !isSafeActionHref(value)) return null;
  return ChatlyBlockAction(
    kind: kind,
    label: label,
    value: value,
    data: _bag(bag['payload']) ?? _bag(bag['data']),
    silent: bag['silent'] == true,
    id: _str(bag['id']),
    style: _str(bag['style']),
  );
}

List<ChatlyBlockAction> _readActions(Object? raw) => _list(raw)
    .map(_readAction)
    .whereType<ChatlyBlockAction>()
    .toList(growable: false);

/// Pairs need BOTH halves: one is unreadable, the other unanswerable.
List<ChatlyBlockField> _readPairs(Object? raw) {
  final out = <ChatlyBlockField>[];
  for (final entry in _list(raw)) {
    final bag = _bag(entry);
    final label = _str(bag?['label']);
    final value = _str(bag?['value']);
    if (label != null && value != null) {
      out.add(ChatlyBlockField(label: label, value: value));
    }
  }
  return out;
}

const Map<String, ChatlyBadgeTone> _tones = <String, ChatlyBadgeTone>{
  'success': ChatlyBadgeTone.success,
  'warning': ChatlyBadgeTone.warning,
  'danger': ChatlyBadgeTone.danger,
};

/// Badges, collapsed to ONE shape: always text plus a tone.
///
/// `card.badge` accepts three spellings — a bare string (which is what every
/// stored row holds), an object with a `tone`, or an array of up to two of
/// either. A renderer branching on all three would be three branches, two of
/// which nobody exercises, so the reader collapses it here.
///
/// An unrecognised tone is COERCED to neutral rather than dropped: dropping
/// the badge would delete the words "Final sale" to protect the colour of a
/// pill.
List<ChatlyCardBadge> _readBadges(Object? raw) {
  final entries = raw is List<Object?> ? raw : <Object?>[raw];
  final out = <ChatlyCardBadge>[];
  for (final entry in entries) {
    final text = _str(entry) ?? _str(_bag(entry)?['text']);
    if (text == null) continue;
    final tone = entry is String ? null : _tones[_bag(entry)?['tone']];
    out.add(ChatlyCardBadge(text: text, tone: tone ?? ChatlyBadgeTone.neutral));
  }
  return out;
}

const Map<String, ChatlyCardStock> _stocks = <String, ChatlyCardStock>{
  'in_stock': ChatlyCardStock.inStock,
  'low': ChatlyCardStock.low,
  'out_of_stock': ChatlyCardStock.outOfStock,
};

const Map<String, ChatlyCardReaction> _reactions = <String, ChatlyCardReaction>{
  'like': ChatlyCardReaction.like,
  'dislike': ChatlyCardReaction.dislike,
};

/// Variants, keeping the option and normalising the one field a renderer
/// branches on: `inStock` survives only as a real boolean, because the string
/// `"false"` is truthy and two renderers written the two obvious ways would
/// disagree about whether the option can be bought.
List<ChatlyCardVariant> _readVariants(Object? raw) {
  final out = <ChatlyCardVariant>[];
  for (final entry in _list(raw)) {
    final bag = _bag(entry);
    final label = _str(bag?['label']);
    final value = _str(bag?['value']);
    if (label == null || value == null) continue;
    final Object? stocked = bag?['inStock'];
    out.add(ChatlyCardVariant(
      label: label,
      value: value,
      inStock: stocked is bool ? stocked : null,
    ));
  }
  return out;
}

/// A card, or null when it has no title.
ChatlyCard? _readCard(Object? raw) {
  final bag = _bag(raw);
  final title = _str(bag?['title']);
  if (bag == null || title == null) return null;

  final image = _str(bag['image']);
  final reactions = _list(bag['reactions'])
      .map((Object? r) => _reactions[r])
      .whereType<ChatlyCardReaction>()
      .toSet()
      .toList(growable: false);
  // `reaction` is only meaningful if the card OFFERS it: a chosen thumb with
  // no control behind it is something the shopper cannot un-press.
  final chosen = _reactions[bag['reaction']];
  final tap = _readAction(bag['action']);

  return ChatlyCard(
    id: _str(bag['id']),
    title: title,
    subtitle: _str(bag['subtitle']),
    image: image != null && isSafeMediaSrc(image) ? image : null,
    badges: bag['badge'] == null
        ? const <ChatlyCardBadge>[]
        : _readBadges(bag['badge']),
    price: readChatlyMoney(bag['price']),
    fields: _readPairs(bag['fields']),
    variants: _readVariants(bag['variants']),
    stock: _stocks[bag['stock']],
    actions: _readActions(bag['actions']),
    reactions: reactions,
    reaction: reactions.contains(chosen) ? chosen : null,
    // A `postback` tap target is excluded by the schema: a silent message
    // sent by tapping a photo is indistinguishable from a mis-tap.
    action: tap == null || tap.kind == ChatlyBlockActionKind.postback
        ? null
        : tap,
  );
}

/// The trailing tile, narrowed to the kinds that can page.
ChatlyGridMore? _readGridMore(Object? raw) {
  final bag = _bag(raw);
  final label = _str(bag?['label']);
  if (label == null) return null;
  final action = _readAction(bag?['action']);
  if (action == null ||
      !(action.kind == ChatlyBlockActionKind.postback ||
          action.kind == ChatlyBlockActionKind.url ||
          action.kind == ChatlyBlockActionKind.navigate)) {
    return null;
  }
  return ChatlyGridMore(label: label, action: action);
}

const Map<String, ChatlyStepState> _stepStates = <String, ChatlyStepState>{
  'done': ChatlyStepState.done,
  'current': ChatlyStepState.current,
  'pending': ChatlyStepState.pending,
};

/// Timeline steps, with the state COERCED rather than the step dropped.
///
/// Dropping a step whose state a later release invented (`failed`, say)
/// removes a ROW from a timeline, and a timeline missing a row reads as an
/// order that skipped a stage: the words "Payment failed" vanish and the
/// shopper is told nothing. Coercing to `pending` keeps the label and the
/// timestamp — what a person actually reads — and costs only the shape of a
/// dot.
List<ChatlyOrderStep> _readSteps(Object? raw) {
  final out = <ChatlyOrderStep>[];
  for (final entry in _list(raw)) {
    final bag = _bag(entry);
    final label = _str(bag?['label']);
    if (label == null) continue;
    final at = _str(bag?['at']);
    out.add(ChatlyOrderStep(
      label: label,
      // `DateTime.tryParse` is stricter than JavaScript's `Date.parse`: it
      // wants ISO-8601, and anything else drops the DATE and keeps the step.
      at: at == null ? null : DateTime.tryParse(at),
      state: _stepStates[bag?['state']] ?? ChatlyStepState.pending,
    ));
  }
  return out;
}

/// A comparison table, or null when it is not a comparison.
///
/// ── Why a bad COLUMN is coerced and a bad ROW is dropped ─────────────
///
/// Not the same mistake. A row is identified by its own label, so a row
/// without one is a line of values nobody can interpret and it goes. A COLUMN
/// is identified by its POSITION: drop column 1 and every row's cells shift
/// left, so "USD 120.00" is drawn under the wrong product — a wrong answer
/// rather than a missing one. So an unreadable heading is coerced to an empty
/// one and keeps its place.
ChatlyTableBlock? _readTable(Map<String, Object?> bag) {
  final columns = <ChatlyTableColumn>[];
  for (final entry in _list(bag['columns'])) {
    final column = _bag(entry);
    final image = _str(column?['image']);
    columns.add(ChatlyTableColumn(
      label: _str(column?['label']) ?? '',
      image: image != null && isSafeMediaSrc(image) ? image : null,
    ));
  }
  // The headings are what make it a comparison rather than a list.
  if (!columns.any((c) => c.label.isNotEmpty)) return null;

  final rows = <ChatlyTableRow>[];
  for (final entry in _list(bag['rows'])) {
    final row = _bag(entry);
    final label = _str(row?['label']);
    if (label == null) continue;
    final cells = _list(row?['cells'])
        .take(columns.length)
        .map((Object? cell) => cell is String ? cell : '')
        .toList(growable: false);
    rows.add(ChatlyTableRow(label: label, cells: cells));
  }
  // No readable row is no comparison: a heading row over a blank space.
  if (rows.isEmpty) return null;
  return ChatlyTableBlock(
    columns: columns,
    rows: rows,
    caption: _str(bag['caption']),
    id: _str(bag['id']),
  );
}

const Map<String, ChatlyStatusState> _statusStates = <String, ChatlyStatusState>{
  'running': ChatlyStatusState.running,
  'done': ChatlyStatusState.done,
  'failed': ChatlyStatusState.failed,
};

/// Read one block, or null when nothing drawable survives.
///
/// Public so a host can render the envelope itself one block at a time.
ChatlyBlock? readChatlyBlock(Object? raw) {
  final bag = _bag(raw);
  if (bag == null) return null;
  final id = _str(bag['id']);
  switch (bag['type']) {
    case 'text':
      final markdown = _str(bag['markdown']);
      return markdown == null
          ? null
          : ChatlyTextBlock(markdown: markdown, id: id);
    case 'media':
      final url = _str(bag['url']);
      final alt = _str(bag['alt']);
      final kind = bag['kind'] == 'video'
          ? ChatlyMediaKind.video
          : bag['kind'] == 'image'
              ? ChatlyMediaKind.image
              : null;
      if (url == null || alt == null || kind == null || !isSafeMediaSrc(url)) {
        return null;
      }
      return ChatlyMediaBlock(kind: kind, url: url, alt: alt, id: id);
    case 'fields':
      final items = _readPairs(bag['items']);
      return items.isEmpty ? null : ChatlyFieldsBlock(items: items, id: id);
    case 'card':
      final card = _readCard(bag);
      return card == null ? null : ChatlyCardBlock(card: card, id: id);
    case 'card_grid':
      final cards = _list(bag['cards'])
          .map(_readCard)
          .whereType<ChatlyCard>()
          .toList(growable: false);
      return cards.isEmpty
          ? null
          : ChatlyCardGridBlock(
              cards: cards,
              carousel: bag['layout'] == 'carousel',
              more: _readGridMore(bag['more']),
              id: id,
            );
    case 'actions':
      final actions = _readActions(bag['actions']);
      return actions.isEmpty
          ? null
          : ChatlyActionsBlock(actions: actions, id: id);
    case 'quick_replies':
      final options = _readPairs(bag['options']);
      return options.isEmpty
          ? null
          : ChatlyQuickRepliesBlock(options: options, id: id);
    case 'order_status':
      final steps = _readSteps(bag['steps']);
      // No readable step is no timeline: a bordered blank space where the
      // answer to "where is my order" belongs.
      return steps.isEmpty
          ? null
          : ChatlyOrderStatusBlock(steps: steps, id: id);
    case 'table':
      return _readTable(bag);
    case 'place':
      final label = _str(bag['label']);
      return label == null
          ? null
          : ChatlyPlaceBlock(
              label: label,
              detail: _str(bag['detail']),
              ref: _str(bag['ref']),
              id: id,
            );
    case 'status':
      // `id` is required: a status block exists to be patched.
      final text = _str(bag['text']);
      return id == null || text == null
          ? null
          : ChatlyStatusBlock(
              id: id,
              text: text,
              state: _statusStates[bag['state']],
            );
    case 'divider':
      return ChatlyDividerBlock(id: id);
    default:
      // An old app meeting a newer server. Expected, not exceptional.
      return null;
  }
}

/// Read a whole `messages.blocks` value, or null when nothing can be drawn.
///
/// Pass [ChatlyMessage.blocks] straight in — it is deliberately untyped, and
/// this is the only thing that should interpret it. Never throws.
ChatlyBlocksEnvelope? readChatlyBlocks(Object? raw) {
  final bag = _bag(raw);
  if (bag == null || bag['v'] != 1 || bag['blocks'] is! List<Object?>) {
    return null;
  }
  final blocks = _list(bag['blocks'])
      .map(readChatlyBlock)
      .whereType<ChatlyBlock>()
      .toList(growable: false);
  return blocks.isEmpty ? null : ChatlyBlocksEnvelope(blocks: blocks);
}
