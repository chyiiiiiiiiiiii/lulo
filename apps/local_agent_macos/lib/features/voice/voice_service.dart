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
  /// Creates the event with what has been heard so far.
  const PartialTranscript(this.text);

  /// The volatile transcription of the utterance in progress.
  final String text;
}

/// One finished utterance, as the transcriber settled it.
final class FinalTranscript extends VoiceEvent {
  /// Creates the event with the settled utterance.
  const FinalTranscript(this.text);

  /// The finalized transcription.
  final String text;
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
}
