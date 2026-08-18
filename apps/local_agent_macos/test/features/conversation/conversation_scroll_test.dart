import 'package:agent_core/agent_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_list.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

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

    conversation.completedTurns.value = _turns(20) + _answers(4);
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

  testWidgets('an answer arriving mid-scroll does not take the list back', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);

    await tester.pumpWidget(conversation.surface());
    conversation.completedTurns.value = _turns(20);
    await tester.pump();
    await tester.pump();

    // Still holding the list, which is the whole of it: an answer that lands
    // between two frames of a scroll must not end the scroll. Answers arrive
    // every few hundred milliseconds, so one that cancels the gesture cancels
    // every attempt to read back and the list cannot be moved at all.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('conversation-scroll-surface'))),
    );
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump();

    conversation.completedTurns.value = _turns(20) + _answers(4);
    await tester.pump();
    await tester.pump();

    // The hand carries on where it was.
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final ScrollPosition position = _position(tester);
    expect(
      position.pixels,
      lessThan(position.maxScrollExtent - 100),
      reason: 'The answer took the list back while it was being scrolled.',
    );
  });

  testWidgets('saying something takes you back to the newest', (
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
    expect(
      _position(tester).pixels,
      lessThan(_position(tester).maxScrollExtent),
    );

    // Sending something is asking to see it. Being left where they were
    // reading, with what they just said off screen below, is the one case
    // where staying put is the wrong answer.
    conversation.completedTurns.value = <Turn>[
      ..._turns(20),
      const Turn(
        role: TurnRole.user,
        text: 'And what about this?',
        status: TurnStatus.completed,
      ),
    ];
    await tester.pump();
    await tester.pump();

    expect(
      _position(tester).pixels,
      _position(tester).maxScrollExtent,
      reason: 'What the user just said was left off screen below them.',
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

    conversation.completedTurns.value = _turns(20) + _answers(4);
    await tester.pump();
    await tester.pump();

    expect(
      _position(tester).pixels,
      _position(tester).maxScrollExtent,
      reason: 'Coming back to the newest answer did not resume following it.',
    );
  });

  testWidgets('a mouse wheel reads the conversation back', (
    WidgetTester tester,
  ) async {
    // A Mac conversation is mostly read with a wheel or two trackpad fingers,
    // not by dragging the list like a phone — and only the drag was tested.
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);

    await tester.pumpWidget(conversation.surface());
    conversation.completedTurns.value = _turns(20);
    await tester.pump();
    await tester.pump();

    final Offset center = tester.getCenter(
      find.byKey(const Key('conversation-scroll-surface')),
    );
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -240)));
    await tester.pump();

    expect(
      _position(tester).pixels,
      lessThan(_position(tester).maxScrollExtent),
      reason: 'The wheel turned and the conversation did not move.',
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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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

/// More of the agent answering, which is what arrives on its own.
List<Turn> _answers(int count) => <Turn>[
  for (int index = 0; index < count; index += 1)
    Turn(
      role: TurnRole.assistant,
      text: 'A further answer, number $index.',
      status: TurnStatus.completed,
    ),
];

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
