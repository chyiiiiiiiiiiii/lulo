import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The isolated repaint and rebuild boundary for streamed output.
final class ActiveStreamingTurn extends StatelessWidget {
  /// Creates the active turn listener.
  const ActiveStreamingTurn({
    required this.activeTurn,
    this.onBuild,
    super.key,
  });

  /// Only this listenable changes for token deltas.
  final ValueListenable<Turn?> activeTurn;

  /// Optional test instrumentation.
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<Turn?>(
        valueListenable: activeTurn,
        builder: (BuildContext context, Turn? turn, Widget? child) {
          onBuild?.call();
          if (turn == null) {
            return const SizedBox.shrink();
          }
          return Semantics(
            liveRegion: true,
            label: 'Assistant is responding',
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SelectableText(
                  turn.text.isEmpty ? 'Thinking…' : turn.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
