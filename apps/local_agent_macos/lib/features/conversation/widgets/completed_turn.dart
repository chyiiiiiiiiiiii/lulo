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
      TurnStatus.interrupted => 'Response interrupted',
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
              if (isUser)
                SelectableText(turn.text)
              else
                TerminalMarkdown(turn.text),
              if (HeardConfidence.isDoubtful(turn.voiceInput?.heardConfidence))
                _HeardDoubt(score: turn.voiceInput!.heardConfidence!),
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

/// The caveat on a sentence the recogniser was not sure it heard.
///
/// Small and quiet on purpose. It is not an error — the sentence may well
/// be right — it is the one piece of information that turns "the agent is
/// stupid" into "it misheard that word", which is a thing the user can
/// actually do something about.
final class _HeardDoubt extends StatelessWidget {
  const _HeardDoubt({required this.score});

  /// The weakest span's confidence, shown so the user can calibrate the
  /// threshold against their own voice rather than take it on trust.
  final double score;

  @override
  Widget build(BuildContext context) {
    final Color colour = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message:
          'The weakest word scored ${score.toStringAsFixed(2)}; anything '
          'under ${HeardConfidence.trusted.toStringAsFixed(2)} is marked.',
      child: Padding(
        key: const Key('heard-doubt'),
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.graphic_eq, size: 13, color: colour),
            const SizedBox(width: 5),
            Text(
              'Not sure it heard this right',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colour),
            ),
          ],
        ),
      ),
    );
  }
}

/// SDK-only terminal Markdown presentation built once after generation ends.
///
/// Phase 1A intentionally supports the high-value subset: paragraphs, fenced
/// code blocks, and bold emphasis. Streaming text never enters this parser.
final class TerminalMarkdown extends StatelessWidget {
  /// Creates terminal Markdown from the final assistant text.
  const TerminalMarkdown(this.source, {super.key});

  /// Final assistant response.
  final String source;

  @override
  Widget build(BuildContext context) {
    final List<Widget> blocks = <Widget>[];
    final RegExp fence = RegExp(r'```[^\n]*\n([\s\S]*?)```');
    int cursor = 0;
    for (final RegExpMatch match in fence.allMatches(source)) {
      _appendParagraphs(blocks, source.substring(cursor, match.start), context);
      blocks.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            match.group(1)!.trimRight(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
      cursor = match.end;
    }
    _appendParagraphs(blocks, source.substring(cursor), context);
    return Column(
      key: const Key('terminal-markdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.isEmpty ? const <Widget>[SizedBox.shrink()] : blocks,
    );
  }

  static void _appendParagraphs(
    List<Widget> blocks,
    String text,
    BuildContext context,
  ) {
    for (final String paragraph in text.split(RegExp(r'\n\s*\n'))) {
      final String trimmed = paragraph.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      blocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: SelectableText.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: _emphasisSpans(trimmed),
            ),
          ),
        ),
      );
    }
  }

  static List<InlineSpan> _emphasisSpans(String text) {
    final List<InlineSpan> spans = <InlineSpan>[];
    final RegExp bold = RegExp(r'\*\*(.+?)\*\*');
    int cursor = 0;
    for (final RegExpMatch match in bold.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}
