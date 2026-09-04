/// What the voice pipeline can say about itself.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// The microphone is open and transcription is running.
final class ListeningStarted extends VoiceEvent {
  /// Creates the event.
  const ListeningStarted();
}

/// The microphone has been released.
final class ListeningStopped extends VoiceEvent {
  /// Creates the event.
  const ListeningStopped();
}

/// Words heard so far in the current utterance, still subject to change.
final class PartialTranscript extends VoiceEvent {
  /// Creates the event with what is being heard, and how long the burst of
  /// speech it came from has run.
  const PartialTranscript(this.text, {this.spokenFor});

  /// The words heard so far, still subject to change.
  final String text;

  /// How long the current burst of speech has run, or null where nothing
  /// measured it.
  ///
  /// The one turn-taking signal that needs no words: a backchannel is short
  /// in every language studied, so this is what keeps 「うんうん」 from ending
  /// an answer in a language whose acknowledgements nobody has listed. It
  /// also arrives before the transcript does, since it needs no recognition.
  final Duration? spokenFor;
}

/// One finished utterance, as the transcriber settled it.
final class FinalTranscript extends VoiceEvent {
  /// Creates the event with the settled utterance.
  const FinalTranscript(this.text, {this.confidence});

  /// The finalized transcription.
  final String text;

  /// How sure the recogniser was of the weakest span it wrote, or null
  /// where it scored nothing.
  ///
  /// Carried rather than merely logged so the sentence can be shown with a
  /// caveat: see [HeardConfidence]. The weakest span rather than the
  /// average, because one wrong word is enough to make the whole thing
  /// wrong.
  final double? confidence;
}

/// The synthesizer has started speaking.
final class SpeakingStarted extends VoiceEvent {
  /// Creates the event.
  const SpeakingStarted();
}

/// The synthesizer finished, or was stopped.
final class SpeakingFinished extends VoiceEvent {
  /// Creates the event.
  const SpeakingFinished();
}

/// Something in the pipeline failed; listening may have stopped with it.
final class VoiceFailed extends VoiceEvent {
  /// Creates the event with what went wrong.
  const VoiceFailed(this.message);

  /// A human-readable account of the failure.
  final String message;
}

/// The global hotkey is being held: the user is talking to the agent.
final class HoldToTalkPressed extends VoiceEvent {
  /// Creates the event.
  const HoldToTalkPressed();
}

/// The global hotkey was released: the held speech is complete.
final class HoldToTalkReleased extends VoiceEvent {
  /// Creates the event.
  const HoldToTalkReleased();
}

/// What the held speech actually said, from the batch recogniser.
///
/// Arrives a beat after [HoldToTalkReleased] and outranks the streaming
/// transcripts collected during the hold; empty means the recogniser had
/// nothing to say and the streaming transcripts stand.
final class HeldTranscript extends VoiceEvent {
  /// Creates the event with the recognised [text].
  const HeldTranscript(this.text);

  /// The whole held utterance, or empty when recognition failed.
  final String text;
}

/// Ears and voice, independently of who provides them.
///
/// The seam between the conversation loop and the platform: production
/// speaks through the native host (SpeechAnalyzer and AVSpeechSynthesizer),
/// tests hand events in by hand.
abstract interface class VoiceService {
  /// Everything the pipeline reports, in order.
  Stream<VoiceEvent> get events;

  /// Opens the microphone and starts streaming transcription.
  Future<void> startListening();

  /// Releases the microphone.
  Future<void> stopListening();

  /// Forces whatever is being heard to settle as a final transcript now.
  Future<void> finalizeUtterance();

  /// Speaks [text] aloud. Events report when it starts and finishes.
  ///
  /// [language] pins the synthesis language for a whole answer, so one
  /// English word inside a Chinese reply cannot flip the accent.
  Future<void> speak(String text, {String? language});

  /// Stops speaking mid-sentence, if speaking at all.
  Future<void> stopSpeaking();

  /// Tells the endpointer the user's own ways of leaving a sentence
  /// unfinished, so a pause after one of them is given longer to finish.
  ///
  /// The decision itself is native — the endpointer runs on a 50ms tick in
  /// the audio path — so this is the only way the profile reaches it.
  Future<void> useUnfinishedEndings(List<String> endings);

  /// Tells the recogniser the words this user says that it would otherwise
  /// spell as something else.
  ///
  /// Contextual biasing, which happens before audio is decoded rather than
  /// repairing a name afterwards. Read that as where it acts, not as
  /// whether it works: `SpokenVocabularyBook` carries a measurement of a
  /// thirty-two term bias changing the transcript by not one character, and
  /// `AgentProfile.misheard` exists because a hint can do nothing where a
  /// substitution cannot.
  Future<void> useSpokenVocabulary(List<String> terms);

  /// Tells the recogniser which language it is about to hear, as a BCP-47
  /// tag, before the microphone opens.
  ///
  /// The recogniser is monolingual and its locale is fixed for the whole
  /// session, so this is a decision that has to be made before there is any
  /// evidence to make it on. Sending it late sets the language of the next
  /// session, not this one.
  Future<void> useRecognitionLocale(String bcp47);

  /// Asks the batch recogniser to listen again to the utterance that just
  /// settled, and returns what it heard — or empty when it could not be
  /// reached, heard nothing, or there was no utterance to re-hear.
  ///
  /// The second listen exists because the streaming recogniser is measured
  /// 2-4x worse than the batch one on the same audio, and it scores its own
  /// doubt: see [HeardConfidence]. Costs about 1.3s, so the caller only asks
  /// on a doubted sentence.
  Future<String> reHearUtterance();

  /// Asks the user for a recording and returns its path, or empty if they
  /// backed out.
  Future<String> chooseRecording();

  /// Writes out the recording at [path], or empty when nothing came back.
  ///
  /// The batch recogniser is tuned for this user's language and already
  /// installed; until now the only way to reach it was to hold a key at a
  /// live microphone, so a recording they already had could not use it.
  Future<String> transcribeRecording(String path);
}
