import 'dart:async';

import '../../generated/voice_host_api.g.dart';
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
  PigeonVoiceService({VoiceHostApi? hostApi, String Function()? voiceOf})
    : this._(hostApi ?? VoiceHostApi(), voiceOf);

  PigeonVoiceService._(this._host, this._voiceOf) {
    VoiceHostEvents.setUp(this);
  }

  final VoiceHostApi _host;
  final String Function()? _voiceOf;
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

  @override
  Future<void> speak(String text, {String? language}) =>
      _guard(() => _host.speak(text, _voiceOf?.call(), language));

  @override
  Future<void> stopSpeaking() => _guard(() => _host.stopSpeaking());

  @override
  Future<void> useUnfinishedEndings(List<String> endings) =>
      _guard(() => _host.useUnfinishedEndings(endings));

  @override
  Future<void> useSpokenVocabulary(List<String> terms) =>
      _guard(() => _host.useSpokenVocabulary(terms));

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
