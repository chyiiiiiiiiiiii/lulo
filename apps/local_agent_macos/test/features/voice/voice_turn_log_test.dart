import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/voice/voice_turn_log.dart';

void main() {
  test('what happened is kept in the order it happened', () {
    final VoiceTurnLog log = VoiceTurnLog();
    log.note(VoiceNoteKind.heard, '介紹台北', detail: 'confident');
    log.note(VoiceNoteKind.ignored, '嗯嗯', detail: 'backchannel');

    expect(log.notes.map((VoiceTurnNote n) => n.kind), <VoiceNoteKind>[
      VoiceNoteKind.heard,
      VoiceNoteKind.ignored,
    ]);
    expect(log.notes.last.text, '嗯嗯');
    expect(log.notes.last.detail, 'backchannel');
  });

  test('a long session does not become a memory leak', () {
    // Every partial is a decision, and a partial arrives every few hundred
    // milliseconds for as long as the microphone is open. Unbounded, this
    // would be the longest-lived list in the app.
    final VoiceTurnLog log = VoiceTurnLog();
    for (int i = 0; i < VoiceTurnLog.kept * 3; i++) {
      log.note(VoiceNoteKind.heard, 'utterance $i');
    }

    expect(log.notes, hasLength(VoiceTurnLog.kept));
    expect(
      log.notes.last.text,
      'utterance ${VoiceTurnLog.kept * 3 - 1}',
      reason: 'The newest note is the one worth keeping.',
    );
  });

  test('the view is told whenever there is something new to draw', () {
    final VoiceTurnLog log = VoiceTurnLog();
    int told = 0;
    log.addListener(() => told += 1);

    log.note(VoiceNoteKind.spoke, 'answer');

    expect(told, 1);
  });

  test('a long utterance is kept short enough to read', () {
    final VoiceTurnLog log = VoiceTurnLog();
    log.note(VoiceNoteKind.heard, 'x' * 200);

    expect(log.notes.single.text.length, lessThanOrEqualTo(64));
    expect(log.notes.single.text, endsWith('…'));
  });

  test('clearing empties it and says so', () {
    final VoiceTurnLog log = VoiceTurnLog();
    log.note(VoiceNoteKind.heard, 'something');
    int told = 0;
    log.addListener(() => told += 1);

    log.clear();

    expect(log.notes, isEmpty);
    expect(told, 1);
  });
}
