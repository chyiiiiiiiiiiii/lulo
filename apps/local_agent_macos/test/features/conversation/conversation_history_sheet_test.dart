import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_history_sheet.dart';

void main() {
  const ConversationId yesterday = ConversationId('conversation-yesterday');
  const ConversationId older = ConversationId('conversation-older');

  final List<ConversationSummary> stored = <ConversationSummary>[
    ConversationSummary(
      id: yesterday,
      title: 'what we talked about',
      updatedAt: DateTime(2026, 7, 29, 22),
    ),
    ConversationSummary(
      id: older,
      title: 'an older thread',
      updatedAt: DateTime(2026, 7, 26, 9),
    ),
  ];

  Widget sheet({
    List<ConversationSummary>? conversations,
    ValueChanged<ConversationId>? onOpen,
    VoidCallback? onNew,
    ValueChanged<ConversationId>? onDelete,
    VoidCallback? onClose,
  }) => MaterialApp(
    home: ConversationHistorySheet(
      conversations: conversations ?? stored,
      onOpen: onOpen ?? (ConversationId _) {},
      onNew: onNew ?? () {},
      onDelete: onDelete ?? (ConversationId _) {},
      onClose: onClose ?? () {},
    ),
  );

  testWidgets('every stored conversation is a row, called by its title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(sheet());
    await tester.pump();

    expect(find.text('what we talked about'), findsOneWidget);
    expect(find.text('an older thread'), findsOneWidget);
  });

  testWidgets('choosing a conversation opens that one', (
    WidgetTester tester,
  ) async {
    final List<ConversationId> opened = <ConversationId>[];
    await tester.pumpWidget(sheet(onOpen: opened.add));
    await tester.pump();

    await tester.tap(find.text('an older thread'));

    expect(opened, <ConversationId>[older]);
  });

  testWidgets('a new conversation is one button away', (
    WidgetTester tester,
  ) async {
    int started = 0;
    await tester.pumpWidget(sheet(onNew: () => started += 1));
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-new-button')));

    expect(started, 1);
  });

  testWidgets('every row can be forgotten', (WidgetTester tester) async {
    final List<ConversationId> deleted = <ConversationId>[];
    await tester.pumpWidget(sheet(onDelete: deleted.add));
    await tester.pump();

    await tester.tap(find.byKey(Key('conversation-delete-${older.value}')));

    expect(deleted, <ConversationId>[older]);
  });

  testWidgets('a store with nothing in it says so', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(sheet(conversations: <ConversationSummary>[]));
    await tester.pump();

    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('escape puts the list away', (WidgetTester tester) async {
    // The sheet sits over the conversation and Esc is how a Mac user backs
    // out of anything transient — the same rule the settings follow.
    int closed = 0;
    await tester.pumpWidget(sheet(onClose: () => closed += 1));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closed, 1, reason: 'Escape did not close the conversation list.');
  });
}
