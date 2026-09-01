/// What is left of an answer once everything unsayable is taken out.
library;

/// [text] with everything a voice cannot say stripped away.
///
/// The synthesizer reads exactly what it is given: emoji become their
/// spelled-out names, markdown becomes noise, and code is unreadable aloud.
/// Speech gets the sentences alone; the full text stays on screen.
String speakableText(String text) {
  String speakable = text;
  // Whole code blocks go first, fences and all.
  speakable = speakable.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // A link is read by its label; the address is for clicking.
  speakable = speakable.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (Match m) => m[1] ?? '',
  );
  speakable = speakable.replaceAll(RegExp(r'https?://\S+'), ' ');
  // Horizontal rules and list markers are layout, not words: "---" read
  // aloud is a groan, and "- 第一點" starts with a minus.
  speakable = speakable.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    ' ',
  );
  speakable = speakable.replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '');
  // Inline markup keeps its words and loses its marks.
  speakable = speakable.replaceAll(RegExp(r'[`*_~#>]'), '');
  // Emoji and pictographs, including variation selectors.
  speakable = speakable.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}'
      r'\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{200D}]',
      unicode: true,
    ),
    '',
  );
  return speakable.replaceAll(RegExp(r'\s+'), ' ').trim();
}
