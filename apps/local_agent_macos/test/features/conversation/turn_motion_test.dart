import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_list.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('a question sent into an open conversation rises into place', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface());

    conversation.completedTurns.value = <Turn>[_question('台南今天天氣怎麼樣？')];
    await tester.pump();
    final Finder question = find.text('台南今天天氣怎麼樣？');
    final double arrivingAt = tester.getTopLeft(question).dy;
    expect(_opacityOf(tester, question), lessThan(0.05));

    await tester.pump(const Duration(milliseconds: 400));

    expect(_opacityOf(tester, question), 1);
    expect(arrivingAt - tester.getTopLeft(question).dy, closeTo(14, 0.5));
  });

  testWidgets('turns already there when a conversation opens do not move', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation(
      turns: <Turn>[_question('第一個問題'), _answer('第一個回答'), _question('第二個問題')],
    );
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface());

    expect(_opacityOf(tester, find.text('第二個問題')), 1);

    conversation.completedTurns.value = <Turn>[
      _question('另一段對話'),
      _answer('另一個回答'),
      _question('另一段對話的最後一問'),
    ];
    await tester.pump();

    expect(
      _opacityOf(tester, find.text('另一段對話的最後一問')),
      1,
      reason: 'Opening a conversation is not the user asking something.',
    );
  });

  testWidgets('asking a question again brings the new wording in', (
    WidgetTester tester,
  ) async {
    final Turn earlier = _question('先前的問題');
    final Turn earlierAnswer = _answer('先前的回答');
    final _Conversation conversation = _Conversation(
      turns: <Turn>[
        earlier,
        earlierAnswer,
        _question('打錯的問題'),
        _answer('答非所問'),
      ],
    );
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface());

    conversation.completedTurns.value = <Turn>[
      earlier,
      earlierAnswer,
      _question('改好的問題'),
    ];
    await tester.pump();

    expect(_opacityOf(tester, find.text('改好的問題')), lessThan(0.05));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, find.text('改好的問題')), 1);
  });

  testWidgets('with reduced motion a new question is simply there', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface(disableAnimations: true));

    conversation.completedTurns.value = <Turn>[_question('台南今天天氣怎麼樣？')];
    await tester.pump();

    expect(_opacityOf(tester, find.text('台南今天天氣怎麼樣？')), 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the answer follows its question in, a beat behind', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface());

    conversation.activeTurn.value = _answering('');
    await tester.pump();
    final Finder answer = find.byKey(const Key('active-streaming-markdown'));
    expect(_opacityOf(tester, answer), 0);

    await tester.pump(const Duration(milliseconds: 70));
    expect(
      _opacityOf(tester, answer),
      0,
      reason: 'The answer arrived together with the question.',
    );

    await tester.pump(const Duration(milliseconds: 330));
    expect(_opacityOf(tester, answer), 1);
  });

  testWidgets('the thinking placeholder shimmers until the first word', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface());

    conversation.activeTurn.value = _answering('');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final Finder sweep = find.ancestor(
      of: find.text('Thinking…'),
      matching: find.byType(ShaderMask),
    );
    expect(sweep, findsOneWidget);
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'The wait before the first word was a still line of text.',
    );

    conversation.activeTurn.value = _answering('A');
    await tester.pump();
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'The shimmer went on drawing behind a streaming answer.',
    );
  });

  testWidgets('with reduced motion the placeholder holds still', (
    WidgetTester tester,
  ) async {
    final _Conversation conversation = _Conversation();
    addTearDown(conversation.dispose);
    await tester.pumpWidget(conversation.surface(disableAnimations: true));

    conversation.activeTurn.value = _answering('');
    await tester.pump();
    await tester.pump();

    expect(find.text('Thinking…'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

Turn _answering(String text) =>
    Turn(role: TurnRole.assistant, text: text, status: TurnStatus.streaming);

Turn _answer(String text) =>
    Turn(role: TurnRole.assistant, text: text, status: TurnStatus.completed);

Turn _question(String text) =>
    Turn(role: TurnRole.user, text: text, status: TurnStatus.completed);

/// How opaque [finder] is painted, through every fade above it.
double _opacityOf(WidgetTester tester, Finder finder) {
  double opacity = 1;
  for (final Widget widget in tester.widgetList<Widget>(
    find.ancestor(
      of: finder.first,
      matching: find.byWidgetPredicate(
        (Widget widget) => widget is FadeTransition || widget is Opacity,
      ),
    ),
  )) {
    if (widget is FadeTransition) {
      opacity *= widget.opacity.value;
    } else if (widget is Opacity) {
      opacity *= widget.opacity;
    }
  }
  return opacity;
}

/// Drives a [ConversationList] the way the ViewModel does.
final class _Conversation {
  _Conversation({List<Turn> turns = const <Turn>[]})
    : completedTurns = ValueNotifier<List<Turn>>(turns);

  final ValueNotifier<List<Turn>> completedTurns;
  final ValueNotifier<Turn?> activeTurn = ValueNotifier<Turn?>(null);

  Widget surface({bool disableAnimations = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: ConversationList(
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
