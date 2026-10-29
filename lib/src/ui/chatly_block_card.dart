/// ONE card, and everything that hangs off it: badges, price, variants,
/// stock, fields, buttons and the reaction pair.
///
/// Split from `chatly_blocks.dart` because a card is most of the drawing and
/// that file is the block list plus the action plumbing. The seam is the same
/// one `packages/sdk-react-native/src/components/BlockCard.tsx` takes.
library;

import 'package:flutter/material.dart';

import '../blocks/block_text.dart';
import '../blocks/block_values.dart';
import 'chatly_theme.dart';

/// Called when the visitor presses a block button.
///
/// Every kind arrives here, not just `host_event`: this SDK has no postback,
/// canvas-step or link-opening transport of its own, so the host app is what
/// runs a payment sheet, a postback, a navigation or a browser hop. See the
/// header of `chatly_blocks.dart`.
typedef ChatlyBlockActionHandler = void Function(ChatlyBlockAction action);

/// One block button.
///
/// Rendered DISABLED when no handler is wired, which is deliberate: a button
/// that looks live and does nothing is worse than one that says it cannot be
/// pressed.
class ChatlyActionButton extends StatelessWidget {
  /// Creates a [ChatlyActionButton].
  const ChatlyActionButton({
    super.key,
    required this.action,
    required this.theme,
    this.onAction,
  });

  /// The action to run.
  final ChatlyBlockAction action;

  /// Colours.
  final ChatlyTheme theme;

  /// Where a press goes.
  final ChatlyBlockActionHandler? onAction;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onAction == null ? null : () => onAction!(action),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.foreground,
        side: BorderSide(color: theme.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(action.label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// The badges on a card, all of them.
///
/// Both, never the first: the common pair is a fact and a verdict — "Sale"
/// beside "Above typical" — and drawing one shows the shopper half of what
/// the author wrote.
///
/// Only `danger` gets a COLOUR, and the gap is deliberate: [ChatlyTheme] is
/// this package's public theme contract and carries `danger` but no `success`
/// and no `warning`. Mapping those onto `primary`, or onto a hard-coded
/// green, would be this file deciding what a consumer's palette means. They
/// take the ordinary border and lean on the glyph and the accessible word,
/// which carry the meaning anyway.
class ChatlyCardBadges extends StatelessWidget {
  /// Creates a [ChatlyCardBadges].
  const ChatlyCardBadges({
    super.key,
    required this.badges,
    required this.theme,
  });

  /// The badges, already collapsed by the reader.
  final List<ChatlyCardBadge> badges;

  /// Colours.
  final ChatlyTheme theme;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final badge in badges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(
                color: badge.tone == ChatlyBadgeTone.danger
                    ? theme.danger
                    : theme.border,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chatlyBadgeText(badge),
              semanticsLabel: chatlyBadgeSemanticLabel(badge),
              style: TextStyle(color: theme.foreground, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// One card.
///
/// The reaction pair is DRAWN and not pressable — the one deliberately
/// unfinished thing here. Pressing one is a silent postback in the web widget
/// and in React Native, and this SDK has no postback transport; inventing a
/// wire name here that the server later spelled differently would be a silent
/// no-op plus a breaking release to correct. The author's own
/// `card.reaction` still renders as selected, so a verdict a bot is ranking
/// on is visible to the shopper rather than hidden.
class ChatlyBlockCard extends StatelessWidget {
  /// Creates a [ChatlyBlockCard].
  const ChatlyBlockCard({
    super.key,
    required this.card,
    required this.theme,
    this.onAction,
    this.width,
  });

  /// The card to draw.
  final ChatlyCard card;

  /// Colours.
  final ChatlyTheme theme;

  /// Where a button press goes.
  final ChatlyBlockActionHandler? onAction;

  /// Fixed width, used by a carousel. Null fills the bubble.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: theme.mutedForeground, fontSize: 12);
    final body = TextStyle(color: theme.foreground, fontSize: 14);
    final price = card.price;
    final stock = card.stock;
    final tap = card.action;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.image != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                card.image!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                // A refused image must not take the card down with it.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Text(
          card.title,
          style: TextStyle(
            color: theme.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The image and title become ONE tappable, not the whole card:
          // nesting tappables makes a card's buttons unreachable.
          if (tap == null || onAction == null)
            header
          else
            InkWell(onTap: () => onAction!(tap), child: header),
          if (card.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(card.subtitle!, style: muted),
            ),
          if (card.badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ChatlyCardBadges(badges: card.badges, theme: theme),
            ),
          if (price != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                formatChatlyMoney(price),
                style: TextStyle(
                  color: theme.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (formatChatlyCompareAt(price) != null)
              Text(formatChatlyCompareAt(price)!, style: muted),
          ],
          if (stock != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(chatlyStockLabel(stock), style: muted),
            ),
          for (final field in card.fields)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${field.label}: ${field.value}', style: muted),
            ),
          for (final variant in card.variants)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                variant.label,
                // `inStock == false` is dimmed; an ABSENT one is left alone,
                // because the author not saying is not the same as a no.
                style: variant.inStock == false ? muted : body,
              ),
            ),
          if (card.actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final action in card.actions)
                    ChatlyActionButton(
                      action: action,
                      theme: theme,
                      onAction: onAction,
                    ),
                ],
              ),
            ),
          if (card.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reaction in card.reactions)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        chatlyReactionLabel(reaction),
                        style: card.reaction == reaction
                            ? TextStyle(
                                color: theme.foreground,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              )
                            : muted,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
