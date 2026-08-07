import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_history_sheet.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// What the list has to do once there is more than a screenful in it.
void main() {
  ConversationSummary summary(String id, String title, {bool pinned = false}) =>
      ConversationSummary(
        id: ConversationId(id),
        title: title,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
        isPinned: pinned,
      );

  final List<ConversationSummary> two = <ConversationSummary>[
    summary('weather', '明天台中天氣如何'),
    summary('tests', 'how do I run the tests'),
  ];

  Widget sheet({
    List<ConversationSummary>? conversations,
    ValueChanged<String>? onSearch,
    void Function(ConversationId, String)? onRename,
    void Function(ConversationId, {required bool pinned})? onPin,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ConversationHistorySheet(
      conversations: conversations ?? two,
      onOpen: (ConversationId _) {},
      onNew: () {},
      onDelete: (ConversationId _) {},
      onClose: () {},
      onSearch: onSearch,
      onRename: onRename,
      onPin: onPin,
    ),
  );

  testWidgets('typing narrows the list', (WidgetTester tester) async {
    final List<String> queries = <String>[];
    await tester.pumpWidget(sheet(onSearch: queries.add));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('conversation-search-field')),
      '天',
    );
    await tester.enterText(
      find.byKey(const Key('conversation-search-field')),
      '天氣',
    );
    await tester.pump();
    // Debounced: the store is a full scan of every turn, and asking it per
    // keystroke asks the question five times to answer it once.
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(queries, <String>['天氣']);
  });

  testWidgets('a search with no matches says so rather than looking broken', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      sheet(conversations: const <ConversationSummary>[], onSearch: (_) {}),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('conversation-search-field')),
      '無關的字',
    );
    await tester.pump();

    expect(find.byKey(const Key('conversation-no-matches')), findsOneWidget);
  });

  testWidgets('a conversation can be pinned and unpinned', (
    WidgetTester tester,
  ) async {
    final List<({ConversationId id, bool pinned})> pins =
        <({ConversationId id, bool pinned})>[];
    await tester.pumpWidget(
      sheet(
        conversations: <ConversationSummary>[
          summary('weather', '明天台中天氣如何'),
          summary('tests', 'how do I run the tests', pinned: true),
        ],
        onPin: (ConversationId id, {required bool pinned}) =>
            pins.add((id: id, pinned: pinned)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-pin-weather')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-pin-tests')));
    await tester.pump();

    expect(pins, <({ConversationId id, bool pinned})>[
      (id: const ConversationId('weather'), pinned: true),
      (id: const ConversationId('tests'), pinned: false),
    ]);
  });

  testWidgets('a conversation can be renamed in place', (
    WidgetTester tester,
  ) async {
    final List<({ConversationId id, String title})> renames =
        <({ConversationId id, String title})>[];
    await tester.pumpWidget(
      sheet(
        onRename: (ConversationId id, String title) =>
            renames.add((id: id, title: title)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-menu-weather')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-rename-weather')));
    await tester.pumpAndSettle();

    final Finder field = find.byKey(const Key('conversation-rename-field'));
    expect(
      tester.widget<TextField>(field).controller?.text,
      '明天台中天氣如何',
      reason: 'renaming should start from the name it has',
    );
    await tester.enterText(field, '週末計畫');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renames, <({ConversationId id, String title})>[
      (id: const ConversationId('weather'), title: '週末計畫'),
    ]);
  });

  testWidgets('a sheet given no actions still lists and opens', (
    WidgetTester tester,
  ) async {
    // The preview and the widget tests have no store behind them.
    await tester.pumpWidget(sheet());
    await tester.pump();

    expect(find.byKey(const Key('conversation-search-field')), findsNothing);
    expect(find.byKey(const Key('conversation-pin-weather')), findsNothing);
    expect(find.byKey(const Key('conversation-row-weather')), findsOneWidget);
  });
}
