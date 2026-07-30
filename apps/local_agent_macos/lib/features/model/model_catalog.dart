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
    this.sha256,
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

  /// The SHA-256 of the whole file, lower-case hex, from the official model
  /// card. Null skips verification — permitted for test fixtures only; the
  /// catalog test refuses a real entry without one.
  final String? sha256;

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
    sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
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
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  ),
];
