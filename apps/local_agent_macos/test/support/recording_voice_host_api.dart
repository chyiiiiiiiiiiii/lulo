import 'package:local_agent_macos/generated/voice_host_api.g.dart';

/// The pigeon host, replaced by a notebook.
///
/// Subclassed rather than faked behind an interface because pigeon generates
/// a concrete class: overriding the one call under test is less machinery
/// than standing up a binary messenger, and the seam this test cares about is
/// what the text looks like by the time it gets here.
final class RecordingVoiceHostApi extends VoiceHostApi {
  /// Every sentence handed to the synthesiser, in order.
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text, String? voice, String? language) async {
    spoken.add(text);
  }
}
