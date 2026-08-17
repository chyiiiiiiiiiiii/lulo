import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../voice/voice_conversation_controller.dart';
import 'conversation_content_column.dart';

/// Desktop-first prompt composer that owns all of its UI controllers.
///
/// Drawn as a floating glass card: a dark translucent frame over the
/// conversation, which scrolls beneath it. The field sits on the glass with
/// no frame of its own, and the controls live on a row below it — the mic on
/// the left, the look and the send on the right, the send as the one filled
/// accent on the card.
final class ConversationComposer extends StatefulWidget {
  /// Creates a desktop prompt composer.
  const ConversationComposer({
    required this.canSubmit,
    required this.onSubmit,
    required this.onStop,
    this.voice,
    this.onBuild,
    this.seed,
    this.onLook,
    super.key,
  });

  /// Whether a new prompt may be submitted.
  final ValueListenable<bool> canSubmit;

  /// Text handed in from outside the window, or null where nothing does.
  ///
  /// A selection sent from another app's Services menu. It lands in the
  /// field rather than being sent, because a selection is not a question.
  ///
  /// A stream rather than a listenable, and both reasons are bugs this
  /// replaced. A `ValueNotifier` suppresses a write equal to what it already
  /// holds, so invoking the service twice on the same paragraph did nothing
  /// the second time; and it still held that value when a new conversation
  /// remounted the composer, so last week's selection reappeared in an empty
  /// field. An event happens once, when it happens.
  final Stream<String>? seed;

  /// Push-to-talk, when a voice is present and enabled: hold the button to
  /// speak, release to send, and the answer plays out uninterrupted.
  final VoiceConversationController? voice;

  /// Called with a normalized non-empty prompt.
  final ValueChanged<String> onSubmit;

  /// The invited look: called with whatever is in the field — possibly
  /// nothing — when the user asks Lulo to look at their screen. Null hides
  /// the button, for surfaces with no screen behind them.
  final ValueChanged<String>? onLook;

  /// Called when the active response should stop.
  final Future<void> Function() onStop;

  /// Optional render instrumentation used by tests.
  final VoidCallback? onBuild;

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

final class _ConversationComposerState extends State<ConversationComposer> {
  final TextEditingController _controller = TextEditingController();
  StreamSubscription<String>? _seed;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Conversation composer');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _seed = widget.seed?.listen(_takeSeed);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _refresh() => setState(() {});

  /// Puts text handed in from outside into the field, without sending it.
  ///
  /// Not submitted. What arrives from another app's Services menu is a
  /// selection, and a selection is not a question — the user still has to
  /// say what they want done with it. Appended rather than replacing, so a
  /// second send does not silently discard what they were part-way through
  /// typing.
  void _takeSeed(String text) {
    if (text.isEmpty) {
      return;
    }
    final String existing = _controller.text;
    _controller.text = existing.isEmpty ? text : '$existing\n\n$text';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _submit() {
    final String prompt = _controller.text.trim();
    if (prompt.isEmpty || !widget.canSubmit.value) {
      return;
    }
    widget.onSubmit(prompt);
    _controller.clear();
    _focusNode.requestFocus();
  }

  /// Sends the field — empty is allowed, a look is its own question — to
  /// whoever takes the screenshot.
  void _look() {
    if (!widget.canSubmit.value) {
      return;
    }
    widget.onLook?.call(_controller.text.trim());
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
    unawaited(_seed?.cancel());
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
        final ThemeData theme = Theme.of(context);
        final ColorScheme colors = theme.colorScheme;
        final bool dark = theme.brightness == Brightness.dark;
        final AppLocalizations words = AppLocalizations.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            conversationContentMargin,
            8,
            conversationContentMargin,
            16,
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
              // The shadow lives outside the clip — a translucent card
              // cannot cast one from inside its own glass.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.32 : 0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      key: const Key('conversation-composer-glass'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: dark
                            ? colors.surfaceContainerHigh.withValues(
                                alpha: 0.62,
                              )
                            : colors.surface.withValues(alpha: 0.72),
                        border: Border.all(
                          color: dark
                              ? Colors.white.withValues(alpha: 0.09)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            key: const Key('conversation-composer-field'),
                            controller: _controller,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            style: theme.textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: words.composerHint,
                              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              // The card is the frame; a second one inside
                              // it would be a box in a box.
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                6,
                              ),
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              if (widget.voice != null)
                                _HoldToTalkButton(voice: widget.voice!),
                              const Spacer(),
                              if (canSubmit) ...<Widget>[
                                if (widget.onLook != null)
                                  IconButton(
                                    key: const Key('conversation-look-button'),
                                    tooltip: words.lookAtScreenTooltip,
                                    onPressed: _look,
                                    style: _ghostButton(colors),
                                    icon: const Icon(
                                      Icons.remove_red_eye_outlined,
                                      size: 19,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                IconButton(
                                  key: const Key('conversation-submit-button'),
                                  tooltip: words.sendTooltip,
                                  onPressed: _controller.text.trim().isEmpty
                                      ? null
                                      : _submit,
                                  style: _accentButton(colors),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                  ),
                                ),
                              ] else
                                IconButton(
                                  key: const Key('conversation-stop-button'),
                                  tooltip: words.stopAnswerTooltip,
                                  onPressed: _stop,
                                  style: _accentButton(colors),
                                  icon: const Icon(
                                    Icons.stop_rounded,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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

  /// The one filled control on the card: send while writing, stop while
  /// an answer streams. Disabled it recedes into the glass instead of
  /// greying out into a second visual language.
  static ButtonStyle _accentButton(ColorScheme colors) {
    return IconButton.styleFrom(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.08),
      disabledForegroundColor: colors.onSurface.withValues(alpha: 0.35),
      minimumSize: const Size(34, 34),
      maximumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
    );
  }

  /// Quiet circular controls that only announce themselves on hover.
  static ButtonStyle _ghostButton(ColorScheme colors) {
    return IconButton.styleFrom(
      foregroundColor: colors.onSurfaceVariant,
      hoverColor: colors.onSurface.withValues(alpha: 0.08),
      minimumSize: const Size(34, 34),
      maximumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
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
        final bool held = voice.holdingToTalk;
        final ColorScheme colors = Theme.of(context).colorScheme;
        // Present in every state: an empty slot where a button sometimes
        // is reads as a rendering bug, and the button is the invitation.
        // Holding it with the voice off turns the voice on — the press is
        // the intent to talk.
        return Listener(
          key: const Key('conversation-hold-to-talk'),
          // No batch recognition behind the button: only the hotkey path
          // captures audio natively. The streamed transcript is what sends.
          onPointerDown: (_) => voice.holdToTalkPressed(),
          onPointerUp: (_) => voice.holdToTalkReleased(),
          onPointerCancel: (_) => voice.holdToTalkReleased(),
          child: Tooltip(
            message: AppLocalizations.of(context).holdToTalkHint,
            child: AnimatedScale(
              scale: held ? 1.12 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: held
                      ? colors.primary.withValues(alpha: 0.18)
                      : Colors.transparent,
                ),
                child: Icon(
                  held ? Icons.mic_rounded : Icons.mic_none_rounded,
                  size: 19,
                  color: held
                      ? colors.primary
                      : voice.enabled
                      ? colors.onSurfaceVariant
                      : colors.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
