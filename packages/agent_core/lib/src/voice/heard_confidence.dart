/// How sure the recogniser was of what it wrote, and whether that is sure
/// enough to show the user without a caveat.
///
/// The complaint that outlives every latency fix is that the bubble shows a
/// word the user did not say — the recogniser writes 計算 for 肌酸, and the
/// answer then talks about 計算, because the model has the conversation and
/// the recogniser does not. There is nothing in the text that says which
/// word is wrong.
///
/// There is something in the *score*. `SpeechTranscriber` attaches a
/// confidence to every span, and over the private zh-TW corpus the two
/// populations barely overlap: every correctly heard span scored 0.88 to
/// 1.00, and every error scored 0.78 or below. A transcript is worth its
/// weakest span rather than its average, because one wrong word is enough
/// to make the sentence wrong and an average buries a 0.31 under a dozen
/// 1.00s.
///
/// This decides only whether to *mark* the sentence. Repairing it is a
/// different and much more expensive decision — measured at 0.7–1.0s warm
/// against the full model — and it needs its own evidence.
abstract final class HeardConfidence {
  /// At or above this score, the recogniser is taken at its word.
  ///
  /// 0.85 sits in the gap the corpus left between 0.79 (`codex`, heard
  /// right but unsure of its capitalisation) and 0.88 (the weakest span of
  /// anything heard correctly). It catches all four real errors and one
  /// correct-but-hesitant span. That asymmetry is deliberate: the mark is
  /// advisory, so over-marking costs a caveat and under-marking costs the
  /// user not knowing why the answer was strange.
  static const double trusted = 0.85;

  /// Whether a transcript scored [weakestSpan] should be shown with a
  /// caveat.
  ///
  /// A null score means the recogniser measured nothing — an older system,
  /// or a path that never asked for the attribute. Nothing is claimed, so
  /// nothing is doubted: a caveat on every sentence is a caveat on none.
  static bool isDoubtful(double? weakestSpan) =>
      weakestSpan != null && weakestSpan < trusted;
}
