import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/voice/voice_turn_hud.dart';
import 'package:local_agent_macos/features/voice/voice_turn_log.dart';

void main() {
  Future<void> show(WidgetTester tester, VoiceTurnLog log) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: VoiceTurnHud(log: log)),
    ),
  );

  testWidgets('an empty log says what it is waiting for', (
    WidgetTester tester,
  ) async {
    await show(tester, VoiceTurnLog());

    expect(find.textContaining('Nothing heard yet'), findsOneWidget);
  });

  testWidgets('every ruling is shown with its reason', (
    WidgetTester tester,
  ) async {
    final VoiceTurnLog log = VoiceTurnLog();
    log.note(
      VoiceNoteKind.ignored,
      '嗯嗯',
      detail: 'backchannel — this means carry on',
    );

    await show(tester, log);

    expect(find.text('嗯嗯'), findsOneWidget);
    expect(find.text('backchannel — this means carry on'), findsOneWidget);
  });

  testWidgets('a new ruling appears without the view being rebuilt', (
    WidgetTester tester,
  ) async {
    // The HUD exists to be watched during a conversation; nothing else is
    // going to call setState for it.
    final VoiceTurnLog log = VoiceTurnLog();
    await show(tester, log);

    log.note(VoiceNoteKind.tookTheFloor, '不對', detail: 'a correction');
    await tester.pump();

    expect(find.text('不對'), findsOneWidget);
  });

  testWidgets('the newest ruling is the one at the bottom', (
    WidgetTester tester,
  ) async {
    final VoiceTurnLog log = VoiceTurnLog();
    log.note(VoiceNoteKind.heard, 'first');
    log.note(VoiceNoteKind.heard, 'second');

    await show(tester, log);

    final double firstY = tester.getTopLeft(find.text('first')).dy;
    final double secondY = tester.getTopLeft(find.text('second')).dy;
    expect(secondY, greaterThan(firstY));
  });

  testWidgets('each kind of ruling is told apart at a glance', (
    WidgetTester tester,
  ) async {
    final VoiceTurnLog log = VoiceTurnLog();
    for (final VoiceNoteKind kind in VoiceNoteKind.values) {
      log.note(kind, kind.name);
    }

    await show(tester, log);

    // One label per kind, and no two the same — a HUD where "ignored" and
    // "took the floor" look alike is worse than no HUD.
    final Iterable<String> labels = tester
        .widgetList<Text>(find.byKey(const Key('voice-note-label')))
        .map((Text t) => t.data!);
    expect(labels.toSet(), hasLength(VoiceNoteKind.values.length));
  });
}
