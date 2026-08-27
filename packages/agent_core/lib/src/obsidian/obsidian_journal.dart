/// One day's page in the user's own notes, and the entries appended to it.
///
/// The point of writing into a vault at all is that the record outlives the
/// app: a year from now, with Lulo uninstalled, the questions and answers are
/// still in the user's Obsidian where the rest of their thinking is. Three
/// rules follow from that, and each one gives something up.
///
/// **Append only.** Nothing already written is ever rewritten. The file lives
/// in someone else's vault, where they may have edited it, linked to it,
/// tagged it, or written underneath it — a tool that rewrites the file
/// destroys that work, and it destroys it silently. The cost is that a
/// regenerated answer appends beside the one it replaced rather than
/// replacing it, and a rewound question stays. That is what a journal is.
///
/// **One page a day, not one a conversation.** A day is an immutable fact, so
/// the file name never has to change. A conversation's title is not: the user
/// renames it, and renaming their note behind them breaks whatever they
/// linked to it. It also means no index has to be kept anywhere of which note
/// belongs to which conversation, and therefore no index that can go stale.
///
/// **The question is the heading.** It is the only summary that costs nothing
/// and cannot be wrong.
library;

import 'package:characters/characters.dart';

/// The file one day's entries are appended to, inside the chosen folder.
///
/// Named for the day alone, in the order that sorts: this is the same shape
/// as every daily-note plugin, so the page lands where the user already looks.
String obsidianJournalFileName(DateTime day) =>
    '${_four(day.year)}-${_two(day.month)}-${_two(day.day)}.md';

/// What a day's page opens with, written once when the file is created.
///
/// The front matter is the smallest thing Obsidian's own search and Dataview
/// can act on. `source: lulo` is there so the user can find — or exclude —
/// everything this app ever wrote in one query.
String obsidianJournalHeader(DateTime day, {required String heading}) {
  final String date = '${_four(day.year)}-${_two(day.month)}-${_two(day.day)}';
  return '---\n'
      'date: $date\n'
      'source: lulo\n'
      'tags:\n'
      '  - lulo\n'
      '---\n'
      '\n'
      '# $date $heading\n';
}

/// How much of a question fits in a heading before it stops being scannable.
const int _headingLimit = 60;

/// One exchange, ready to be appended to a day's page.
///
/// The heading carries the time and the question, because that is what the
/// user will be scanning a year from now. A question too long to be a heading
/// is cut there and repeated whole underneath — cutting it and losing the
/// rest would make the page a worse record than the app it was meant to
/// outlive.
String obsidianJournalEntry({
  required DateTime at,
  required String question,
  required String answer,
}) {
  final String asked = _oneLine(question);
  final String short = _truncate(asked, _headingLimit);
  final StringBuffer entry = StringBuffer()
    ..writeln()
    ..writeln('## ${_two(at.hour)}:${_two(at.minute)} $short')
    ..writeln();
  if (short != asked) {
    entry
      ..writeln('> ${_oneLine(asked)}')
      ..writeln();
  }
  entry
    ..writeln(answer.trim())
    ..writeln();
  return entry.toString();
}

/// A heading cannot span lines, and a question asked by voice often does.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Cuts to [limit] **graphemes**, not code units.
///
/// The same reason the transcript refiner walks graphemes: counting code
/// units cuts a surrogate pair in half and leaves broken text in the user's
/// notes, and counting runes takes a combining accent off the letter it
/// belongs to.
String _truncate(String text, int limit) {
  final Characters characters = text.characters;
  if (characters.length <= limit) {
    return text;
  }
  return '${characters.take(limit).toString().trimRight()}…';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _four(int value) => value.toString().padLeft(4, '0');
