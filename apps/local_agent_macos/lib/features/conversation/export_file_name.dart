/// A file name the system will accept, from whatever a conversation is called.
///
/// The title is the verbatim first thing the user said, so it can be anything
/// — including things that make a file the user will never find again.
///
/// * A leading dot makes a hidden file. Asking a local coding agent about
///   `.zshrc` is an ordinary thing to do and produced a conversation the
///   Finder would not show.
/// * `/` and `:` are not name characters on this system.
/// * A long title is cut, but cut on whole characters: slicing UTF-16 code
///   units can leave a lone surrogate, which the platform channel replaces
///   with U+FFFD.
String exportFileName(String title) {
  final String flattened = title
      .replaceAll(RegExp(r'[/:\\]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Leading dots only: one inside a name is ordinary.
  final String visible = flattened.replaceFirst(RegExp(r'^\.+'), '').trim();
  if (visible.isEmpty) {
    return 'conversation';
  }
  final List<int> runes = visible.runes.toList();
  if (runes.length <= _maxRunes) {
    return visible;
  }
  return String.fromCharCodes(runes.take(_maxRunes)).trim();
}

/// How many characters of a title survive into the file name.
///
/// Counted in characters rather than bytes, and kept well under the 255-byte
/// limit so that a name entirely in Han — three bytes each — still fits.
const int _maxRunes = 60;
