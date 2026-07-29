import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop-first prompt composer that owns all of its UI controllers.
final class ConversationComposer extends StatefulWidget {
  /// Creates a desktop prompt composer.
  const ConversationComposer({
    required this.canSubmit,
    required this.onSubmit,
    required this.onStop,
    this.onBuild,
    super.key,
  });

  /// Whether a new prompt may be submitted.
  final ValueListenable<bool> canSubmit;

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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter): _submit,
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      _insertNewline,
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
          ),
        );
      },
    );
  }
}
