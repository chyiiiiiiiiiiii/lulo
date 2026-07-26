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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          key: const Key('conversation-scroll-surface'),
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<List<Turn>>(
                valueListenable: widget.completedTurns,
                builder:
                    (BuildContext context, List<Turn> turns, Widget? child) {
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
                          for (final Turn turn in turns)
                            CompletedTurn(turn: turn),
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
      },
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
