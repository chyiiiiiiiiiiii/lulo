import 'package:flutter/material.dart';

import 'voice_turn_log.dart';

/// A running account of the turn-taking rulings, for the person testing them.
///
/// The rules are all judgement calls with reasons — an acknowledgement is
/// ignored, a correction is obeyed, a half-finished sentence is given longer
/// — and every one of them used to be visible only in a console the user is
/// not looking at. Watching this while talking is how you tell "the rule
/// fired and I disagree with it" from "the rule did not fire".
///
/// Deliberately plain: it is an instrument, not a feature. It rebuilds only
/// itself, off the log rather than off the conversation, so a busy voice
/// session cannot cost the transcript a frame.
final class VoiceTurnHud extends StatelessWidget {
  /// Creates the panel over [log].
  const VoiceTurnHud({required this.log, super.key});

  /// What the voice pipeline has decided so far.
  final VoiceTurnLog log;

  /// How tall the panel is allowed to grow before it scrolls.
  static const double maxHeight = 168;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      key: const Key('voice-turn-hud'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedBuilder(
        animation: log,
        builder: (BuildContext context, Widget? _) {
          final List<VoiceTurnNote> notes = log.notes;
          if (notes.isEmpty) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Nothing heard yet. Turn-taking rulings appear here as you '
                'talk.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: EdgeInsets.zero,
            itemCount: notes.length,
            itemBuilder: (BuildContext context, int index) =>
                _Note(note: notes[notes.length - 1 - index]),
          );
        },
      ),
    );
  }
}

final class _Note extends StatelessWidget {
  const _Note({required this.note});

  final VoiceTurnNote note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color colour = switch (note.kind) {
      VoiceNoteKind.heard => theme.colorScheme.primary,
      VoiceNoteKind.ignored => theme.colorScheme.onSurfaceVariant,
      VoiceNoteKind.tookTheFloor => theme.colorScheme.error,
      VoiceNoteKind.spoke => theme.colorScheme.tertiary,
      VoiceNoteKind.cost => theme.colorScheme.secondary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              _label(note.kind),
              key: const Key('voice-note-label'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(note.text, style: theme.textTheme.labelMedium),
                if (note.detail.isNotEmpty)
                  Text(
                    note.detail,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The one word that says which ruling this was.
  ///
  /// Distinct per kind on purpose: a panel where "ignored" and "took the
  /// floor" read alike is worse than no panel, because it looks informative.
  static String _label(VoiceNoteKind kind) => switch (kind) {
    VoiceNoteKind.heard => 'asked',
    VoiceNoteKind.ignored => 'ignored',
    VoiceNoteKind.tookTheFloor => 'cut in',
    VoiceNoteKind.spoke => 'said',
    VoiceNoteKind.cost => 'cost',
  };
}
