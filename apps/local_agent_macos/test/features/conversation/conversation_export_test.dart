import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_history_sheet.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// The one way anything said to Lulo can leave the machine.
void main() {
  final List<ConversationSummary> conversations = <ConversationSummary>[
    ConversationSummary(
      id: const ConversationId('yesterday'),
      title: '明天天氣如何',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    ),
  ];

  Widget sheet({ValueChanged<ConversationId>? onExport}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ConversationHistorySheet(
      conversations: conversations,
      onOpen: (ConversationId _) {},
      onNew: () {},
      onDelete: (ConversationId _) {},
      onClose: () {},
      onExport: onExport,
    ),
  );

  testWidgets('a stored conversation offers a way out', (
    WidgetTester tester,
  ) async {
    final List<ConversationId> exported = <ConversationId>[];
    await tester.pumpWidget(sheet(onExport: exported.add));
    await tester.pump();

    // Behind the row's menu rather than a fourth icon on the row itself.
    await tester.tap(find.byKey(const Key('conversation-menu-yesterday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-export-yesterday')));
    await tester.pumpAndSettle();

    expect(exported, <ConversationId>[const ConversationId('yesterday')]);
  });

  testWidgets('no way out is offered where there is nowhere to save', (
    WidgetTester tester,
  ) async {
    // The preview and the widget tests have no window to put a save panel
    // over. A button that cannot open one is a dead end, not a feature.
    await tester.pumpWidget(sheet());
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-menu-yesterday')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation-export-yesterday')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('conversation-delete-yesterday')),
      findsOneWidget,
      reason: 'forgetting must still be reachable without a save panel',
    );
  });
}
