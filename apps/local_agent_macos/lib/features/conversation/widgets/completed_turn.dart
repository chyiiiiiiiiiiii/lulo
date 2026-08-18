import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/generated/app_localizations.dart';

/// How much of a turn bubble's colour covers the glass beneath it.
///
/// An assistant bubble is wide enough to fill the window, and painted opaque
/// it took the frosted glass back out over most of the surface. Stacked on
/// `conversationSurfaceOpacity`, so behind a bubble the desktop is dimmer,
/// not gone.
const double turnBubbleOpacity = 0.55;

/// A terminal user or assistant turn.
final class CompletedTurn extends StatefulWidget {
  /// Creates a terminal turn presentation.
  const CompletedTurn({
    required this.turn,
    this.onRegenerate,
    this.onRevise,
    this.onSpeak,
    super.key,
  });

  /// Reads this answer aloud, or null where there is no voice to read it.
  ///
  /// Typed answers are not spoken by default — the mode of the answer
  /// follows the mode of the ask, and an answer written to be read has
  /// lists and structure that do not want reciting. But hearing one should
  /// never mean turning the microphone on and asking the question again.
  final ValueChanged<String>? onSpeak;

  /// Asks this answer to be produced again, or null where it cannot be.
  ///
  /// Only the newest answer carries this: replacing one in the middle would
  /// leave every answer after it standing on a question that no longer got
  /// that reply.
  final VoidCallback? onRegenerate;

  /// Asks this question again as the given text, or null where it cannot be.
  final ValueChanged<String>? onRevise;

  /// How long the turn says it has been copied.
  ///
  /// Long enough to be read by someone whose eyes were on the text they just
  /// took, short enough that it is gone before it becomes part of the answer.
  static const Duration copiedNoticeDuration = Duration(milliseconds: 1600);

  /// The turn to present.
  final Turn turn;

  @override
  State<CompletedTurn> createState() => _CompletedTurnState();
}

final class _CompletedTurnState extends State<CompletedTurn> {
  Timer? _copiedNotice;
  bool _copied = false;
  TextEditingController? _revision;

  @override
  void dispose() {
    _copiedNotice?.cancel();
    _revision?.dispose();
    super.dispose();
  }

  void _beginRevision() {
    setState(() {
      _revision = TextEditingController(text: widget.turn.text)
        ..selection = TextSelection.collapsed(offset: widget.turn.text.length);
    });
  }

  void _endRevision() {
    final TextEditingController? revision = _revision;
    setState(() => _revision = null);
    revision?.dispose();
  }

  void _submitRevision() {
    final String text = _revision?.text.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    final ValueChanged<String>? onRevise = widget.onRevise;
    _endRevision();
    onRevise?.call(text);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.turn.text));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _copiedNotice?.cancel();
    _copiedNotice = Timer(CompletedTurn.copiedNoticeDuration, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    final Turn turn = widget.turn;
    final bool isUser = turn.role == TurnRole.user;
    final String? statusLabel = switch (turn.status) {
      TurnStatus.failed => words.turnFailed,
      TurnStatus.cancelled => words.turnStopped,
      TurnStatus.interrupted => words.turnInterrupted,
      TurnStatus.completed || TurnStatus.streaming => null,
    };
    return Semantics(
      label: isUser ? words.roleYou : words.roleAssistant,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              constraints: const BoxConstraints(maxWidth: 720),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    (isUser
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest)
                        .withValues(alpha: turnBubbleOpacity),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_revision != null)
                    _Revision(
                      controller: _revision!,
                      onSubmit: _submitRevision,
                      onCancel: _endRevision,
                    )
                  else if (isUser)
                    SelectableText(turn.text)
                  else
                    TerminalMarkdown(turn.text),
                  if (HeardConfidence.isDoubtful(
                    turn.voiceInput?.heardConfidence,
                  ))
                    _HeardDoubt(score: turn.voiceInput!.heardConfidence!),
                  if (statusLabel != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      statusLabel,
                      key: const Key('turn-status'),
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
            if (_revision == null)
              _TurnActions(
                copied: _copied,
                onCopy: _copy,
                onRegenerate: widget.onRegenerate,
                onRevise: widget.onRevise == null ? null : _beginRevision,
                // Never on the user's own turn: reading them back their own
                // words is the one thing this must not offer.
                onSpeak: widget.onSpeak == null || isUser
                    ? null
                    : () => widget.onSpeak!(turn.text),
              ),
          ],
        ),
      ),
    );
  }
}

/// What can be done with a turn, under the turn.
///
/// Quiet by default and brighter under the pointer: this sits beneath every
/// turn in the scrollback, so at full contrast it would be a row of buttons
/// competing with the conversation itself. It stays in the tree rather than
/// appearing on hover, because a control that only exists while the mouse is
/// over it does not exist at all for VoiceOver or the keyboard.
final class _TurnActions extends StatefulWidget {
  const _TurnActions({
    required this.copied,
    required this.onCopy,
    this.onRegenerate,
    this.onRevise,
    this.onSpeak,
  });

  final bool copied;
  final Future<void> Function() onCopy;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRevise;
  final VoidCallback? onSpeak;

  @override
  State<_TurnActions> createState() => _TurnActionsState();
}

final class _TurnActionsState extends State<_TurnActions> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations words = AppLocalizations.of(context);
    Widget action(String key, String tooltip, IconData icon, VoidCallback go) {
      return IconButton(
        key: Key(key),
        tooltip: tooltip,
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        color: colors.onSurfaceVariant,
        icon: Icon(icon),
        onPressed: go,
      );
    }

    final VoidCallback? onRegenerate = widget.onRegenerate;
    final VoidCallback? onRevise = widget.onRevise;
    final VoidCallback? onSpeak = widget.onSpeak;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: _hovered || widget.copied ? 1 : 0.35,
        duration: const Duration(milliseconds: 140),
        child: Padding(
          padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              action(
                'turn-copy-button',
                words.copyTooltip,
                Icons.copy_rounded,
                () => unawaited(widget.onCopy()),
              ),
              if (onRegenerate != null)
                action(
                  'turn-regenerate-button',
                  words.regenerateTooltip,
                  Icons.refresh_rounded,
                  onRegenerate,
                ),
              if (onRevise != null)
                action(
                  'turn-revise-button',
                  words.reviseTooltip,
                  Icons.edit_outlined,
                  onRevise,
                ),
              if (onSpeak != null)
                action(
                  'turn-speak',
                  words.speakTooltip,
                  Icons.volume_up_rounded,
                  onSpeak,
                ),
              if (widget.copied)
                Padding(
                  key: const Key('turn-copied'),
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    words.copiedNotice,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colors.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A question being rewritten, in the place the question was.
///
/// Edited where it sits rather than sent back to the composer: the composer
/// is where a new question is written, and a user watching their words appear
/// down there has been given no reason to believe the one up here is going
/// away. Escape backs out, because that is what Escape does everywhere else
/// in this app.
final class _Revision extends StatelessWidget {
  const _Revision({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): onCancel,
          },
          child: TextField(
            key: const Key('turn-revise-field'),
            controller: controller,
            autofocus: true,
            maxLines: null,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (String _) => onSubmit(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(
              key: const Key('turn-revise-cancel'),
              onPressed: onCancel,
              child: Text(AppLocalizations.of(context).reviseCancel),
            ),
            const SizedBox(width: 4),
            // Filled rather than tonal: this sits inside the question's own
            // container, and a tonal button there is the same colour as the
            // bubble behind it.
            FilledButton(
              key: const Key('turn-revise-submit'),
              onPressed: onSubmit,
              child: Text(AppLocalizations.of(context).reviseSubmit),
            ),
          ],
        ),
      ],
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
    final AppLocalizations words = AppLocalizations.of(context);
    return Tooltip(
      message: words.heardDoubtTooltip(
        score.toStringAsFixed(2),
        HeardConfidence.trusted.toStringAsFixed(2),
      ),
      child: Padding(
        key: const Key('heard-doubt'),
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.graphic_eq, size: 13, color: colour),
            const SizedBox(width: 5),
            Text(
              words.heardDoubtLabel,
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

  /// A line that is a Markdown heading: hashes, a space, then words.
  ///
  /// The space is load-bearing — 「C# 和 F#」 is content, not a heading —
  /// and the match is anchored per line because headings arrive on their
  /// own lines inside a paragraph block as often as between blocks.
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*)$', multiLine: true);

  /// A line that is a list item: a dash or a number, a space, then words.
  ///
  /// The space is load-bearing here too — 「-5 度」 is a temperature.
  static final RegExp _listItem = RegExp(r'^\s*(?:[-*•]|(\d{1,2}[.)]))\s+');

  /// Reading rhythm for the answer's body.
  ///
  /// CJK needs more leading than the theme's default or the lines sit on
  /// each other's shoulders; this is the 1.5–1.7 every reading surface
  /// converged on.
  static TextStyle? _body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55);

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
      // The model is told not to write Markdown and a 4B model sometimes
      // does anyway. The instruction cannot make that certain; this layer
      // can — a heading is shown as its words, set apart by weight, never
      // as its syntax.
      final RegExpMatch? heading =
          _heading.matchAsPrefix(trimmed) as RegExpMatch?;
      if (heading != null && !trimmed.contains('\n')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: SelectableText.rich(
              TextSpan(
                style: Theme.of(context).textTheme.titleSmall,
                children: _emphasisSpans(heading.group(1)!.trim()),
              ),
            ),
          ),
        );
        continue;
      }
      if (_appendListBlock(blocks, trimmed, context)) {
        continue;
      }
      blocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SelectableText.rich(
            TextSpan(
              style: _body(context),
              children: _spansStrippingHeadings(trimmed),
            ),
          ),
        ),
      );
    }
  }

  /// Renders a block whose lines are all list items, or says it is not one.
  ///
  /// Each item gets a bullet gutter and a hanging indent, so a wrapped
  /// line aligns under its own first character instead of crashing into
  /// the margin. A block where any line is not an item is left to the
  /// paragraph path whole — half-list half-prose is prose.
  static bool _appendListBlock(
    List<Widget> blocks,
    String paragraph,
    BuildContext context,
  ) {
    final List<String> lines = paragraph.split('\n');
    if (lines.length < 2 &&
        _listItem.matchAsPrefix(lines.first.trim()) == null) {
      return false;
    }
    final List<({String marker, String text})> items =
        <({String marker, String text})>[];
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final Match? match = _listItem.matchAsPrefix(trimmed);
      if (match == null) {
        return false;
      }
      items.add((
        marker: match.group(1) ?? '•',
        text: trimmed.substring(match.end),
      ));
    }
    if (items.isEmpty) {
      return false;
    }
    final TextStyle? style = _body(context);
    blocks.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (int index, ({String marker, String text}) item)
                in items.indexed)
              Padding(
                key: Key('markdown-list-item-$index'),
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      child: Text(
                        item.marker,
                        style: style?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText.rich(
                        TextSpan(
                          style: style,
                          children: _emphasisSpans(item.text),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return true;
  }

  /// Emphasis spans, with any heading line inside the paragraph shown as
  /// its words rather than its hashes.
  static List<InlineSpan> _spansStrippingHeadings(String text) {
    return _emphasisSpans(
      text.replaceAllMapped(_heading, (Match match) => match.group(1)!),
    );
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
