import 'floor_control.dart';

/// Learns the words this speaker gets cut off after, from getting cut off.
///
/// Every lexicon in [FloorControl] and its native counterpart is an
/// assertion about a language, written by somebody who is not the person
/// talking. This one needs no language knowledge at all: it watches for the
/// shape of having been interrupted mid-thought — a turn submitted, its
/// answer talked over, another turn straight after — and counts what the
/// cut-off sentence ended on.
///
/// Detection is deliberately loose and counting is what makes it precise. A
/// question genuinely interrupted for a good reason looks the same once; it
/// does not look the same three times ending on the same words. So the
/// ledger asks a weak question often rather than a strong question rarely.
///
/// It suggests, and nothing more. What it produces is a line for
/// `turnTaking.unfinished` in the agent profile, which the user adds or
/// does not — an app that silently rewrote how it listens to somebody would
/// be harder to trust than one that keeps being slightly wrong.
final class CutOffLedger {
  /// Creates a ledger.
  ///
  /// [alreadyListed] is read at the moment suggestions are asked for, so a
  /// word the user has just added stops being suggested immediately.
  CutOffLedger({
    this.repeatsBeforeSuggesting = 3,
    this.longestEnding = 5,
    List<String> Function()? alreadyListed,
  }) : alreadyListed = alreadyListed ?? _nothingListed;

  /// How many times an ending has to be cut off before it is worth raising.
  ///
  /// Three, because two is a coincidence often enough to be annoying and
  /// four is most of a session's patience.
  final int repeatsBeforeSuggesting;

  /// The longest ending considered, in syllables.
  ///
  /// Every shorter tail of a repeated phrase repeats with it, so all of them
  /// cross the threshold together and the longest is the real phrase. Five
  /// covers 「我想說的是」 and 「我的意思是」, which is about as long as a
  /// lead-in gets before it stops being a lead-in.
  final int longestEnding;

  /// What the profile already covers, read live.
  final List<String> Function() alreadyListed;

  final Map<String, int> _counts = <String, int>{};

  /// Records that [submitted] was cut off mid-thought.
  void noteCutOff(String submitted) {
    for (final String ending in _endingsOf(submitted)) {
      _counts[ending] = (_counts[ending] ?? 0) + 1;
    }
  }

  /// How many times an utterance ending in [ending] was cut off.
  ///
  /// The suggestion has to be able to show its evidence; without this it is
  /// only the app asserting something about how somebody talks.
  int timesCutOff(String ending) => _counts[ending] ?? 0;

  /// Endings worth adding to `turnTaking.unfinished`, longest first.
  ///
  /// Only the longest of each family: 「我想說的是」 and not also 「的是」,
  /// which matches half the language and would hold every turn open.
  List<String> get suggestions {
    final List<String> listed = alreadyListed()
        .map((String entry) => entry.trim())
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
    final List<String> ranked =
        _counts.entries
            .where(
              (MapEntry<String, int> e) => e.value >= repeatsBeforeSuggesting,
            )
            .map((MapEntry<String, int> e) => e.key)
            .toList()
          ..sort((String a, String b) {
            final int byLength = _length(b).compareTo(_length(a));
            return byLength != 0 ? byLength : a.compareTo(b);
          });
    final List<String> kept = <String>[];
    final List<String> accounted = <String>[];
    for (final String ending in ranked) {
      // A shorter tail of a longer one already handled is redundant only
      // when it never occurred anywhere else, which is exactly when their
      // counts match. A higher count means it did occur elsewhere — 「說的是」
      // reaching the threshold across three different sentences is a more
      // useful entry than any one of them.
      final bool explained = accounted.any(
        (String longer) =>
            longer.endsWith(ending) &&
            timesCutOff(longer) == timesCutOff(ending),
      );
      if (explained) {
        continue;
      }
      accounted.add(ending);
      // Covered by the profile only when a *listed* entry is a suffix of
      // this one: 「說的是」 already catches everything 「我想說的是」 would, and
      // not the other way round.
      if (listed.any((String entry) => ending.endsWith(entry))) {
        continue;
      }
      kept.add(ending);
    }
    return List<String>.unmodifiable(kept);
  }

  /// The tails of [submitted] at every length worth counting.
  List<String> _endingsOf(String submitted) {
    final List<String> units = _units(submitted);
    if (units.length < 2) {
      // One unit is not an ending, it is the whole utterance, and adding it
      // to `unfinished` would hold every turn that used that word.
      return const <String>[];
    }
    final List<String> endings = <String>[];
    for (int take = 2; take <= units.length && take <= longestEnding; take++) {
      endings.add(_join(units.sublist(units.length - take)));
    }
    return endings;
  }

  /// [text] split into the units an ending is measured in: one CJK
  /// character, or one whole Latin word.
  ///
  /// The same unit [FloorControl.syllablesOf] counts in, for the same
  /// reason — three letters of English is not three characters of Han.
  static List<String> _units(String text) {
    final List<String> units = <String>[];
    final StringBuffer latin = StringBuffer();
    void flush() {
      if (latin.isNotEmpty) {
        units.add(latin.toString());
        latin.clear();
      }
    }

    for (final int rune in text.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      if (_latinPiece.hasMatch(character)) {
        latin.write(character);
      } else if (_wordCharacter.hasMatch(character)) {
        flush();
        units.add(character);
      } else {
        flush();
      }
    }
    flush();
    return units;
  }

  /// Latin units are rejoined with the space they are written with; CJK
  /// units are not, because they are not written with one.
  static String _join(List<String> units) {
    final StringBuffer written = StringBuffer();
    for (int i = 0; i < units.length; i++) {
      final bool needsSpace =
          i > 0 &&
          _latinPiece.hasMatch(units[i][0]) &&
          _latinPiece.hasMatch(units[i - 1][units[i - 1].length - 1]);
      if (needsSpace) {
        written.write(' ');
      }
      written.write(units[i]);
    }
    return written.toString();
  }

  static int _length(String ending) => _units(ending).length;

  static final RegExp _latinPiece = RegExp(r'[a-z0-9]');
  static final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static List<String> _nothingListed() => const <String>[];
}
