/// The WORDS a rich block renders, separate from the widgets that draw them.
///
/// Two reasons this is not inside the renderer. A price, a stock state and a
/// timeline milestone are the parts that are easy to get wrong and the parts
/// worth testing without mounting a widget; and a host rendering the envelope
/// with its own design system still wants Chatly's labels rather than
/// inventing a second set.
///
/// English literals, because this package has no translation layer: a
/// consumer who needs another language renders the envelope themselves, which
/// `readChatlyBlocks` is exported for. The DEVICE locale is still honoured
/// for numbers and dates, which is where it actually shows.
library;

import 'package:intl/intl.dart';

import 'block_types.dart';
import 'block_values.dart';

/// Format a price in the device's locale.
///
/// `amount` is MINOR units and the divisor is NOT 100: three currencies have
/// no minor unit (JPY, KRW, VND) and four have three digits (KWD, BHD, JOD,
/// OMR), so `amount / 100` renders ¥4,820 as "¥48" and 4.820 KWD as
/// "48.200 KWD" — wrong by two orders of magnitude in opposite directions,
/// and perfect in USD, which is why it would ship. The digit count is read
/// off `intl`'s own currency table, so a currency added to CLDR after this
/// was written is right with no table here.
String formatChatlyMoney(ChatlyMoney money) {
  try {
    final format = NumberFormat.currency(name: money.currency);
    final divisor = _pow10(format.maximumFractionDigits);
    return format.format(money.amount / divisor);
  } on Object {
    // A currency `intl` cannot resolve still shows a price rather than
    // taking the thread's render down.
    return '${money.currency} ${(money.amount / 100).toStringAsFixed(2)}';
  }
}

int _pow10(int digits) {
  var out = 1;
  for (var i = 0; i < digits; i++) {
    out *= 10;
  }
  return out;
}

/// The was-price line, or null when there is nothing to compare against.
///
/// "Was X" on its own line rather than a struck-through price beside it: a
/// line-through reads as decoration to a screen reader and as nothing at all
/// to a reader who has strike-through styling turned off.
String? formatChatlyCompareAt(ChatlyMoney money) {
  final compareAt = money.compareAt;
  if (compareAt == null || compareAt <= money.amount) return null;
  return 'Was ${formatChatlyMoney(ChatlyMoney(
    amount: compareAt,
    currency: money.currency,
  ))}';
}

/// Availability in this surface's own words.
///
/// The stored plain-text projection keeps the author's enum member verbatim
/// (`Stock: out_of_stock`) because it is generated on the server and read
/// back by a model; a surface rendering for a person writes its own label.
String chatlyStockLabel(ChatlyCardStock stock) {
  switch (stock) {
    case ChatlyCardStock.inStock:
      return 'In stock';
    case ChatlyCardStock.low:
      return 'Low stock';
    case ChatlyCardStock.outOfStock:
      return 'Out of stock';
  }
}

/// What a badge tone adds BESIDES a colour, and why it has to add something.
///
/// Colour may never be the only carrier of meaning: "Great price" and "Above
/// typical" are both badges and they say opposite things in one pill, which
/// is the entire reason `tone` exists. So a reader with no colour vision gets
/// the glyph and a screen reader gets [chatlyBadgeToneWord].
///
/// Empty for [ChatlyBadgeTone.neutral], which is the ABSENCE of a claim — a
/// plain pill is the correct rendition of "Sale".
String chatlyBadgeGlyph(ChatlyBadgeTone tone) {
  switch (tone) {
    case ChatlyBadgeTone.success:
      return '✓';
    case ChatlyBadgeTone.warning:
      return '!';
    case ChatlyBadgeTone.danger:
      return '✕';
    case ChatlyBadgeTone.neutral:
      return '';
  }
}

/// The tone in a word, for a screen reader. Empty for neutral.
String chatlyBadgeToneWord(ChatlyBadgeTone tone) {
  switch (tone) {
    case ChatlyBadgeTone.success:
      return 'positive';
    case ChatlyBadgeTone.warning:
      return 'caution';
    case ChatlyBadgeTone.danger:
      return 'negative';
    case ChatlyBadgeTone.neutral:
      return '';
  }
}

/// A badge as one string: the glyph, then the words.
String chatlyBadgeText(ChatlyCardBadge badge) {
  final glyph = chatlyBadgeGlyph(badge.tone);
  return glyph.isEmpty ? badge.text : '$glyph ${badge.text}';
}

/// A badge's accessible name: the words, then the tone in parentheses.
String chatlyBadgeSemanticLabel(ChatlyCardBadge badge) {
  final word = chatlyBadgeToneWord(badge.tone);
  return word.isEmpty ? badge.text : '${badge.text} ($word)';
}

/// A timeline step's state, in words.
String chatlyStepStateLabel(ChatlyStepState state) {
  switch (state) {
    case ChatlyStepState.done:
      return 'Done';
    case ChatlyStepState.current:
      return 'In progress';
    case ChatlyStepState.pending:
      return 'Pending';
  }
}

/// One timeline row's text: the milestone, its state in WORDS — a coloured
/// dot alone says nothing to a screen reader — and the time if there is one.
///
/// An absent or unformattable time leaves no dangling separator.
String chatlyStepLine(ChatlyOrderStep step) {
  final line = '${step.label} — ${chatlyStepStateLabel(step.state)}';
  final at = step.at;
  if (at == null) return line;
  try {
    return '$line · ${DateFormat.yMMMd().add_jm().format(at.toLocal())}';
  } on Object {
    return line;
  }
}

/// A table row as one line: the attribute, then its cells. A row SHORTER than
/// the columns renders blanks, which is deliberate — an author assembling a
/// comparison from a catalogue will have gaps.
String chatlyTableRowLine(ChatlyTableRow row, int columnCount) {
  final cells = List<String>.generate(
    columnCount,
    (i) => i < row.cells.length ? row.cells[i] : '',
  );
  return '${row.label}: ${cells.join(' · ')}';
}

/// A table's heading line.
String chatlyTableHeaderLine(List<ChatlyTableColumn> columns) =>
    columns.map((c) => c.label).join(' · ');

/// A place as one line: the label, and its detail where there is one.
///
/// No "take me there" button: a place is intent rather than coordinates, and
/// the host world is the only thing that can resolve it.
String chatlyPlaceLine(ChatlyPlaceBlock place) =>
    place.detail == null ? place.label : '${place.label} — ${place.detail}';

/// A status line, with the failure stated rather than coloured.
String chatlyStatusLine(ChatlyStatusBlock status) =>
    status.state == ChatlyStatusState.failed
        ? '${status.text} — failed'
        : status.text;

/// The reaction pair in words. A lone thumb glyph says nothing to a screen
/// reader.
String chatlyReactionLabel(ChatlyCardReaction reaction) =>
    reaction == ChatlyCardReaction.like ? 'Helpful' : 'Not helpful';
