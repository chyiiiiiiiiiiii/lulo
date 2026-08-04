import 'package:flutter/foundation.dart';

/// What a note in the voice log is about.
enum VoiceNoteKind {
  /// An utterance settled and was submitted as a question.
  heard,

  /// Something was said and deliberately not acted on.
  ignored,

  /// The user took the floor back from an answer in progress.
  tookTheFloor,

  /// A chunk of the answer was handed to the voice.
  spoke,

  /// What one turn cost, from the settled transcript to the first sound.
  cost,
}

/// One decision the voice pipeline made, in words.
@immutable
final class VoiceTurnNote {
  /// Creates a note.
  const VoiceTurnNote({
    required this.kind,
    required this.text,
    required this.detail,
  });

  /// What the note is about.
  final VoiceNoteKind kind;

  /// The words the decision was made over, shortened for reading.
  final String text;

  /// Why it went the way it did.
  final String detail;
}

/// A short, bounded account of what the voice pipeline just did and why.
///
/// Every one of these decisions already went to `debugPrint`, which is
/// exactly the wrong place for them: the person who needs to know why the
/// agent stopped talking is the person talking to it, and they are looking
/// at the window rather than at a console. The turn-taking rules are
/// deliberate — an acknowledgement is ignored, a correction is obeyed, a
/// half-finished sentence is given longer — and a rule the user cannot see
/// firing is indistinguishable from a bug.
///
/// Written on the UI thread from the controller and read by the HUD. Kept
/// out of the controller itself so the controller does not grow a second
/// job, and so a surface that does not want the evidence simply passes
/// nothing.
final class VoiceTurnLog extends ChangeNotifier {
  /// How many notes are kept.
  ///
  /// A partial arrives every few hundred milliseconds for as long as the
  /// microphone is open, so this list is unbounded in principle and would
  /// otherwise outlive everything else in the app. Forty is a few minutes
  /// of conversation, which is as far back as anyone reads.
  static const int kept = 40;

  /// The longest an utterance is quoted at.
  static const int _quoted = 64;

  final List<VoiceTurnNote> _notes = <VoiceTurnNote>[];

  /// What has happened, oldest first.
  List<VoiceTurnNote> get notes => List<VoiceTurnNote>.unmodifiable(_notes);

  /// Records that [kind] happened over [text], because of [detail].
  void note(VoiceNoteKind kind, String text, {String detail = ''}) {
    _notes.add(VoiceTurnNote(kind: kind, text: _shorten(text), detail: detail));
    if (_notes.length > kept) {
      _notes.removeRange(0, _notes.length - kept);
    }
    notifyListeners();
  }

  /// Forgets everything recorded so far.
  void clear() {
    _notes.clear();
    notifyListeners();
  }

  static String _shorten(String text) {
    final String trimmed = text.trim();
    if (trimmed.runes.length <= _quoted) {
      return trimmed;
    }
    return '${String.fromCharCodes(trimmed.runes.take(_quoted - 1))}…';
  }
}
