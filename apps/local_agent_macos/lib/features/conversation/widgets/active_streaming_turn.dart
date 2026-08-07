import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'completed_turn.dart';

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
            label: AppLocalizations.of(context).answering,
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
                // The same renderer the completed bubble uses. A raw-text
                // stream showed paragraph breaks as full blank lines, and
                // the bubble visibly shrank the moment completion swapped
                // in the block renderer with its tighter spacing — the
                // same layout for both is what makes the hand-off
                // invisible.
                child: KeyedSubtree(
                  key: const Key('active-streaming-markdown'),
                  child: TerminalMarkdown(
                    turn.text.isEmpty
                        ? AppLocalizations.of(context).thinkingPlaceholder
                        : turn.text,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
