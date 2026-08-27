import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_list.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

Turn userTurn(int i) =>
    Turn(role: TurnRole.user, text: '問題 $i', status: TurnStatus.completed);

Turn agentTurn(int i) =>
    Turn(role: TurnRole.assistant, text: '回答 $i', status: TurnStatus.completed);

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    ValueNotifier<List<Turn>> completed,
    ValueNotifier<Turn?> active,
  ) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('zh'),
      home: Scaffold(
        body: ConversationList(completedTurns: completed, activeTurn: active),
      ),
    ),
  );

  Map<String, CompletedTurn> renderedBy(WidgetTester tester) =>
      <String, CompletedTurn>{
        for (final CompletedTurn turn in tester.widgetList<CompletedTurn>(
          find.byType(CompletedTurn),
        ))
          turn.turn.text: turn,
      };

  testWidgets('a new turn does not rebuild the turns already on screen', (
    tester,
  ) async {
    final completed = ValueNotifier<List<Turn>>(<Turn>[
      for (int i = 0; i < 6; i++) ...<Turn>[userTurn(i), agentTurn(i)],
    ]);
    final active = ValueNotifier<Turn?>(null);
    addTearDown(completed.dispose);
    addTearDown(active.dispose);
    await pumpList(tester, completed, active);
    final Map<String, CompletedTurn> before = renderedBy(tester);

    completed.value = <Turn>[...completed.value, userTurn(6), agentTurn(6)];
    await tester.pump();
    final Map<String, CompletedTurn> after = renderedBy(tester);

    // Everything but the exchange that was newest, which loses its retries.
    for (final String text in <String>['問題 0', '回答 0', '問題 4', '回答 4']) {
      expect(
        identical(before[text], after[text]),
        isTrue,
        reason: '$text was rebuilt for a turn that arrived after it',
      );
    }
  });

  testWidgets('a turn edited in place is rendered again', (tester) async {
    final completed = ValueNotifier<List<Turn>>(<Turn>[
      userTurn(0),
      agentTurn(0),
      userTurn(1),
    ]);
    final active = ValueNotifier<Turn?>(null);
    addTearDown(completed.dispose);
    addTearDown(active.dispose);
    await pumpList(tester, completed, active);

    completed.value = <Turn>[
      userTurn(0),
      Turn(
        role: TurnRole.assistant,
        text: '換過的回答',
        status: TurnStatus.completed,
      ),
      userTurn(1),
    ];
    await tester.pump();

    expect(find.text('換過的回答'), findsOneWidget);
    expect(find.text('回答 0'), findsNothing);
  });
}
