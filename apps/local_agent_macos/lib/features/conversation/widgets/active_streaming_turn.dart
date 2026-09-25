import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'completed_turn.dart';
import 'streaming_markdown.dart';
import 'turn_reveal.dart';

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
              // ChunUI's stagger step: the answer follows its question in
              // rather than arriving on top of it.
              child: TurnReveal(
                play: true,
                delay: const Duration(milliseconds: 70),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    // The completed bubble's glass, for the same hand-off
                    // reason as the renderer below.
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: turnBubbleOpacity),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  // The same renderer the completed bubble uses. A raw-text
                  // stream showed paragraph breaks as full blank lines, and
                  // the bubble visibly shrank the moment completion swapped
                  // in the block renderer with its tighter spacing — the
                  // same layout for both is what makes the hand-off
                  // invisible. Streaming reaches it through
                  // StreamingMarkdown, which lays out identically and leaves
                  // the paragraphs that have already settled alone.
                  child: KeyedSubtree(
                    key: const Key('active-streaming-markdown'),
                    child: turn.text.isEmpty
                        ? _ThinkingShimmer(
                            child: StreamingMarkdown(
                              AppLocalizations.of(context).thinkingPlaceholder,
                            ),
                          )
                        : StreamingMarkdown(turn.text),
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

/// The placeholder while nothing has been written, with a light passing
/// through its words.
///
/// A first answer takes 1.6 s to its first word and a look at the screen
/// 5.7 s, and a still line of text for that long reads as stuck. The sweep
/// is ChunUI's skeleton shimmer (MIT, github.com/liseami/ChunUI) set into
/// the words. It ticks only while it is on screen, ends with the first word,
/// and is not drawn at all when the system asks for reduced motion.
final class _ThinkingShimmer extends StatefulWidget {
  const _ThinkingShimmer({required this.child});

  final Widget child;

  @override
  State<_ThinkingShimmer> createState() => _ThinkingShimmerState();
}

final class _ThinkingShimmerState extends State<_ThinkingShimmer>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 1600);

  /// Half the width of the band of light.
  static const double _band = 40;

  /// How far the light travels. The placeholder is laid out the full width
  /// of the bubble so the hand-off to the first word cannot move it; a sweep
  /// across all of that would spend most of its time lighting nothing.
  static const double _travel = 100;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    // Dimmed, because in the dark scheme the accent and the muted text are
    // nearly the same brightness, and a light that only changes hue is a
    // light nobody sees pass.
    final Color resting = colors.onSurfaceVariant.withValues(alpha: 0.5);
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double centre = -_band + (_travel + 2 * _band) * _sweep.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) =>
              LinearGradient(
                colors: <Color>[resting, colors.primary, resting],
              ).createShader(
                Rect.fromLTWH(centre - _band, 0, 2 * _band, bounds.height),
              ),
          child: child,
        );
      },
    );
  }
}
