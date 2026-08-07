import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Turn spoken({required double? confidence}) => Turn.voice(
    voiceInput: TranscriptRefinement(
      rawTranscript: '計算怎麼吃',
      proposedTranscript: null,
      selectedTranscript: '計算怎麼吃',
      status: TranscriptRefinementStatus.unchanged,
      edits: const <TranscriptEdit>[],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'test',
      refinerVersion: '1',
      elapsed: Duration.zero,
      heardConfidence: confidence,
    ),
  );

  Future<void> show(WidgetTester tester, Turn turn) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CompletedTurn(turn: turn)),
    ),
  );

  testWidgets('a sentence the recogniser doubted says so', (
    WidgetTester tester,
  ) async {
    // The recogniser writes 計算 for 肌酸 and the answer then talks about
    // 計算. Nothing on screen says which word it was unsure of, so the
    // agent reads as stupid rather than as mishearing.
    await show(tester, spoken(confidence: 0.48));

    expect(find.byKey(const Key('heard-doubt')), findsOneWidget);
  });

  testWidgets('a sentence it was sure of is left alone', (
    WidgetTester tester,
  ) async {
    await show(tester, spoken(confidence: 0.97));

    expect(find.byKey(const Key('heard-doubt')), findsNothing);
  });

  testWidgets('an unscored sentence is left alone', (
    WidgetTester tester,
  ) async {
    // Restored turns and older systems score nothing. A caveat on every
    // sentence is a caveat on none of them.
    await show(tester, spoken(confidence: null));

    expect(find.byKey(const Key('heard-doubt')), findsNothing);
  });

  testWidgets('a typed turn is never marked', (WidgetTester tester) async {
    await show(
      tester,
      const Turn(
        role: TurnRole.user,
        text: 'typed by hand',
        status: TurnStatus.completed,
      ),
    );

    expect(find.byKey(const Key('heard-doubt')), findsNothing);
  });

  testWidgets('the mark carries the score that produced it', (
    WidgetTester tester,
  ) async {
    // The number is what lets the user calibrate the threshold against
    // their own voice and room instead of trusting it.
    await show(tester, spoken(confidence: 0.48));

    final Tooltip tip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('heard-doubt')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tip.message, contains('0.48'));
  });
}
