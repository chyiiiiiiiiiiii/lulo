import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../voice/voice_conversation_controller.dart';
import 'conversation_content_column.dart';

/// Desktop-first prompt composer that owns all of its UI controllers.
final class ConversationComposer extends StatefulWidget {
  /// Creates a desktop prompt composer.
  const ConversationComposer({
    required this.canSubmit,
    required this.onSubmit,
    required this.onStop,
    this.voice,
    this.onBuild,
    super.key,
  });

  /// Whether a new prompt may be submitted.
  final ValueListenable<bool> canSubmit;

  /// Push-to-talk, when a voice is present and enabled: hold the button to
  /// speak, release to send, and the answer plays out uninterrupted.
  final VoiceConversationController? voice;

  /// Called with a normalized non-empty prompt.
  final ValueChanged<String> onSubmit;

  /// Called when the active response should stop.
  final Future<void> Function() onStop;

  /// Optional render instrumentation used by tests.
  final VoidCallback? onBuild;

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

final class _ConversationComposerState extends State<ConversationComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Conversation composer');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _refresh() => setState(() {});

  void _submit() {
    final String prompt = _controller.text.trim();
    if (prompt.isEmpty || !widget.canSubmit.value) {
      return;
    }
    widget.onSubmit(prompt);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _insertNewline() {
    final TextSelection selection = _controller.selection;
    final int start = selection.isValid
        ? selection.start
        : _controller.text.length;
    final int end = selection.isValid ? selection.end : start;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Future<void> _stop() async {
    await widget.onStop();
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return ValueListenableBuilder<bool>(
      valueListenable: widget.canSubmit,
      builder: (BuildContext context, bool canSubmit, Widget? child) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            conversationContentMargin,
            12,
            conversationContentMargin,
            24,
          ),
          child: ConversationContentColumn(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter): _submit,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    _insertNewline,
                // Only while an answer is streaming: with nothing to stop,
                // Escape belongs to the sheets above the conversation.
                if (!canSubmit)
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      unawaited(_stop()),
              },
              child: TextField(
                key: const Key('conversation-composer-field'),
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message Lulo',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                  prefixIcon: widget.voice == null
                      ? null
                      : _HoldToTalkButton(voice: widget.voice!),
                  suffixIcon: canSubmit
                      ? IconButton(
                          key: const Key('conversation-submit-button'),
                          tooltip: 'Send message',
                          onPressed: _controller.text.trim().isEmpty
                              ? null
                              : _submit,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        )
                      : IconButton(
                          key: const Key('conversation-stop-button'),
                          tooltip: 'Stop response',
                          onPressed: _stop,
                          icon: const Icon(Icons.stop_rounded),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Hold to speak, release to send.
///
/// While held the agent falls silent and listens; the release submits the
/// whole utterance as one question, and the answer plays out over any
/// ambient speech — the next hold is the only interruption.
final class _HoldToTalkButton extends StatelessWidget {
  const _HoldToTalkButton({required this.voice});

  final VoiceConversationController voice;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: voice,
      builder: (BuildContext context, _) {
        if (!voice.enabled) {
          return const SizedBox.shrink();
        }
        final bool held = voice.holdingToTalk;
        final ColorScheme colors = Theme.of(context).colorScheme;
        return Listener(
          key: const Key('conversation-hold-to-talk'),
          onPointerDown: (_) => voice.holdToTalkPressed(),
          onPointerUp: (_) => voice.holdToTalkReleased(),
          onPointerCancel: (_) => voice.holdToTalkReleased(),
          child: Tooltip(
            message: 'Hold to talk; release to send',
            child: Icon(
              held ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: held ? colors.primary : null,
            ),
          ),
        );
      },
    );
  }
}
