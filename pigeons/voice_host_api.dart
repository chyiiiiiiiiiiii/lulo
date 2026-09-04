import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'apps/local_agent_macos/lib/generated/voice_host_api.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'apps/local_agent_macos/macos/Runner/GeneratedVoiceHostApi.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    dartPackageName: 'local_agent_macos',
  ),
)
/// What the native voice pipeline can report.
enum HostVoiceEventType {
  /// The microphone is open and transcription is running.
  listeningStarted,

  /// The microphone has been released.
  listeningStopped,

  /// Words heard so far, still subject to change.
  partialTranscript,

  /// One finished utterance, settled.
  finalTranscript,

  /// The synthesizer started speaking.
  speakingStarted,

  /// The synthesizer finished, or was stopped.
  speakingFinished,

  /// Something failed; listening may have stopped with it.
  voiceFailed,

  /// The global hotkey is being held: the user is talking to the agent.
  holdToTalkPressed,

  /// The global hotkey was released: the held speech is complete.
  holdToTalkReleased,

  /// What the held speech actually said, from the batch recogniser.
  ///
  /// Arrives a beat after holdToTalkReleased and replaces the streaming
  /// transcripts collected during the hold; if it never arrives, the
  /// streaming transcripts stand.
  heldTranscript,
}

/// One event from the native voice pipeline.
class HostVoiceEvent {
  /// Creates the event.
  HostVoiceEvent({
    required this.type,
    this.text,
    this.confidence,
    this.speechMs,
  });

  /// What happened.
  final HostVoiceEventType type;

  /// The transcript for transcript events, the message for failures.
  final String? text;

  /// How sure the recogniser was of the weakest span it wrote, on settled
  /// transcripts only, and null wherever it scored nothing.
  ///
  /// The weakest span rather than the average: one wrong word makes the
  /// sentence wrong, and an average buries it.
  final double? confidence;

  /// How long the burst of speech this transcript came from has run, in
  /// milliseconds, or null where nothing measured it.
  ///
  /// The one turn-taking signal that needs no words: a backchannel is short
  /// in every language studied. It is what keeps 「うんうん」 from ending an
  /// answer in a language whose acknowledgements nobody has listed.
  final int? speechMs;
}

/// Dart-to-native: driving the ears and the mouth.
@HostApi()
abstract class VoiceHostApi {
  /// Opens the microphone and starts streaming transcription.
  @async
  void startListening();

  /// Releases the microphone.
  @async
  void stopListening();

  /// Forces whatever is being heard to settle as a final transcript now.
  ///
  /// The transcriber's own endpointing waits out a long silence; a user who
  /// has visibly stopped talking should not.
  @async
  void finalizeUtterance();

  /// Speaks [text] aloud, with [voice] naming who speaks and [language]
  /// pinning the synthesis language for the whole answer, so one English
  /// word inside a Chinese reply cannot flip the accent mid-thought.
  @async
  void speak(String text, String? voice, String? language);

  /// Stops speaking mid-sentence.
  @async
  void stopSpeaking();

  /// Tells the endpointer the user's own ways of leaving a sentence
  /// unfinished, so a pause after one of them is given longer to finish.
  ///
  /// Sent from Dart because the agent profile lives there and is watched;
  /// applied natively because the endpointer runs on a 50ms tick in the
  /// audio path, where a hop across this channel per tick would cost more
  /// than the decision saves. Replaces the previous list wholesale.
  @async
  void useUnfinishedEndings(List<String> endings);

  /// Tells the recogniser which language it will be hearing, as a BCP-47
  /// tag.
  ///
  /// The transcriber is monolingual: a locale is chosen once, when the
  /// session opens, and cannot be asked afterwards what it is hearing. Until
  /// this existed that choice was made natively from
  /// `Locale.preferredLanguages`, so the agent spoke whatever the Mac spoke
  /// and an English agent on a Chinese machine could not be expressed at
  /// all. Sent before `startListening`, because a locale that arrives after
  /// the session has opened sets the language of the session after this one.
  @async
  void useRecognitionLocale(String bcp47);

  /// Tells the recogniser the words this user says that it would otherwise
  /// spell as something else — names, products, jargon.
  ///
  /// This is contextual biasing: Apple's `AnalysisContext.contextualStrings`,
  /// what most vendors call a boost list. It has to happen before the audio
  /// is decoded, which is why it crosses the channel instead of being read
  /// where the decision is made — by the time Dart sees a transcript the
  /// word has already been misheard, and repairing it there is guessing at
  /// what was said. Replaces the previous list wholesale.
  @async
  void useSpokenVocabulary(List<String> terms);

  /// Re-hears the utterance that just settled with the batch recogniser and
  /// returns what it heard, or empty when it could not be reached, heard
  /// nothing, or there was no utterance to re-hear.
  ///
  /// The streaming session's microphone samples are kept in a bounded ring
  /// for exactly this: a settled transcript the recogniser doubted can be
  /// listened to again by the recogniser that hears this user better. The
  /// same Breeze-ASR-25 sidecar the hold key uses.
  @async
  String reHearUtterance();

  /// Asks the user for a recording to transcribe and returns its path, or
  /// empty if they backed out.
  ///
  /// The chooser is the system's own, so the app is never told where files
  /// live and never handles a path the user did not pick.
  @async
  String chooseRecording();

  /// Transcribes the recording at [path] with the batch recogniser.
  ///
  /// Returns the text, or empty when the recogniser could not be reached or
  /// had nothing to say. The same Breeze-ASR-25 sidecar the hold-to-talk key
  /// uses — it is tuned for this user's language and already installed, and
  /// until now the only way to reach it was to hold a key at a live
  /// microphone.
  @async
  String transcribeRecording(String path);
}

/// Native-to-Dart: everything the pipeline reports, in order.
@FlutterApi()
abstract class VoiceHostEvents {
  /// Delivers one event.
  void onVoiceEvent(HostVoiceEvent event);
}
