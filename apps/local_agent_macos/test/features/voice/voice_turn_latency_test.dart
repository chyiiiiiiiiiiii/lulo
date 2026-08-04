import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/voice/voice_turn_latency.dart';

void main() {
  final DateTime heard = DateTime.utc(2026, 8, 4, 12);
  DateTime after(int milliseconds) =>
      heard.add(Duration(milliseconds: milliseconds));

  test('a completed turn reports every stage and their sum', () {
    final VoiceTurnLatency latency = VoiceTurnLatency(heardAt: heard);
    latency.markSubmitted(after(10));
    latency.markFirstToken(after(300));

    expect(
      latency.describeFirstSpeech(after(540), characters: 12),
      'Lulo latency: refine 0.01s + think 0.29s + write 0.24s '
      '= 0.54s to the first 12 characters spoken',
    );
  });

  test('a turn that never reached the model describes nothing', () {
    final VoiceTurnLatency latency = VoiceTurnLatency(heardAt: heard);
    latency.markSubmitted(after(10));

    expect(latency.describeFirstSpeech(after(540), characters: 12), isNull);
  });

  test('a turn describes itself once, however many chunks follow', () {
    final VoiceTurnLatency latency = VoiceTurnLatency(heardAt: heard);
    latency.markSubmitted(after(10));
    latency.markFirstToken(after(300));

    expect(latency.describeFirstSpeech(after(540), characters: 12), isNotNull);
    expect(latency.describeFirstSpeech(after(900), characters: 30), isNull);
  });

  test('a stage that ran backwards is reported as zero, not as a negative', () {
    // The marks come from different callbacks on one clock, and a turn that
    // was already streaming when its transcript settled can order them the
    // other way round. A negative stage would read as a measurement bug.
    // The total stays measured end to end, so a clamped stage makes the
    // parts add up to slightly more than the whole — which is the truth.
    final VoiceTurnLatency latency = VoiceTurnLatency(heardAt: heard);
    latency.markSubmitted(after(10));
    latency.markFirstToken(after(5));

    expect(
      latency.describeFirstSpeech(after(540), characters: 12),
      'Lulo latency: refine 0.01s + think 0.00s + write 0.54s '
      '= 0.54s to the first 12 characters spoken',
    );
  });

  test('the first mark of each stage is the one that counts', () {
    final VoiceTurnLatency latency = VoiceTurnLatency(heardAt: heard);
    latency.markSubmitted(after(10));
    latency.markSubmitted(after(200));
    latency.markFirstToken(after(300));
    latency.markFirstToken(after(400));

    expect(
      latency.describeFirstSpeech(after(540), characters: 12),
      contains('refine 0.01s + think 0.29s'),
    );
  });
}
