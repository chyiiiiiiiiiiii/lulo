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
}

/// One event from the native voice pipeline.
class HostVoiceEvent {
  /// Creates the event.
  HostVoiceEvent({required this.type, this.text});

  /// What happened.
  final HostVoiceEventType type;

  /// The transcript for transcript events, the message for failures.
  final String? text;
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
}

/// Native-to-Dart: everything the pipeline reports, in order.
@FlutterApi()
abstract class VoiceHostEvents {
  /// Delivers one event.
  void onVoiceEvent(HostVoiceEvent event);
}
