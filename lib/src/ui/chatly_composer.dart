import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../chatly_client.dart';
import '../models/message.dart';
import '../transport/rest_client.dart';
import 'chatly_theme.dart';

/// Bottom-anchored chat composer: paperclip + text field + send button.
///
/// Calls [onSend] when the user submits a non-empty message *or* has staged
/// at least one attachment, and [onTypingChanged] when the typing state flips
/// (with a 1.5s idle window).
class ChatlyComposer extends StatefulWidget {
  /// Creates a composer.
  const ChatlyComposer({
    super.key,
    required this.theme,
    required this.onSend,
    this.onTypingChanged,
    this.placeholder = 'Type a message…',
    this.enabled = true,
  });

  /// Theme used to colour the composer.
  final ChatlyTheme theme;

  /// Called when the user submits a non-empty message. The list of staged
  /// attachments may be empty for a plain text send.
  final FutureOr<void> Function(String body, List<ChatlyAttachment> attachments)
      onSend;

  /// Called as the user starts (true) / stops (false) typing.
  final ValueChanged<bool>? onTypingChanged;

  /// Placeholder shown when the field is empty.
  final String placeholder;

  /// Whether the composer accepts input. Disabled during in-flight sends.
  final bool enabled;

  @override
  State<ChatlyComposer> createState() => _ChatlyComposerState();
}

class _ChatlyComposerState extends State<ChatlyComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _typingTimer;
  bool _wasTyping = false;
  bool _isSending = false;
  bool _isUploading = false;
  final List<ChatlyAttachment> _staged = <ChatlyAttachment>[];

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final isTyping = value.trim().isNotEmpty;
    if (isTyping != _wasTyping) {
      _wasTyping = isTyping;
      widget.onTypingChanged?.call(isTyping);
    }
    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_wasTyping) {
          _wasTyping = false;
          widget.onTypingChanged?.call(false);
        }
      });
    }
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    final attachments = List<ChatlyAttachment>.from(_staged);
    if ((body.isEmpty && attachments.isEmpty) || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSend(body, attachments);
      _controller.clear();
      setState(() {
        _staged.clear();
      });
      if (_wasTyping) {
        _wasTyping = false;
        widget.onTypingChanged?.call(false);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Opens the platform picker, reads bytes, and uploads via the Chatly
  /// client. On success the attachment is appended to the staged chip strip.
  Future<void> _pickAndUpload() async {
    if (_isUploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;
    final mime = _guessMime(picked.name, picked.extension);
    setState(() => _isUploading = true);
    try {
      final attachment = await Chatly.instance.uploadAttachment(
        Uint8List.fromList(bytes),
        picked.name,
        mime,
      );
      if (!mounted) return;
      setState(() => _staged.add(attachment));
    } on Object catch (err) {
      /*
       * Show what the server said.
       *
       * The presign route refuses on three conditions and each one's copy is
       * written for the VISITOR to read: "File uploads are turned off for
       * this chat", "That file type is not accepted: …", "Files must be under
       * 10 MB". This used to say "Upload failed. Try again." for all three,
       * which is wrong twice over — two of them will fail identically on
       * every retry, and the one sentence that told the visitor what to do
       * instead was thrown away.
       */
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(content: Text(_uploadFailureText(err))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// The visitor-facing reason an upload did not happen.
  String _uploadFailureText(Object err) {
    if (err is ChatlyRestException) {
      return err.visitorMessage ?? 'Upload failed. Try again.';
    }
    if (err is ChatlyUploadException) {
      return err.message;
    }
    return 'Upload failed. Try again.';
  }

  /// Crude extension → mime mapping; full table is overkill for the widget.
  String _guessMime(String filename, String? ext) {
    final e = (ext ?? '').toLowerCase();
    switch (e) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final disabled = !widget.enabled || _isSending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_staged.isNotEmpty || _isUploading) ...[
              _StagedChips(
                attachments: _staged,
                uploading: _isUploading,
                theme: theme,
                onRemove: (a) {
                  setState(() => _staged.removeWhere((x) => x.id == a.id));
                },
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: disabled || _isUploading ? null : _pickAndUpload,
                  icon: _isUploading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(theme.primary),
                          ),
                        )
                      : Icon(Icons.attach_file, color: theme.primary),
                  tooltip: 'Attach a file',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: !disabled,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _submit(),
                    style:
                        TextStyle(color: theme.foreground, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: widget.placeholder,
                      hintStyle: TextStyle(color: theme.mutedForeground),
                      filled: true,
                      fillColor: theme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(theme.borderRadius),
                        borderSide: BorderSide(color: theme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(theme.borderRadius),
                        borderSide: BorderSide(color: theme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(theme.borderRadius),
                        borderSide:
                            BorderSide(color: theme.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: disabled
                      ? theme.primary.withValues(alpha: 0.5)
                      : theme.primary,
                  borderRadius:
                      BorderRadius.circular(theme.borderRadius),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(theme.borderRadius),
                    onTap: disabled ? null : _submit,
                    child: SizedBox(
                      height: 48,
                      width: 48,
                      child: _isSending
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.onPrimary),
                              ),
                            )
                          : Icon(Icons.send_rounded, color: theme.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of staged-attachment chips with a remove (x) button.
class _StagedChips extends StatelessWidget {
  const _StagedChips({
    required this.attachments,
    required this.uploading,
    required this.theme,
    required this.onRemove,
  });

  final List<ChatlyAttachment> attachments;
  final bool uploading;
  final ChatlyTheme theme;
  final ValueChanged<ChatlyAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (uploading)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(theme.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Uploading…',
                      style: TextStyle(
                          color: theme.foreground, fontSize: 12)),
                ],
              ),
            ),
          for (final a in attachments)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding:
                  const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.isImage ? Icons.image : Icons.insert_drive_file,
                      size: 14, color: theme.mutedForeground),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      a.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.foreground, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onRemove(a),
                    icon: Icon(Icons.close,
                        size: 14, color: theme.mutedForeground),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
