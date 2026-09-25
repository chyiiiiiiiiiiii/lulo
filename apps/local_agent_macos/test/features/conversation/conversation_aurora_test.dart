import 'dart:ui' as ui;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_aurora.dart';

void main() {
  late ui.FragmentProgram program;

  setUp(() async {
    program = await loadConversationAuroraShader();
  });

  testWidgets('the aurora rises while the answer has not begun', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program));
    await tester.pump();

    expect(_aurora, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    active.value = _answering('');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_opacityOf(tester, _aurora), inExclusiveRange(0.2, 0.8));

    await tester.pump(const Duration(milliseconds: 700));
    expect(_opacityOf(tester, _aurora), 1);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('the first word sends it away, and then nothing is drawn', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program));
    await tester.pump(const Duration(milliseconds: 1300));

    active.value = _answering('台');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, _aurora), inExclusiveRange(0.0, 1.0));

    await tester.pump(const Duration(milliseconds: 500));
    expect(_aurora, findsNothing);
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'The sky went on ticking behind an answer being read.',
    );
  });

  testWidgets('it resumes the sky it left rather than where the clock is', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program));
    await tester.pump(const Duration(seconds: 1));
    final double shown = _timeOf(tester);

    active.value = null;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));

    active.value = _answering('');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_timeOf(tester), greaterThan(shown));
    expect(
      _timeOf(tester),
      lessThan(shown + 5),
      reason: 'Ten hidden seconds reached the shader at once.',
    );
  });

  testWidgets('holding to talk raises it, and letting go with nothing asked '
      'lets it go', (WidgetTester tester) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(null);
    final ValueNotifier<bool> holding = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    addTearDown(holding.dispose);
    await tester.pumpWidget(_host(active, program, holding: holding));
    await tester.pump();

    holding.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(_opacityOf(tester, _aurora), 1);

    holding.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(_aurora, findsNothing);
  });

  testWidgets('from holding to talk to the first word, it stays up', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(null);
    final ValueNotifier<bool> holding = ValueNotifier<bool>(true);
    addTearDown(active.dispose);
    addTearDown(holding.dispose);
    await tester.pumpWidget(_host(active, program, holding: holding));
    await tester.pump(const Duration(milliseconds: 1300));

    active.value = _answering('');
    holding.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(_opacityOf(tester, _aurora), 1);
  });

  testWidgets('arriving while an answer is already awaited, it still rises', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(_opacityOf(tester, _aurora), 1);
  });

  testWidgets('with reduced motion nothing is drawn', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program, disableAnimations: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(_aurora, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion turned on takes it away at once', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, program));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(_aurora, findsOneWidget);

    await tester.pumpWidget(_host(active, program, disableAnimations: true));
    await tester.pump();

    expect(_aurora, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a shader that will not load leaves nothing drawn', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Turn?> active = ValueNotifier<Turn?>(_answering(''));
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationAurora(
            activeTurn: active,
            shaderLoader: () => Future<ui.FragmentProgram>.error(
              UnsupportedError('no shader here'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));

    expect(_aurora, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

double _timeOf(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_aurora).painter! as ConversationAuroraPainter)
        .time
        .value;

final Finder _aurora = find.byKey(const Key('conversation-aurora'));

Turn _answering(String text) =>
    Turn(role: TurnRole.assistant, text: text, status: TurnStatus.streaming);

Widget _host(
  ValueNotifier<Turn?> active,
  ui.FragmentProgram program, {
  bool disableAnimations = false,
  ValueNotifier<bool>? holding,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(
      body: ConversationAurora(
        activeTurn: active,
        holdingToTalk: holding,
        shaderLoader: () async => program,
      ),
    ),
  ),
);

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
