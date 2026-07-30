/// One model the app knows how to fetch and think with.
final class ModelCatalogEntry {
  /// Describes one downloadable model.
  const ModelCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    this.recommended = false,
  });

  /// Stable identity, independent of where the file ends up.
  final String id;

  /// What the settings call it.
  final String name;

  /// One sentence on why someone would pick it.
  final String description;

  /// The file's name once installed.
  final String fileName;

  /// Where the bytes live.
  final String url;

  /// Exactly how many bytes the whole model is.
  ///
  /// Exact rather than approximate, so a finished download can be told apart
  /// from a truncated one.
  final int sizeBytes;

  /// Whether this is the model the app reaches for by default.
  final bool recommended;
}

/// The models the settings offer, the recommended one first.
///
/// Curated rather than fetched: each entry's size is pinned here, and a list
/// the app cannot be surprised by is a list it can verify downloads against.
/// Sizes and URLs come from the official LiteRT community conversions.
const List<ModelCatalogEntry> modelCatalog = <ModelCatalogEntry>[
  ModelCatalogEntry(
    id: 'gemma-4-E4B-it',
    name: 'Gemma 4 E4B',
    description:
        'The balanced choice: strongest answers this laptop-sized '
        'model family offers.',
    fileName: 'gemma-4-E4B-it.litertlm',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/'
        'resolve/main/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    recommended: true,
  ),
  ModelCatalogEntry(
    id: 'gemma-4-E2B-it',
    name: 'Gemma 4 E2B',
    description:
        'The light choice: quicker to fetch and to answer, with '
        'simpler answers.',
    fileName: 'gemma-4-E2B-it.litertlm',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
  ),
];
