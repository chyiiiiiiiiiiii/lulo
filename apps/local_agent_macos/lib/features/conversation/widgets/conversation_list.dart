import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'active_streaming_turn.dart';
import 'completed_turn.dart';

/// Scrollable terminal history plus an independently listening active turn.
final class ConversationList extends StatefulWidget {
  /// Creates conversation history.
  const ConversationList({
    required this.completedTurns,
    required this.activeTurn,
    this.onBuild,
    this.onCompletedTurnsBuild,
    this.onActiveTurnBuild,
    super.key,
  });

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
  final ScrollController _scrollController = ScrollController();

  /// How far from the end still counts as being at the newest answer.
  ///
  /// Streaming moves the end while the user is reading it, and demanding an
  /// exact landing would drop the follow on any frame that arrives mid-scroll.
  static const double _bottomTolerance = 24;

  /// Whether the newest answer is what the user is looking at.
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    widget.completedTurns.addListener(_followNewContent);
    widget.activeTurn.addListener(_followNewContent);
    _scrollController.addListener(_watchPosition);
  }

  /// Follows the newest answer only while the user is already reading it.
  ///
  /// Scrolling back is a deliberate act, so an answer that arrives afterwards
  /// must not drag the view away from whatever is being read.
  void _watchPosition() {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    final bool atBottom =
        position.pixels >= position.maxScrollExtent - _bottomTolerance;
    if (atBottom == _atBottom) {
      return;
    }
    setState(() => _atBottom = atBottom);
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
    if (!_atBottom) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_atBottom || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          children: <Widget>[
            _scrollSurface(constraints),
            // Only offered when it is needed: while the newest answer is on
            // screen there is nothing to go back to.
            if (!_atBottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
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
              return Column(
                children: <Widget>[
                  for (final Turn turn in turns) CompletedTurn(turn: turn),
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
      label: 'Jump to the newest message',
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
          'Start a conversation',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Private, fast, and ready on this Mac.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
