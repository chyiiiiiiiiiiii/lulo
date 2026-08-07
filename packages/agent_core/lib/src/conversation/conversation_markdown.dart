import '../voice/heard_confidence.dart';
import 'turn.dart';

/// The words an exported conversation is labelled with.
///
/// Passed in rather than chosen here: `agent_core` has no Flutter and no
/// localizations, and a file the user keeps should be written in the language
/// they read the app in.
final class ConversationLabels {
  /// Creates the labels one exported conversation is written with.
  const ConversationLabels({
    required this.user,
    required this.assistant,
    required this.interrupted,
    required this.stopped,
    required this.failed,
    required this.doubted,
  });

  /// What the user's own turns are called.
  final String user;

  /// What the agent's turns are called.
  final String assistant;

  /// Noted beside an answer the process died in the middle of.
  final String interrupted;

  /// Noted beside an answer the user stopped.
  final String stopped;

  /// Noted beside an answer that failed.
  final String failed;

  /// Noted beside a spoken turn the recogniser was not sure it heard.
  final String doubted;
}

/// Renders one conversation as a Markdown document.
///
/// Pure, so that what leaves the machine is decided by something a test can
/// read rather than by a widget. A turn that did not finish says so: an
/// export that quietly tidied those up would be a nicer conversation than the
/// one the user actually had.
String conversationToMarkdown({
  required String title,
  required List<Turn> turns,
  required ConversationLabels labels,
}) {
  final StringBuffer out = StringBuffer()..writeln('# ${_oneLine(title)}');
  for (final Turn turn in turns) {
    final String who = turn.role == TurnRole.user
        ? labels.user
        : labels.assistant;
    final List<String> notes = <String>[
      ?switch (turn.status) {
        TurnStatus.interrupted => labels.interrupted,
        TurnStatus.cancelled => labels.stopped,
        TurnStatus.failed => labels.failed,
        TurnStatus.completed || TurnStatus.streaming => null,
      },
      // The screen captions a turn the recogniser was unsure of rather than
      // showing it as certain, and a file that dropped the caveat would
      // present a guess as a quotation.
      if (HeardConfidence.isDoubtful(turn.voiceInput?.heardConfidence))
        '${labels.doubted} '
            '(${turn.voiceInput!.heardConfidence!.toStringAsFixed(2)})',
    ];
    out
      ..writeln()
      ..writeln(notes.isEmpty ? '**$who**' : '**$who** *(${notes.join('; ')})*')
      ..writeln()
      ..writeln(_quarantined(turn.text, labels));
  }
  return out.toString();
}

/// Collapses [value] onto one line so a heading stays a heading.
String _oneLine(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Stops an answer from corrupting the document around it.
///
/// This file is the user's only copy, so an answer that renders as something
/// other than what was said is data loss. Three ordinary things a model
/// writes would do that, and all three are neutralised here rather than
/// hoped about:
///
/// * A line that looks like a turn header — `**Lulo**`, with or without the
///   up-to-three leading spaces CommonMark still reads as a paragraph — makes
///   the export look as though somebody said something they did not.
/// * An unclosed code fence swallows every later turn into one code block.
///   Routine for an interrupted answer, which this renderer deliberately
///   exports.
/// * An unclosed HTML comment starts a block that a blank line does not end,
///   and everything after it disappears from the rendered document.
///
/// Each is repaired by the smallest edit that breaks the construct while
/// leaving the text readable: a zero-width space inside the marker.
String _quarantined(String text, ConversationLabels labels) {
  String safe = text.trimRight();
  for (final String who in <String>[labels.user, labels.assistant]) {
    safe = safe.replaceAllMapped(
      RegExp('^( *)\\*\\*${RegExp.escape(who)}\\*\\*', multiLine: true),
      (Match match) => '${match[1]}*\u200b*$who*\u200b*',
    );
  }
  if (_fences.allMatches(safe).length.isOdd) {
    safe = '$safe\n```';
  }
  // Only the opener needs breaking: a comment that is closed is harmless, and
  // one that is not can no longer start.
  if (safe.contains('<!--') && !safe.contains('-->')) {
    safe = safe.replaceAll('<!--', '<!\u200b--');
  }
  return safe;
}

/// A fence at the start of a line, which is the only place one counts.
final RegExp _fences = RegExp(r'^ {0,3}(?:`{3,}|~{3,})', multiLine: true);
