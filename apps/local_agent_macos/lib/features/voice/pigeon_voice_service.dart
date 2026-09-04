import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../../generated/voice_host_api.g.dart';
import 'speakable_text.dart';
import 'voice_service.dart';

/// The production [VoiceService]: the native host over pigeon.
///
/// Behind the host live the microphone, SpeechAnalyzer transcription, and
/// AVSpeechSynthesizer. A host call that fails becomes a [VoiceFailed] event
/// rather than an exception: the conversation loop must survive a microphone
/// that went away.
final class PigeonVoiceService implements VoiceService, VoiceHostEvents {
  /// Creates the service over [hostApi], defaulting to the real channel.
  ///
  /// [voiceOf] names who speaks at the moment of each utterance, so a voice
  /// changed in settings applies to the very next answer.
  PigeonVoiceService({
    VoiceHostApi? hostApi,
    String Function()? voiceOf,
    List<SpokenRespelling> Function()? respellings,
  }) : this._(hostApi ?? VoiceHostApi(), voiceOf, respellings);

  PigeonVoiceService._(this._host, this._voiceOf, this._respellings) {
    VoiceHostEvents.setUp(this);
  }

  final VoiceHostApi _host;
  final String Function()? _voiceOf;

  /// Words this voice says wrongly, read again at every utterance so a table
  /// edited in Settings applies to the very next sentence.
  final List<SpokenRespelling> Function()? _respellings;
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> startListening() => _guard(() => _host.startListening());

  @override
  Future<void> stopListening() => _guard(() => _host.stopListening());

  @override
  Future<void> finalizeUtterance() => _guard(() => _host.finalizeUtterance());

  /// Says [text]: stripped of what cannot be spoken, then respelled for
  /// this voice's known mispronunciations.
  ///
  /// This is the one place either happens, and it is deliberately the last
  /// thing that happens to the sentence. Everything upstream — the turn, the
  /// store, the screen, the export — keeps the real spelling, or the user
  /// reads 氣業 in their own transcript and rightly concludes the agent
  /// cannot spell. See [SpokenRespelling].
  ///
  /// [speakableText] used to run only inside the voice loop, so the
  /// read-aloud button on a turn handed the raw answer over and the
  /// synthesiser said the hashes and the list dashes out loud. Applying it
  /// here covers every caller, including the next one; running it twice on
  /// the loop's already-stripped text changes nothing.
  @override
  Future<void> speak(String text, {String? language}) => _guard(
    () => _host.speak(
      respellForSpeech(
        speakableText(text),
        _respellings?.call() ?? const <SpokenRespelling>[],
      ),
      _voiceOf?.call(),
      language,
    ),
  );

  @override
  Future<void> stopSpeaking() => _guard(() => _host.stopSpeaking());

  @override
  Future<void> useUnfinishedEndings(List<String> endings) =>
      _guard(() => _host.useUnfinishedEndings(endings));

  @override
  Future<void> useSpokenVocabulary(List<String> terms) =>
      _guard(() => _host.useSpokenVocabulary(terms));

  @override
  Future<void> useRecognitionLocale(String bcp47) =>
      _guard(() => _host.useRecognitionLocale(bcp47));

  @override
  Future<String> reHearUtterance() => _host.reHearUtterance();

  @override
  Future<String> chooseRecording() => _host.chooseRecording();

  @override
  Future<String> transcribeRecording(String path) =>
      _host.transcribeRecording(path);

  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (error) {
      if (!_events.isClosed) {
        _events.add(VoiceFailed(error.toString()));
      }
    }
  }

  @override
  void onVoiceEvent(HostVoiceEvent event) {
    if (_events.isClosed) {
      return;
    }
    final String text = event.text ?? '';
    _events.add(switch (event.type) {
      HostVoiceEventType.listeningStarted => const ListeningStarted(),
      HostVoiceEventType.listeningStopped => const ListeningStopped(),
      HostVoiceEventType.partialTranscript => PartialTranscript(
        text,
        spokenFor: event.speechMs == null
            ? null
            : Duration(milliseconds: event.speechMs!),
      ),
      HostVoiceEventType.finalTranscript => FinalTranscript(
        text,
        confidence: event.confidence,
      ),
      HostVoiceEventType.speakingStarted => const SpeakingStarted(),
      HostVoiceEventType.speakingFinished => const SpeakingFinished(),
      HostVoiceEventType.voiceFailed => VoiceFailed(text),
      HostVoiceEventType.holdToTalkPressed => const HoldToTalkPressed(),
      HostVoiceEventType.holdToTalkReleased => const HoldToTalkReleased(),
      HostVoiceEventType.heldTranscript => HeldTranscript(text),
    });
  }

  /// Detaches from the channel and closes the event stream.
  Future<void> dispose() async {
    VoiceHostEvents.setUp(null);
    await _events.close();
  }
}
