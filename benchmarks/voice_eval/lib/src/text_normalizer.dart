/// Normalizes spacing while preserving punctuation and Latin letter case.
String normalizeLiteral(String text) =>
    text.trim().replaceAll(RegExp(r'\s+', unicode: true), ' ');

/// Normalizes text for spoken-content comparison.
String normalizeSpoken(String text) => normalizeLiteral(
  text,
).replaceAll(RegExp(r'[\p{P}\p{S}\s]+', unicode: true), '').toLowerCase();
