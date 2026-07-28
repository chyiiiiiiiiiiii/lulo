import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_list.dart';

void main() {
  testWidgets('the conversation follows new answers to the bottom', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);

    await tester.pumpWidget(conversation.surface());
    await tester.pump();

    conversation.completedTurns.value = _turns(20);
    await tester.pump();
    // The height only exists once the new turns have been laid out, so the
    // correction lands in the frame after the build that added them.
    await tester.pump();

    final ScrollPosition position = _position(tester);
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'A new answer arrived and the conversation stayed where it was.',
    );
  });

  testWidgets('reading back stops the conversation dragging you away', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);

    await tester.pumpWidget(conversation.surface());
    conversation.completedTurns.value = _turns(20);
    await tester.pump();
    await tester.pump();

    // The user scrolls back to read something earlier.
    await tester.drag(
      find.byKey(const Key('conversation-scroll-surface')),
      const Offset(0, 300),
    );
    await tester.pump();
    final double readingAt = _position(tester).pixels;
    expect(readingAt, lessThan(_position(tester).maxScrollExtent));

    conversation.completedTurns.value = _turns(24);
    await tester.pump();
    await tester.pump();

    expect(
      _position(tester).pixels,
      readingAt,
      reason: 'A new answer yanked the view away from what was being read.',
    );
    expect(
      find.byKey(const Key('conversation-scroll-to-bottom')),
      findsOneWidget,
      reason: 'Nothing offered a way back to the newest answer.',
    );
  });

  testWidgets('returning to the bottom resumes following', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);

    await tester.pumpWidget(conversation.surface());
    conversation.completedTurns.value = _turns(20);
    await tester.pump();
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('conversation-scroll-surface')),
      const Offset(0, 300),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-scroll-to-bottom')));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, _position(tester).maxScrollExtent);
    expect(
      find.byKey(const Key('conversation-scroll-to-bottom')),
      findsNothing,
      reason: 'The way back stayed on screen after arriving.',
    );

    conversation.completedTurns.value = _turns(24);
    await tester.pump();
    await tester.pump();

    expect(
      _position(tester).pixels,
      _position(tester).maxScrollExtent,
      reason: 'Coming back to the newest answer did not resume following it.',
    );
  });
}

/// Drives a [ConversationList] the way the ViewModel does.
final class _Conversation {
  final ValueNotifier<List<Turn>> completedTurns = ValueNotifier<List<Turn>>(
    <Turn>[],
  );
  final ValueNotifier<Turn?> activeTurn = ValueNotifier<Turn?>(null);

  Widget surface() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 300,
        child: ConversationList(
          completedTurns: completedTurns,
          activeTurn: activeTurn,
        ),
      ),
    ),
  );

  void dispose() {
    completedTurns.dispose();
    activeTurn.dispose();
  }
}

List<Turn> _turns(int count) => <Turn>[
  for (int index = 0; index < count; index += 1)
    Turn(
      role: index.isEven ? TurnRole.user : TurnRole.assistant,
      text: 'Turn number $index of the conversation.',
      status: TurnStatus.completed,
    ),
];

/// The conversation's own scroll position.
///
/// Rendered turns bring scrollables of their own, so this is anchored to the
/// conversation surface rather than to whatever scrollable comes first.
ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('conversation-scroll-surface')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;
