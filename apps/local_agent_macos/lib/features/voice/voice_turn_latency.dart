/// One turn's journey from a settled transcript to the first sound of an
/// answer, in the three stages a person actually waits through.
///
/// The two ends of the wait are logged elsewhere and by whoever can see them:
/// the adapter reports how long the room was quiet before the endpointer
/// fired and how long the transcriber took to answer it, and the synthesiser
/// reports how long its first chunk took. This covers the stretch in between,
/// which nothing else can see whole — the refinement, the model's first
/// token, and how much of an answer had to exist before any of it was worth
/// saying out loud.
///
/// Deliberately a measurement and nothing else: it holds no transcript and no
/// answer text, only lengths and instants, so the line it produces is safe to
/// write to a log that keeps private conversations out of it.
final class VoiceTurnLatency {
  /// Starts the clock at the instant the transcript settled.
  VoiceTurnLatency({required this.heardAt});

  /// When the transcript settled: the instant the wait starts.
  final DateTime heardAt;
  DateTime? _submittedAt;
  DateTime? _firstTokenAt;
  bool _described = false;

  /// The refined question went to the model.
  ///
  /// A repeat is ignored: the first submission is the one the user waited on.
  void markSubmitted(DateTime at) => _submittedAt ??= at;

  /// The model produced the first of the answer.
  void markFirstToken(DateTime at) => _firstTokenAt ??= at;

  /// The one line describing this turn, or null when there is nothing
  /// honest to say — a stage that never happened, or a turn already
  /// described, because only the answer's *first* chunk is a latency.
  String? describeFirstSpeech(DateTime at, {required int characters}) {
    final DateTime? submitted = _submittedAt;
    final DateTime? firstToken = _firstTokenAt;
    if (submitted == null || firstToken == null || _described) {
      return null;
    }
    _described = true;
    final double refine = _seconds(heardAt, submitted);
    final double think = _seconds(submitted, firstToken);
    final double write = _seconds(firstToken, at);
    return 'Lulo latency: refine ${refine.toStringAsFixed(2)}s '
        '+ think ${think.toStringAsFixed(2)}s '
        '+ write ${write.toStringAsFixed(2)}s '
        '= ${_seconds(heardAt, at).toStringAsFixed(2)}s '
        'to the first $characters characters spoken';
  }

  /// Seconds from [from] to [to], never negative.
  ///
  /// The marks arrive from separate callbacks, and a turn that was already
  /// streaming when its transcript settled orders them the other way round.
  /// A negative stage reads as a broken measurement rather than as the
  /// overlap it actually is.
  static double _seconds(DateTime from, DateTime to) {
    final int microseconds = to.difference(from).inMicroseconds;
    return microseconds <= 0
        ? 0
        : microseconds / Duration.microsecondsPerSecond;
  }
}
