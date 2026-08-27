import 'package:flutter/material.dart';

import 'completed_turn.dart';

/// The answer while it is still being written: what has settled, and the tail.
///
/// [TerminalMarkdown] parses and rebuilds its whole source, which is right
/// once but wrong a hundred times a second. Measured in a widget test, one
/// rebuild of a 1118-character answer cost **7.9 ms** — the entire 120 fps
/// frame — and grew with every paragraph, while the parse itself was 50 µs of
/// it. The cost is rebuilding paragraphs that are already finished: a token
/// only ever changes the last one.
///
/// So the source is split at the last paragraph break and the settled half is
/// held as **the same widget instance** across rebuilds. Flutter skips an
/// identical child outright, so those paragraphs are not rebuilt, not laid out
/// again, and — behind their own repaint boundary — not repainted. What is
/// left is the tail, whose cost does not grow with the answer.
///
/// Two stacked columns of blocks lay out exactly as one, so nothing about the
/// hand-off to [TerminalMarkdown] at completion is visible.
final class StreamingMarkdown extends StatefulWidget {
  /// Renders [source] as an answer that is still arriving.
  const StreamingMarkdown(this.source, {this.onSettledBuild, super.key});

  /// The answer so far.
  final String source;

  /// Optional test instrumentation, called when the settled half is rebuilt.
  final VoidCallback? onSettledBuild;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

final class _StreamingMarkdownState extends State<StreamingMarkdown> {
  /// The source of [_settled], to tell a new settlement from a longer tail.
  String? _settledSource;

  /// The settled paragraphs, kept by identity so Flutter can skip them.
  Widget? _settled;

  @override
  Widget build(BuildContext context) {
    final int split = settlementPoint(widget.source);
    final String settledSource = widget.source.substring(0, split);
    if (settledSource != _settledSource) {
      _settledSource = settledSource;
      _settled = settledSource.isEmpty
          ? null
          : RepaintBoundary(child: TerminalMarkdown(settledSource));
      widget.onSettledBuild?.call();
    }
    final String tail = widget.source.substring(split);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_settled case final Widget settled) settled,
        if (tail.isNotEmpty) TerminalMarkdown(tail),
      ],
    );
  }
}

/// A blank line, which is where one block of Markdown ends and the next opens.
final RegExp _paragraphBreak = RegExp(r'\n[ \t]*\n');

/// The offset up to which [source] can no longer change as more arrives.
///
/// The last paragraph break, except that a break inside an unclosed code fence
/// is not one: the fence pattern reaches across blank lines, so settling
/// inside it would render half a code block as prose — and then put it back
/// together at completion, which is exactly the visible hand-off this is
/// meant to avoid. Walking back to an earlier break costs a little more of the
/// answer being live and cannot be wrong.
@visibleForTesting
int settlementPoint(String source) {
  for (final RegExpMatch match
      in _paragraphBreak.allMatches(source).toList().reversed) {
    if (!_insideFence(source, match.end)) {
      return match.end;
    }
  }
  return 0;
}

bool _insideFence(String source, int end) {
  int fences = 0;
  int at = source.indexOf('```');
  while (at >= 0 && at < end) {
    fences += 1;
    at = source.indexOf('```', at + 3);
  }
  return fences.isOdd;
}
