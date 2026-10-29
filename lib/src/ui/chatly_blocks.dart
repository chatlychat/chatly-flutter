/// Rich blocks on a Flutter screen — the cards, grids, timelines and tables a
/// `rich` message carries.
///
/// ── What presses do, and what they deliberately do not ────────────────
///
/// Every pressed button is handed to [ChatlyBlocks.onAction] and nothing else
/// happens here, whatever its kind. That is wider than the React Native SDK,
/// which keeps `host_event` for the host and runs the rest itself, and the
/// reason is transport: this SDK has no postback, no canvas-step and no
/// action-report method (`Chatly` offers `sendMessage`, `startConversation`,
/// uploads, typing and reads — nothing else), so a `postback` run from here
/// would have to be smuggled out as a visitor message, and a `silent` one
/// would then become visible. A `url` is handed over for the same kind of
/// reason: opening a browser from Flutter needs `url_launcher`, and this
/// package has no dependency a host has to rebuild for. The iOS and Android
/// SDKs DO open a `url` natively, because there it is one platform call.
///
/// With no handler wired, buttons render disabled rather than looking live
/// and doing nothing.
///
/// A `quick_replies` press is the exception: those ARE ordinary visitor
/// messages, so [ChatlyBlocks.onQuickReply] sends one — and
/// [ChatlyChatPage] wires it to the client for you.
///
/// ── A carousel scrolls; a grid stacks ─────────────────────────────────
///
/// Never two columns. Two cards side by side on a phone are narrower than the
/// images they carry. A `carousel` is honoured because it is horizontal
/// rather than narrow: each card gets most of the width and the row scrolls.
library;

import 'package:flutter/material.dart';

import '../blocks/block_text.dart';
import '../blocks/block_types.dart';
import '../blocks/block_values.dart';
import '../blocks/read_blocks.dart';
import 'chatly_block_card.dart';
import 'chatly_theme.dart';

/// Called when the visitor presses a quick reply. The value is what gets
/// sent, not the label.
typedef ChatlyQuickReplyHandler = void Function(String value);

/// The rich blocks on one message.
///
/// Pass [ChatlyMessage.blocks] in raw: this widget reads it with
/// `readChatlyBlocks` at RENDER time and draws nothing at all when there is
/// nothing drawable — a malformed envelope, or one carrying only block types
/// this release does not know, costs the message's text nothing.
class ChatlyBlocks extends StatelessWidget {
  /// Creates a [ChatlyBlocks].
  const ChatlyBlocks({
    super.key,
    required this.blocks,
    required this.theme,
    this.onAction,
    this.onQuickReply,
  });

  /// The stored envelope, straight off the message row. Unvalidated.
  final Object? blocks;

  /// Colours.
  final ChatlyTheme theme;

  /// Where a pressed action goes.
  final ChatlyBlockActionHandler? onAction;

  /// Where a pressed quick reply goes.
  final ChatlyQuickReplyHandler? onQuickReply;

  @override
  Widget build(BuildContext context) {
    final envelope = readChatlyBlocks(blocks);
    if (envelope == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final block in envelope.blocks)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Block(
              block: block,
              theme: theme,
              onAction: onAction,
              onQuickReply: onQuickReply,
            ),
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.block,
    required this.theme,
    this.onAction,
    this.onQuickReply,
  });

  final ChatlyBlock block;
  final ChatlyTheme theme;
  final ChatlyBlockActionHandler? onAction;
  final ChatlyQuickReplyHandler? onQuickReply;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: theme.mutedForeground, fontSize: 12);
    final body = TextStyle(color: theme.foreground, fontSize: 14, height: 1.35);

    // Exhaustive over the sealed hierarchy: a block type added to
    // `block_types.dart` and forgotten here is a compile error rather than a
    // blank space on a shopper's screen.
    switch (block) {
      case ChatlyTextBlock(:final markdown):
        // PLAIN text, deliberately. A markdown renderer is a dependency, and
        // what a bot actually emits — `**bold**`, a bullet, a link — reads
        // acceptably raw. A host who wants more renders the envelope itself.
        return Text(markdown, style: body);

      case ChatlyMediaBlock(:final kind, :final url, :final alt):
        if (kind == ChatlyMediaKind.image) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: alt,
              errorBuilder: (_, __, ___) => Text(alt, style: muted),
            ),
          );
        }
        // No video player without a dependency. The alt text plus a handed-
        // over link is strictly better than a blank space.
        return _LinkLine(
          label: alt,
          theme: theme,
          onTap: onAction == null
              ? null
              : () => onAction!(ChatlyBlockAction(
                    kind: ChatlyBlockActionKind.url,
                    label: alt,
                    value: url,
                  )),
        );

      case ChatlyFieldsBlock(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Text('${item.label}: ${item.value}', style: muted),
          ],
        );

      case ChatlyCardBlock(:final card):
        return ChatlyBlockCard(card: card, theme: theme, onAction: onAction);

      case ChatlyCardGridBlock(:final cards, :final carousel, :final more):
        // The trailing tile's own label is what renders, not the action's:
        // `more` carries both, and the tile is the thing the shopper reads.
        // Only the label is overridden, so the postback's value and the
        // url's href reach the host exactly as authored.
        final tile = more == null
            ? null
            : ChatlyActionButton(
                action: ChatlyBlockAction(
                  kind: more.action.kind,
                  label: more.label,
                  value: more.action.value,
                  data: more.action.data,
                  silent: more.action.silent,
                  id: more.action.id,
                  style: more.action.style,
                ),
                theme: theme,
                onAction: onAction,
              );
        if (carousel) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final card in cards)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChatlyBlockCard(
                      card: card,
                      theme: theme,
                      onAction: onAction,
                      width: 240,
                    ),
                  ),
                if (tile != null) tile,
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChatlyBlockCard(
                  card: card,
                  theme: theme,
                  onAction: onAction,
                ),
              ),
            if (tile != null) tile,
          ],
        );

      case ChatlyActionsBlock(:final actions):
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final action in actions)
              ChatlyActionButton(
                action: action,
                theme: theme,
                onAction: onAction,
              ),
          ],
        );

      case ChatlyQuickRepliesBlock(:final options):
        return Semantics(
          label: 'Quick replies',
          container: true,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                ActionChip(
                  label: Text(
                    option.label,
                    style: TextStyle(color: theme.foreground, fontSize: 13),
                  ),
                  side: BorderSide(color: theme.border),
                  backgroundColor: theme.background,
                  onPressed: onQuickReply == null
                      ? null
                      : () => onQuickReply!(option.value),
                ),
            ],
          ),
        );

      case ChatlyOrderStatusBlock(:final steps):
        return Semantics(
          label: 'Order status',
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final step in steps)
                Text(
                  chatlyStepLine(step),
                  style: step.state == ChatlyStepState.pending ? muted : body,
                ),
            ],
          ),
        );

      case ChatlyTableBlock(:final columns, :final rows, :final caption):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption != null) Text(caption, style: muted),
            Text(
              chatlyTableHeaderLine(columns),
              style: TextStyle(
                color: theme.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final row in rows)
              Text(chatlyTableRowLine(row, columns.length), style: body),
          ],
        );

      case final ChatlyPlaceBlock place:
        final line = chatlyPlaceLine(place);
        return Text(line, semanticsLabel: 'Place: $line', style: body);

      case final ChatlyStatusBlock status:
        return Text(chatlyStatusLine(status), style: muted);

      case ChatlyDividerBlock():
        return Semantics(
          label: 'divider',
          child: Container(height: 1, color: theme.border),
        );
    }
  }
}

/// A tappable line of text, used where there is no player for the media.
class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.label, required this.theme, this.onTap});

  final String label;
  final ChatlyTheme theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: onTap == null ? theme.foreground : theme.primary,
          fontSize: 14,
          decoration: onTap == null ? null : TextDecoration.underline,
        ),
      ),
    );
  }
}
