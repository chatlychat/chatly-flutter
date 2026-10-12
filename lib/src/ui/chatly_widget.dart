import 'package:flutter/material.dart';

import '../chatly_client.dart';
import 'chatly_theme.dart';

/// Embeddable floating-bubble Chatly entry point.
///
/// Drop it into the bottom-right of any scaffold via a `Stack` or
/// `floatingActionButton` slot. Tapping the bubble opens the bundled
/// [ChatlyChatPage].
///
/// ```dart
/// Scaffold(
///   body: Stack(children: const [MyContent(), ChatlyWidget()]),
/// )
/// ```
class ChatlyWidget extends StatelessWidget {
  /// Creates a [ChatlyWidget].
  const ChatlyWidget({
    super.key,
    this.bottom = 24,
    this.right = 24,
    this.icon = Icons.chat_bubble_rounded,
  });

  /// Inset from the bottom edge.
  final double bottom;

  /// Inset from the right edge.
  final double right;

  /// Icon shown inside the bubble.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Chatly.instance.config?.theme ?? const ChatlyTheme();
    return Positioned(
      bottom: bottom,
      right: right,
      child: StreamBuilder<int>(
        stream: Chatly.instance.unreadCount,
        initialData: 0,
        builder: (context, snap) {
          final unread = snap.data ?? 0;
          return Material(
            color: theme.primary,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: theme.primary.withValues(alpha: 0.4),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Chatly.instance.show(context),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: theme.onPrimary, size: 26),
                    if (unread > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.danger,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
