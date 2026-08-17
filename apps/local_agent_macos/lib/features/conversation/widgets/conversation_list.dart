import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'active_streaming_turn.dart';
import 'completed_turn.dart';
import 'conversation_content_column.dart';

/// Scrollable terminal history plus an independently listening active turn.
final class ConversationList extends StatefulWidget {
  /// Creates conversation history.
  const ConversationList({
    required this.completedTurns,
    required this.activeTurn,
    this.retryAvailable,
    this.onRegenerate,
    this.onRevise,
    this.onSpeak,
    this.onBuild,
    this.onCompletedTurnsBuild,
    this.onActiveTurnBuild,
    this.bottomInset = 0,
    super.key,
  });

  /// Extra bottom padding, the measured height of whatever floats over the
  /// list's tail — the glass composer and its notices.
  ///
  /// The list scrolls under that glass on purpose; this inset is what keeps
  /// the last message able to clear it.
  final double bottomInset;

  /// Whether a retry can be started now, or null to offer none.
  ///
  /// Watched around the newest turn alone rather than the whole history: it
  /// flips at the start and the end of every generation, and the history is
  /// deliberately built once and left alone while an answer streams.
  final ValueListenable<bool>? retryAvailable;

  /// Asks the newest answer to be produced again.
  final VoidCallback? onRegenerate;

  /// Asks the newest question again, as the given text.
  final ValueChanged<String>? onRevise;

  /// Reads one answer aloud, or null where there is no voice.
  final ValueChanged<String>? onSpeak;

  /// Immutable terminal turns shown in history.
  final ValueListenable<List<Turn>> completedTurns;

  /// The independently rendered active streaming turn.
  final ValueListenable<Turn?> activeTurn;

  /// Optional list render instrumentation used by tests.
  final VoidCallback? onBuild;

  /// Optional completed-history render instrumentation used by tests.
  final VoidCallback? onCompletedTurnsBuild;

  /// Optional active-turn render instrumentation used by tests.
  final VoidCallback? onActiveTurnBuild;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

final class _ConversationListState extends State<ConversationList> {
  /// Breathing room above the first turn and below the last.
  static const double _verticalPadding = 12;

  final ScrollController _scrollController = ScrollController();

  /// How far from the end still counts as being at the newest answer.
  ///
  /// Streaming moves the end while the user is reading it, and demanding an
  /// exact landing would drop the follow on any frame that arrives mid-scroll.
  static const double _bottomTolerance = 24;

  /// Whether the newest answer is what the user is looking at.
  bool _atBottom = true;

  /// Whether the newest answer is being followed as it grows.
  ///
  /// Kept apart from [_atBottom], which only decides whether to offer the way
  /// back. Being near the bottom is not the same as wanting to be taken there:
  /// a scroll that has only just begun is still within a hair of the end, and
  /// treating that as consent is what made reading back impossible.
  bool _following = true;

  /// Whether the user currently has hold of the list.
  bool _held = false;

  /// How many completed turns have been accounted for.
  int _seenTurns = 0;

  @override
  void initState() {
    super.initState();
    widget.completedTurns.addListener(_followNewContent);
    widget.activeTurn.addListener(_followNewContent);
    _scrollController.addListener(_watchPosition);
  }

  /// Decides whether the way back to the newest answer is worth offering.
  void _watchPosition() {
    final bool atBottom = _isAtBottom();
    if (atBottom == _atBottom) {
      return;
    }
    setState(() => _atBottom = atBottom);
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final ScrollPosition position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - _bottomTolerance;
  }

  /// Follows the scroll the user is performing, rather than their position.
  ///
  /// Scrolling back towards what has already been said is a deliberate act and
  /// stops the follow the moment it starts, not once it has travelled far
  /// enough to count. Letting go at the newest answer takes it up again, which
  /// is how every chat window a Mac user already knows behaves.
  bool _watchScroll(ScrollNotification notification) {
    // Rendered turns bring scrollables of their own; only this one is the
    // conversation.
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _held = notification.dragDetails != null;
    } else if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _setFollowing(false);
      }
    } else if (notification is ScrollEndNotification) {
      _held = false;
      _setFollowing(_isAtBottom());
    }
    return false;
  }

  void _setFollowing(bool following) {
    if (_following == following) {
      return;
    }
    _following = following;
  }

  /// Returns to the newest answer, which also resumes following it.
  Future<void> _returnToBottom() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(ConversationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completedTurns != widget.completedTurns) {
      oldWidget.completedTurns.removeListener(_followNewContent);
      widget.completedTurns.addListener(_followNewContent);
    }
    if (oldWidget.activeTurn != widget.activeTurn) {
      oldWidget.activeTurn.removeListener(_followNewContent);
      widget.activeTurn.addListener(_followNewContent);
    }
  }

  @override
  void dispose() {
    widget.completedTurns.removeListener(_followNewContent);
    widget.activeTurn.removeListener(_followNewContent);
    _scrollController.removeListener(_watchPosition);
    _scrollController.dispose();
    super.dispose();
  }

  /// Keeps the newest content in view as the answer grows.
  ///
  /// Deferred to after the frame because the content that just arrived has no
  /// height until it has been laid out, so the distance to scroll does not
  /// exist yet while this is being notified.
  void _followNewContent() {
    _resumeIfTheUserJustSpoke();
    // Never while the list is being held: a jump ends the scroll the user is
    // performing, and answers arrive often enough that every attempt to read
    // back would be ended in turn.
    if (!_following || _held) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_following || _held || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Sending something is asking to see it, so it takes the follow up again.
  void _resumeIfTheUserJustSpoke() {
    final List<Turn> turns = widget.completedTurns.value;
    if (turns.length <= _seenTurns) {
      _seenTurns = turns.length;
      return;
    }
    final bool spoke = turns
        .skip(_seenTurns)
        .any((Turn turn) => turn.role == TurnRole.user);
    _seenTurns = turns.length;
    if (spoke) {
      _setFollowing(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          children: <Widget>[
            NotificationListener<ScrollNotification>(
              onNotification: _watchScroll,
              child: _scrollSurface(constraints),
            ),
            // Only offered when it is needed: while the newest answer is on
            // screen there is nothing to go back to.
            if (!_atBottom)
              Positioned(
                left: 0,
                right: 0,
                // Above the glass, not under it.
                bottom: 16 + widget.bottomInset,
                child: Center(
                  child: _ScrollToBottomButton(onPressed: _returnToBottom),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _scrollSurface(BoxConstraints constraints) {
    return SingleChildScrollView(
      key: const Key('conversation-scroll-surface'),
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        conversationContentMargin,
        _verticalPadding,
        conversationContentMargin,
        _verticalPadding + widget.bottomInset,
      ),
      // The turns live in the same centred column as the header and the
      // composer, so a message's edge lines up with both at any window size.
      child: ConversationContentColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ValueListenableBuilder<List<Turn>>(
              valueListenable: widget.completedTurns,
              builder: (BuildContext context, List<Turn> turns, Widget? child) {
                widget.onCompletedTurnsBuild?.call();
                if (turns.isEmpty) {
                  return SizedBox(
                    height: (constraints.maxHeight - 40).clamp(
                      0,
                      double.infinity,
                    ),
                    child: const _EmptyConversation(),
                  );
                }
                // Only the newest exchange can be retried: replacing an answer
                // in the middle would leave every answer after it standing on
                // a question that never got that reply.
                final int newestQuestion = turns.lastIndexWhere(
                  (Turn turn) => turn.role == TurnRole.user,
                );
                final int newestAnswer = turns.last.role == TurnRole.assistant
                    ? turns.length - 1
                    : -1;
                return Column(
                  children: <Widget>[
                    for (int index = 0; index < turns.length; index++)
                      _retryable(
                        turn: turns[index],
                        regenerate: index == newestAnswer,
                        revise: index == newestQuestion,
                      ),
                  ],
                );
              },
            ),
            ActiveStreamingTurn(
              activeTurn: widget.activeTurn,
              onBuild: widget.onActiveTurnBuild,
            ),
          ],
        ),
      ),
    );
  }
}

/// One turn, with whichever retries it is the right turn for.
///
/// A turn that offers none is built plainly, so the listenable that gates the
/// retries cannot rebuild the history behind it.
extension on _ConversationListState {
  Widget _retryable({
    required Turn turn,
    required bool regenerate,
    required bool revise,
  }) {
    final ValueListenable<bool>? available = widget.retryAvailable;
    final VoidCallback? onRegenerate = regenerate ? widget.onRegenerate : null;
    final ValueChanged<String>? onRevise = revise ? widget.onRevise : null;
    if (available == null || (onRegenerate == null && onRevise == null)) {
      return CompletedTurn(turn: turn, onSpeak: widget.onSpeak);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: available,
      builder: (BuildContext context, bool ready, Widget? child) =>
          CompletedTurn(
            turn: turn,
            onRegenerate: ready ? onRegenerate : null,
            onRevise: ready ? onRevise : null,
            onSpeak: widget.onSpeak,
          ),
    );
  }
}

/// The way back to the newest answer, offered only while it is off screen.
final class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).jumpToNewest,
      child: Material(
        key: const Key('conversation-scroll-to-bottom'),
        color: colors.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(onPressed()),
          child: SizedBox.square(
            dimension: 34,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

final class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('conversation-empty'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.auto_awesome_rounded,
          size: 34,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(
          AppLocalizations.of(context).conversationEmptyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context).conversationEmptyNote,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
