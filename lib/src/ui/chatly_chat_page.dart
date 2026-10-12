import 'dart:async';

import 'package:flutter/material.dart';

import '../chatly_client.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../realtime/envelope.dart';
import '../realtime/event_types.dart';
import 'chatly_composer.dart';
import 'chatly_messages_list.dart';
import 'chatly_theme.dart';

/// Full-page chat experience. Push it onto the navigator via
/// [Chatly.show], or use it as the body of your own scaffold for custom
/// header treatments.
class ChatlyChatPage extends StatefulWidget {
  /// Creates the chat page.
  const ChatlyChatPage({super.key, this.conversationId});

  /// If non-null, opens that conversation directly; otherwise the page
  /// resumes the most-recent open conversation or starts a fresh one on
  /// first send.
  final String? conversationId;

  @override
  State<ChatlyChatPage> createState() => _ChatlyChatPageState();
}

class _ChatlyChatPageState extends State<ChatlyChatPage> {
  List<ChatlyMessage> _messages = <ChatlyMessage>[];
  String? _conversationId;
  bool _loading = true;
  String? _error;
  StreamSubscription<RealtimeEnvelope>? _envelopeSub;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    // Subscribe to the realtime envelope stream up-front so we don't miss
    // events that arrive while [_bootstrap] is still resolving REST.
    _envelopeSub = Chatly.instance.events
        .where((env) => env.type == RealtimeEventType.messageCreated)
        .listen(_onEnvelope);
    _bootstrap();
  }

  @override
  void dispose() {
    _envelopeSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final client = Chatly.instance;
    try {
      if (_conversationId == null) {
        final convos = await client.listConversations(limit: 1);
        final ChatlyConversation? latest =
            convos.isEmpty ? null : convos.first;
        if (latest != null &&
            latest.status != ChatlyConversationStatus.closed) {
          _conversationId = latest.id;
        }
      }
      if (_conversationId != null) {
        final history =
            await client.listMessages(conversationId: _conversationId!);
        if (!mounted) return;
        setState(() {
          _messages = history;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
      }
      Chatly.instance.markAllRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Project a [RealtimeEventType.messageCreated] envelope into a
  /// [ChatlyMessage] and append it when it belongs to the open conversation.
  ///
  /// Unknown / out-of-conversation envelopes are silently dropped — they're
  /// still observable via [Chatly.events] for hosts that need them.
  void _onEnvelope(RealtimeEnvelope envelope) {
    final msg = ChatlyMessage.fromRealtime(envelope.payload);
    if (msg.conversationId != null &&
        msg.conversationId != _conversationId) {
      return;
    }
    if (!mounted) return;
    if (_messages.any((m) => m.id == msg.id)) return;
    setState(() {
      _messages = [..._messages, msg];
    });
  }

  Future<void> _handleSend(
    String body,
    List<ChatlyAttachment> attachments,
  ) async {
    final client = Chatly.instance;
    final optimistic = ChatlyMessage(
      id: 'optimistic-${DateTime.now().microsecondsSinceEpoch}',
      author: ChatlyMessageAuthor.contact,
      kind: body.isEmpty && attachments.isNotEmpty
          ? ChatlyMessageKind.attachmentOnly
          : ChatlyMessageKind.text,
      body: body,
      attachments: attachments,
      createdAt: DateTime.now().toUtc(),
      conversationId: _conversationId,
    );
    setState(() => _messages = [..._messages, optimistic]);
    try {
      if (_conversationId == null) {
        final res = await client.startConversation(
          body,
          attachments: attachments.isEmpty ? null : attachments,
        );
        if (!mounted) return;
        setState(() {
          _conversationId = res.conversationId;
          _messages = [
            ..._messages.where((m) => m.id != optimistic.id),
            res.message,
          ];
        });
      } else {
        await client.sendMessage(
          conversationId: _conversationId!,
          body: body,
          attachments: attachments.isEmpty ? null : attachments,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != optimistic.id).toList();
        _error = e.toString();
      });
    }
  }

  void _onTypingChanged(bool typing) {
    final convoId = _conversationId;
    if (convoId == null) return;
    if (typing) {
      Chatly.instance.typingStart(convoId);
    } else {
      Chatly.instance.typingStop(convoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Chatly.instance.config;
    final theme = config?.theme ?? const ChatlyTheme();
    final scheme = theme.toColorScheme(MediaQuery.platformBrightnessOf(context));
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: theme.background,
        fontFamily: theme.fontFamily,
      ),
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          surfaceTintColor: theme.background,
          foregroundColor: theme.foreground,
          elevation: 0,
          title: Text(theme.headerTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: theme.border),
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: theme.danger.withValues(alpha: 0.08),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.danger, fontSize: 13),
                ),
              ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(theme.primary),
                      ),
                    )
                  : StreamBuilder<RealtimeEventType>(
                      stream: Chatly.instance.events
                          .where((e) =>
                              e.type == RealtimeEventType.typingStart ||
                              e.type == RealtimeEventType.typingStop)
                          .map((e) => e.type),
                      builder: (context, _) {
                        return ChatlyMessagesList(
                          messages: _messages,
                          theme: theme,
                        );
                      },
                    ),
            ),
            ChatlyComposer(
              theme: theme,
              onSend: _handleSend,
              onTypingChanged: _onTypingChanged,
            ),
          ],
        ),
      ),
    );
  }
}
