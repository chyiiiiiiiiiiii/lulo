/// The language the conversation is held in.
///
/// The written half of the app never needed this: `composeAgentPrompt` reads
/// the language off the question itself, because a small model answers in
/// whichever language it was instructed in and an English preamble in front
/// of a Chinese question turns the reply English. A typed question carries
/// its own answer.
///
/// The spoken half cannot do that. The recogniser is monolingual — one locale
/// chosen at `begin()`, before a word has been said — so a transcript's script
/// says what the recogniser was set to and not what the user spoke. Something
/// has to decide, and it has to decide before there is any evidence. This is
/// that decision, held where the user can change it.
enum AgentLanguage {
  /// English, and the default.
  ///
  /// Measured rather than assumed: the resident voice renders English at
  /// 0.054 WER through a recogniser with every remaining difference a
  /// numeral convention (`twenty past three` written back as `20 past 3`)
  /// and not one mispronounced word — against a Chinese side where one word
  /// in eight had to be respelled before it could be said at all.
  english('en-US'),

  /// Traditional Chinese as spoken in Taiwan.
  chinese('zh-TW');

  const AgentLanguage(this.localeTag);

  /// The BCP-47 tag the platform recogniser is opened with.
  final String localeTag;

  /// What the app falls back to wherever nothing has been chosen.
  static const AgentLanguage byDefault = AgentLanguage.english;

  /// The language [locale] names, or [byDefault] when it names none.
  ///
  /// Only the language subtag is read. Profiles on disk carry `zh-TW`,
  /// `zh-Hant-TW` and `en_GB` depending on what wrote them, and the region
  /// and script never changed which recogniser to open.
  ///
  /// An unreadable tag resolves rather than throwing: the alternative is an
  /// app with no language at all, which falls back to whatever the system
  /// says — the exact behaviour this setting exists to take back.
  static AgentLanguage ofLocale(String locale) {
    final String tag = locale.trim().toLowerCase().replaceAll('_', '-');
    final String language = tag.split('-').first;
    for (final AgentLanguage candidate in AgentLanguage.values) {
      if (candidate.localeTag.split('-').first == language) {
        return candidate;
      }
    }
    return byDefault;
  }
}
