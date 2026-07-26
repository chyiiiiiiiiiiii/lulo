import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

/// A terminal user or assistant turn.
final class CompletedTurn extends StatelessWidget {
  /// Creates a terminal turn presentation.
  const CompletedTurn({required this.turn, super.key});

  /// The turn to present.
  final Turn turn;

  @override
  Widget build(BuildContext context) {
    final bool isUser = turn.role == TurnRole.user;
    final String? statusLabel = switch (turn.status) {
      TurnStatus.failed => 'Response failed',
      TurnStatus.cancelled => 'Response stopped',
      TurnStatus.completed || TurnStatus.streaming => null,
    };
    return Semantics(
      label: isUser ? 'You' : 'Assistant',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(turn.text),
              if (statusLabel != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: turn.status == TurnStatus.failed
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
