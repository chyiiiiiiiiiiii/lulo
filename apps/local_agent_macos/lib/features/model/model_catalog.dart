import '../../l10n/generated/app_localizations.dart';

/// Which of the written descriptions belongs to a model.
///
/// A key rather than the sentence itself: the catalogue is a const list and
/// the sentence has to be read in whatever language the Mac is set to.
enum ModelDescription {
  /// The larger model: the strongest answers this family offers.
  balanced,

  /// The smaller model: quicker, and simpler in what it says.
  light,
}

/// One model the app knows how to fetch and think with.
final class ModelCatalogEntry {
  /// Describes one downloadable model.
  const ModelCatalogEntry({
    required this.id,
    required this.name,
    required this.descriptionKey,
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

  /// Which written description belongs to this model.
  final ModelDescription descriptionKey;

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

/// The one model a first launch is offered.
///
/// The first launch has exactly one decision to make and offering a list
/// would turn it into a comparison nobody arriving is equipped to make. The
/// rest of the catalogue is in settings, for later.
ModelCatalogEntry get recommendedModel => modelCatalog.firstWhere(
  (ModelCatalogEntry entry) => entry.recommended,
  orElse: () => modelCatalog.first,
);

/// The models the settings offer, the recommended one first.
///
/// Curated rather than fetched: each entry's size is pinned here, and a list
/// the app cannot be surprised by is a list it can verify downloads against.
/// Sizes and URLs come from the official LiteRT community conversions.
const List<ModelCatalogEntry> modelCatalog = <ModelCatalogEntry>[
  ModelCatalogEntry(
    id: 'gemma-4-E4B-it',
    name: 'Gemma 4 E4B',
    descriptionKey: ModelDescription.balanced,
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
    descriptionKey: ModelDescription.light,
    fileName: 'gemma-4-E2B-it.litertlm',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  ),
];

/// Reads a model's written description in the language the Mac is set to.
extension ModelCatalogEntryText on ModelCatalogEntry {
  /// What this model is, in words, for [words]' language.
  String description(AppLocalizations words) => switch (descriptionKey) {
    ModelDescription.balanced => words.modelDescriptionBalanced,
    ModelDescription.light => words.modelDescriptionLight,
  };
}
