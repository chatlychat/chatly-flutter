import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import 'chatly_theme.dart';

/// Renders one attachment inside a message bubble. Image mime types come
/// through as inline thumbnails (max 200px tall); everything else renders as
/// a compact file row with name and human-readable size.
class _AttachmentView extends StatelessWidget {
  const _AttachmentView({
    required this.attachment,
    required this.theme,
    required this.isContact,
  });

  final ChatlyAttachment attachment;
  final ChatlyTheme theme;
  final bool isContact;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          attachment.url,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _FileRow(
            attachment: attachment,
            theme: theme,
            isContact: isContact,
          ),
        ),
      );
    }
    return _FileRow(
      attachment: attachment,
      theme: theme,
      isContact: isContact,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.attachment,
    required this.theme,
    required this.isContact,
  });

  final ChatlyAttachment attachment;
  final ChatlyTheme theme;
  final bool isContact;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fg = isContact ? theme.onPrimary : theme.foreground;
    final muted = isContact
        ? theme.onPrimary.withValues(alpha: 0.7)
        : theme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isContact
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 18, color: fg),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  _formatBytes(attachment.sizeBytes),
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable list of [ChatlyMessage]s rendered as left/right chat bubbles.
///
/// Stateless — pass the message list in, swap it out when new messages
/// arrive. The list automatically reverses so the newest message sits at the
/// bottom while preserving natural scroll behaviour.
class ChatlyMessagesList extends StatelessWidget {
  /// Creates a messages list.
  const ChatlyMessagesList({
    super.key,
    required this.messages,
    required this.theme,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
  });

  /// Messages to render. Order should be oldest-first.
  final List<ChatlyMessage> messages;

  /// Theme used to colour bubbles.
  final ChatlyTheme theme;

  /// Padding around the list contents.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Say hi! An agent will be with you shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.mutedForeground, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: padding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        return _Bubble(message: msg, theme: theme);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.theme});

  final ChatlyMessage message;
  final ChatlyTheme theme;

  bool get _isContact => message.author == ChatlyMessageAuthor.contact;
  bool get _isSystem => message.author == ChatlyMessageAuthor.system ||
      message.kind == ChatlyMessageKind.systemEvent;

  @override
  Widget build(BuildContext context) {
    if (_isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.body,
            style: TextStyle(
              color: theme.mutedForeground,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final bg = _isContact ? theme.primary : theme.surface;
    final fg = _isContact ? theme.onPrimary : theme.foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            _isContact ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(theme.borderRadius),
                  topRight: Radius.circular(theme.borderRadius),
                  bottomLeft: Radius.circular(_isContact ? theme.borderRadius : 4),
                  bottomRight:
                      Radius.circular(_isContact ? 4 : theme.borderRadius),
                ),
                border: _isContact
                    ? null
                    : Border.all(color: theme.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.body.isNotEmpty)
                    Text(
                      message.body,
                      style: TextStyle(color: fg, fontSize: 15, height: 1.35),
                    ),
                  if (message.attachments.isNotEmpty) ...[
                    if (message.body.isNotEmpty) const SizedBox(height: 6),
                    for (final a in message.attachments)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _AttachmentView(
                          attachment: a,
                          theme: theme,
                          isContact: _isContact,
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.jm().format(message.createdAt.toLocal()),
                    style: TextStyle(
                      color: _isContact
                          ? theme.onPrimary.withValues(alpha: 0.7)
                          : theme.mutedForeground,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
